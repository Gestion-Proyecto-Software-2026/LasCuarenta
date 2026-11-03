extends Controlador_juego_Base
class_name Juego_Guinote

# SEÑALES PREPARADAS (Para cuando el juego sea interactivo)
signal aviso_puede_cantar(peer_id, palo, es_40)
signal aviso_puede_cambiar_triunfo(peer_id)

var carta_triunfo: Carta
var palo_triunfo 
var baza_actual: Array = [] 
var palos_cantados: Array = []

func _ready() -> void:
	cartas_repartir_inicio = 6 

func _iniciar_ronda() -> void:
	carta_triunfo = baraja[0] 
	palo_triunfo = carta_triunfo.palo
	var tapete = get_node_or_null("../Tapete")
	if tapete:
		tapete.rpc("sincronizar_mazo", baraja.size(), carta_triunfo.id)


func _es_jugada_valida(jugador: Jugador, carta: Carta) -> bool:
	if baraja.size() > 0:
		return true
		
	if baza_actual.size() == 0:
		return true 
		
	var palo_salida = baza_actual[0]["carta"].palo
	
	var ganadora = baza_actual[0]["carta"]
	for i in range(1, baza_actual.size()):
		var c_eval = baza_actual[i]["carta"]
		if c_eval.palo == ganadora.palo and obtener_rango_carta(c_eval) > obtener_rango_carta(ganadora):
			ganadora = c_eval
		elif c_eval.palo == palo_triunfo and ganadora.palo != palo_triunfo:
			ganadora = c_eval
			
	var tiene_palo_salida = false
	var puede_montar_salida = false
	var tiene_triunfo = false
	var puede_montar_triunfo = false
	
	for c in jugador.mano:
		if c.palo == palo_salida:
			tiene_palo_salida = true
			if ganadora.palo == palo_salida and obtener_rango_carta(c) > obtener_rango_carta(ganadora):
				puede_montar_salida = true
				
		if c.palo == palo_triunfo:
			tiene_triunfo = true
			if ganadora.palo == palo_triunfo and obtener_rango_carta(c) > obtener_rango_carta(ganadora):
				puede_montar_triunfo = true
			elif ganadora.palo != palo_triunfo:
				puede_montar_triunfo = true

	# Reglas estrictas de arrastre
	if tiene_palo_salida:
		if carta.palo != palo_salida:
			return false 
		if puede_montar_salida and obtener_rango_carta(carta) <= obtener_rango_carta(ganadora):
			return false
	elif tiene_triunfo:
		if carta.palo != palo_triunfo:
			return false
		if ganadora.palo == palo_triunfo and puede_montar_triunfo and obtener_rango_carta(carta) <= obtener_rango_carta(ganadora):
			return false
			
	return true


func _procesar_jugada(jugador: Jugador, carta: Carta) -> void:
	# Si lanza una carta, pierde la oportunidad de cantar o cambiar en este turno
	jugador.cantes_pendientes.clear()
	jugador.puede_cambiar_triunfo_pendiente = false
	var tapete = get_node_or_null("../Tapete")
	if tapete: tapete.rpc_id(jugador.peer_id, "desactivar_acciones_post_baza")
	
	baza_actual.append({"jugador": jugador, "carta": carta})
	rpc("carta_jugada_en_mesa", jugador.peer_id, carta.id)
	
	if baza_actual.size() == jugadores.size(): evaluar_baza()
	else: pasar_al_siguiente_turno()

