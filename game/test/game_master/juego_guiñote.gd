extends Controlador_juego_Base
class_name Juego_Guinote

# SEÑALES PREPARADAS (Para cuando el juego sea interactivo)
signal aviso_puede_cantar(peer_id, palo, es_40)
signal aviso_puede_cambiar_triunfo(peer_id)

var carta_triunfo: Carta
var palo_triunfo 
var baza_actual: Array = [] 

func _ready() -> void:
	cartas_repartir_inicio = 6 

func _iniciar_ronda() -> void:
	carta_triunfo = baraja[0] 
	palo_triunfo = carta_triunfo.palo
	var tapete = get_node("../Tapete")
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
	baza_actual.append({"jugador": jugador, "carta": carta})
	rpc("carta_jugada_en_mesa", jugador.peer_id, carta.id)
	
	if baza_actual.size() == jugadores.size():
		evaluar_baza()
	else:
		pasar_al_siguiente_turno()


func evaluar_baza() -> void:
	# BLOQUEAMOS EL JUEGO: Nadie puede tirar cartas (ni hacer trampas de clics dobles)
	acciones_bloqueadas = true
	
	await get_tree().create_timer(2.0).timeout
	
	var ganadora = baza_actual[0]["carta"]
	var jugador_ganador = baza_actual[0]["jugador"]
	
	for i in range(1, baza_actual.size()):
		var carta_evaluada = baza_actual[i]["carta"]
		var jugador_evaluado = baza_actual[i]["jugador"]
		var supera = false
		
		if carta_evaluada.palo == ganadora.palo:
			if obtener_rango_carta(carta_evaluada) > obtener_rango_carta(ganadora):
				supera = true
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
		# Comprobamos si el jugador ganador puede tomar acciones extra antes de robar
		comprobar_acciones_post_baza(jugador_ganador)
		
		# NOTA: En un futuro, si el jugador tiene acciones extra, no llamaremos a repartir_robo()
		# de inmediato. En su lugar dejaremos `acciones_bloqueadas = true` y esperaremos 
		# a que el jugador pulse "Cantar", "Cambiar Triunfo" o "Pasar y robar".
		# Por ahora, el flujo continúa automáticamente:
		
		repartir_robo(jugador_ganador)
		turno_actual_index = jugadores.find(jugador_ganador)
		actualizar_turno_en_clientes()
	else:
		var juego_terminado = true
		for j in jugadores:
			if j.mano.size() > 0:
				juego_terminado = false
				
		if juego_terminado:
			calcular_puntos_finales(jugador_ganador)
		else:
			turno_actual_index = jugadores.find(jugador_ganador)
			actualizar_turno_en_clientes()
			
	# DESBLOQUEAMOS PARA LA SIGUIENTE RONDA
	if juego_en_curso:
		acciones_bloqueadas = false


func comprobar_acciones_post_baza(jugador: Jugador) -> void:
	# 1. Comprobamos si puede cantar las 40 o las 20 (Rey valor 12, Caballo valor 11)
	var puede_40 = false
	var palos_con_20 = []
	
	
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


func calcular_puntos_finales(ganador_ultimas: Jugador):
	print("\n========== FIN DE LA PARTIDA ==========")
	print("El Jugador ", ganador_ultimas.peer_id, " se lleva las 10 de últimas.")
	
	for j in jugadores:
		var puntos = 0
		for c in j.cartas_ganadas:
			puntos += obtener_puntos_carta(c)
		if j == ganador_ultimas:
			puntos += 10
		print("Jugador ", j.peer_id, " -> PUNTOS TOTALES: ", puntos)
	print("=======================================\n")
	juego_en_curso = false


func repartir_robo(jugador_ganador: Jugador) -> void:
	var index_ganador = jugadores.find(jugador_ganador)
	for i in range(jugadores.size()):
		if baraja.size() == 0: break
		var j = jugadores[(index_ganador + i) % jugadores.size()]
		var nueva_carta = baraja.pop_back()
		j.recibir_carta(nueva_carta)
		rpc_id(j.peer_id, "recibir_mano_inicial", [nueva_carta.id])
		
	var id_fondo = carta_triunfo.id if baraja.size() > 0 else ""
	var tapete = get_node("../Tapete")
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
	var tapete = get_node("../Tapete")
	if tapete and tapete.has_method("limpiar_mesa"):
		tapete.limpiar_mesa()