func evaluar_baza() -> void:
	acciones_bloqueadas = true
	await get_tree().create_timer(2.0).timeout
	
	var ganadora = baza_actual[0]["carta"]
	var jugador_ganador = baza_actual[0]["jugador"]
	
	for i in range(1, baza_actual.size()):
		var carta_evaluada = baza_actual[i]["carta"]
		var jugador_evaluado = baza_actual[i]["jugador"]
		var supera = false
		
		if carta_evaluada.palo == ganadora.palo:
			if obtener_rango_carta(carta_evaluada) > obtener_rango_carta(ganadora): supera = true
		elif carta_evaluada.palo == palo_triunfo and ganadora.palo != palo_triunfo:
			supera = true
			
		if supera:
			ganadora = carta_evaluada
			jugador_ganador = jugador_evaluado

	for jugada in baza_actual:
		jugador_ganador.cartas_ganadas.append(jugada["carta"])

	rpc("limpiar_mesa_clientes")
	baza_actual.clear()
	
	if baraja.size() > 0:
		# 1. Miramos qué puede hacer con la mano ANTES de robar
		evaluar_acciones_previas_al_robo(jugador_ganador)
		
		# 2. Comprobamos si es el ÚLTIMO robo (quedan tantas cartas como jugadores)
		if baraja.size() == jugadores.size() and (jugador_ganador.cantes_pendientes.size() > 0 or jugador_ganador.puede_cambiar_triunfo_pendiente):
			# Pausamos el robo y esperamos a que el jugador tome una decisión (Cambiar, Cantar o Pasar)
			jugador_ganador.esperando_decision_antes_de_robar = true
			var tapete = get_node_or_null("../Tapete")
			if tapete:
				tapete.rpc_id(jugador_ganador.peer_id, "mostrar_botones_ultimo_robo", jugador_ganador.cantes_pendientes.size() > 0, jugador_ganador.puede_cambiar_triunfo_pendiente)
		else:
			# Flujo normal para el resto de la partida (robamos directamente)
			ejecutar_flujo_robo_normal(jugador_ganador)
	else:
		var juego_terminado = true
		for j in jugadores:
			if j.mano.size() > 0: juego_terminado = false
				
		if juego_terminado: calcular_puntos_finales(jugador_ganador)
		else:
			turno_actual_index = jugadores.find(jugador_ganador)
			actualizar_turno_en_clientes()
			
	if juego_en_curso and not jugador_ganador.esperando_decision_antes_de_robar:
		acciones_bloqueadas = false

func ejecutar_flujo_robo_normal(jugador: Jugador) -> void:
	repartir_robo(jugador)
	
	# Si la baraja NO está vacía, no era el último robo. Por tanto, mostramos los botones de cantar DESPUÉS de robar.
	# (Al vaciarse la baraja con el último robo, esto no se ejecutará, evitando cantes post-robo)
	if baraja.size() > 0:
		notificar_acciones_disponibles(jugador)
		
	turno_actual_index = jugadores.find(jugador)
	actualizar_turno_en_clientes()
	
	if juego_en_curso:
		acciones_bloqueadas = false

@rpc("any_peer", "call_local", "reliable")
func pasar_decision_antes_de_robar():
	var id_remitente = multiplayer.get_remote_sender_id()
	var jugador = obtener_jugador_por_id(id_remitente)
	
	# Si pulsó el botón "Pasar", retomamos el flujo para robar las últimas cartas
	if jugador and jugador.esperando_decision_antes_de_robar:
		jugador.esperando_decision_antes_de_robar = false
		ejecutar_flujo_robo_normal(jugador)

func evaluar_acciones_previas_al_robo(jugador: Jugador) -> void:
	jugador.cantes_pendientes.clear()
	jugador.puede_cambiar_triunfo_pendiente = false
	
	if baraja.size() > 0:
		# 1. Comprobamos Cantes (Mirando sólo la mano ANTES de robar)
		for p in range(4):
			if palos_cantados.has(p): continue # Ya se ha cantado este palo en la partida
			var tiene_rey = false
			var tiene_sota = false
			for c in jugador.mano:
				if c.palo == p and c.valor == 12: tiene_rey = true
				if c.palo == p and c.valor == 10: tiene_sota = true
			if tiene_rey and tiene_sota:
				jugador.cantes_pendientes.append(p)
				
		# 2. Comprobamos Triunfo
		if carta_triunfo != null:
			var tiene_siete = false
			for c in jugador.mano:
				if c.palo == palo_triunfo and c.valor == 7:
					tiene_siete = true
					break
			if tiene_siete and obtener_rango_carta(carta_triunfo) > 5:
				jugador.puede_cambiar_triunfo_pendiente = true

func notificar_acciones_disponibles(jugador: Jugador) -> void:
	var puede_cantar = jugador.cantes_pendientes.size() > 0
	var puede_cambiar = jugador.puede_cambiar_triunfo_pendiente
	
	var tapete = get_node_or_null("../Tapete")
	if tapete and (puede_cantar or puede_cambiar):
		tapete.rpc_id(jugador.peer_id, "activar_acciones_post_baza", puede_cantar, puede_cambiar)

func continuar_flujo_robo(jugador_ganador: Jugador):
	repartir_robo(jugador_ganador)
	turno_actual_index = jugadores.find(jugador_ganador)
	actualizar_turno_en_clientes()
	if juego_en_curso:
		acciones_bloqueadas = false

func comprobar_acciones_post_baza(jugador: Jugador) -> bool:
	# 1. Comprobamos si puede cantar las 40 o las 20 (Rey valor 12, Caballo valor 11)
	var puede_40 = false
	var palos_con_20 = []
	var puede_cantar = false
	var puede_cambiar = false
	
	for p in range(4):
		var tiene_rey = false
		var tiene_sota = false
		for c in jugador.mano:
			if c.palo == p and c.valor == 12: tiene_rey = true
			if c.palo == p and c.valor == 10: tiene_sota = true
			
		if tiene_rey and tiene_sota:
			if p == palo_triunfo:
				puede_40 = true
			else:
				palos_con_20.append(p)
				
	if puede_40:
		print("== Jugador ", jugador.peer_id, " puede cantar las cuarenta (", palo_triunfo, ") ==")
		emit_signal("aviso_puede_cantar", jugador.peer_id, palo_triunfo, true)
		
	for p in palos_con_20:
		print("== Jugador ", jugador.peer_id, " puede cantar las veinte (", p, ") ==")
		emit_signal("aviso_puede_cantar", jugador.peer_id, p, false)
		
	# 2. Comprobamos si puede intercambiar el 7 de Triunfo (Valor del 7 = 7)
	if carta_triunfo != null and baraja.size() > 0:
		var tiene_siete = false
		for c in jugador.mano:
			if c.palo == palo_triunfo and c.valor == 7:
				tiene_siete = true
				break
				
		if tiene_siete:
			# El 7 en jerarquía es el rango 5. Solo se puede cambiar por uno mayor a 5 
			# (Sota(6), Caballo(7), Rey(8), Tres(9), As(10)). 
			if obtener_rango_carta(carta_triunfo) > 5:
				print("== Jugador ", jugador.peer_id, " puede intercambiar el Triunfo ==")
				emit_signal("aviso_puede_cambiar_triunfo", jugador.peer_id)
	if puede_40 or palos_con_20.size() > 0:
		puede_cantar = true
		
	# Lógica del 7:
	if carta_triunfo != null and baraja.size() > 0:
		var tiene_siete = false
		for c in jugador.mano:
			if c.palo == palo_triunfo and c.valor == 7:
				tiene_siete = true
				break
		if tiene_siete and obtener_rango_carta(carta_triunfo) > 5:
			puede_cambiar = true

	# Mandamos la orden visual al cliente de ese jugador específico
	var tapete = get_node_or_null("../Tapete")
	if tapete:
		tapete.rpc_id(jugador.peer_id, "activar_acciones_post_baza", puede_cantar, puede_cambiar)
		
	return puede_cantar or puede_cambiar

func calcular_puntos_finales(ganador_ultimas: Jugador):
	print("\n========== FIN DE LA PARTIDA ==========")
	for j in jugadores:
		var puntos = j.puntos_cantes # Sumamos los cantes
		for c in j.cartas_ganadas:
			puntos += obtener_puntos_carta(c)
		if j == ganador_ultimas:
			puntos += 10
		print("Jugador ", j.peer_id, " -> PUNTOS TOTALES: ", puntos)
	print("=======================================\n")
	juego_en_curso = false


@rpc("any_peer", "call_local", "reliable")
func ejecutar_cambiar_triunfo():
	var id_remitente = multiplayer.get_remote_sender_id()
	var jugador = obtener_jugador_por_id(id_remitente)
	
	if not jugador or not jugador.puede_cambiar_triunfo_pendiente: return
	
	var carta_siete = null
	for c in jugador.mano:
		if c.palo == palo_triunfo and c.valor == 7:
			carta_siete = c
			break
			
	if carta_siete and carta_triunfo:
		jugador.quitar_carta(carta_siete)
		jugador.recibir_carta(carta_triunfo)
		
		var triunfo_anterior = carta_triunfo
		carta_triunfo = carta_siete
		jugador.puede_cambiar_triunfo_pendiente = false
		
		#cambiamos la carta del mazo por el siete de triunfo
		if baraja.size() > 0:
			baraja[0] = carta_siete
		# Avisamos al cliente de que actualice la imagen de su carta visualmente
		var tapete = get_node_or_null("../Tapete")
		if tapete:
			tapete.rpc_id(jugador.peer_id, "actualizar_mano_cambio_triunfo", carta_siete.id, triunfo_anterior.id)
			tapete.rpc("sincronizar_mazo", baraja.size(), carta_triunfo.id)
			
		if jugador.esperando_decision_antes_de_robar and jugador.cantes_pendientes.size() == 0:
			jugador.esperando_decision_antes_de_robar = false
			ejecutar_flujo_robo_normal(jugador)
			if tapete: tapete.rpc_id(jugador.peer_id, "ocultar_boton_pasar")

@rpc("any_peer", "call_local", "reliable")
func ejecutar_cantar():
	var id_remitente = multiplayer.get_remote_sender_id()
	var jugador = obtener_jugador_por_id(id_remitente)
	
	if not jugador or jugador.cantes_pendientes.size() == 0: return
	
	for palo in jugador.cantes_pendientes:
		if palos_cantados.has(palo): continue
		palos_cantados.append(palo)
		
		var puntos = 40 if palo == palo_triunfo else 20
		jugador.puntos_cantes += puntos
		print("Jugador ", jugador.peer_id, " canta las ", puntos)
		
	jugador.cantes_pendientes.clear()
	
	var tapete = get_node_or_null("../Tapete")
	if tapete:
		tapete.rpc_id(jugador.peer_id, "desactivar_boton_cantar")
	if jugador.esperando_decision_antes_de_robar and not jugador.puede_cambiar_triunfo_pendiente:
		jugador.esperando_decision_antes_de_robar = false
		ejecutar_flujo_robo_normal(jugador)
		if tapete: tapete.rpc_id(jugador.peer_id, "ocultar_boton_pasar")

func repartir_robo(jugador_ganador: Jugador) -> void:
	print("llamo a esta función una vez") 
	var index_ganador = jugadores.find(jugador_ganador)
	for i in range(jugadores.size()):
		
		if baraja.size() == 0: break
		var j = jugadores[(index_ganador + i) % jugadores.size()]
		var nueva_carta = baraja.pop_back()
		j.recibir_carta(nueva_carta)
		rpc_id(j.peer_id, "recibir_mano_inicial", [nueva_carta.id])
		
	var id_fondo = carta_triunfo.id if baraja.size() > 0 else ""
	var tapete = get_node_or_null("../Tapete")
	if tapete: tapete.rpc("sincronizar_mazo", baraja.size(), id_fondo)

func obtener_rango_carta(carta: Carta) -> int:
	match carta.valor:
		1: return 10
		3: return 9
		12: return 8
		11: return 6
		10: return 7
		7: return 5
		6: return 4
		5: return 3
		4: return 2
		2: return 1
		_: return 0

func obtener_puntos_carta(carta: Carta) -> int:
	match carta.valor:
		1: return 11 
		3: return 10 
		12: return 4  
		11: return 2  
		10: return 3  
		_: return 0   

@rpc("authority", "call_remote", "reliable")
func limpiar_mesa_clientes():
	var tapete = get_node_or_null("../Tapete")
	if tapete and tapete.has_method("limpiar_mesa"):
		tapete.limpiar_mesa()
