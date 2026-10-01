extends Node
class_name Controlador_juego_Base

const NUM_CARTAS_TOTALES : int = 40
var baraja : Array[Carta] = []
@export_range(1, 40) var cartas_repartir_inicio : int = 5
var num_max_jugadores : int = 4
var path_cartas : String ="res://data/Cartas/"
var jugadores : Array[Jugador] = []
var turno_actual_index : int = 0
var juego_en_curso : bool = false

# NUEVO: Booleano para bloquear acciones (cartas) entre rondas o mientras ocurren eventos
var acciones_bloqueadas : bool = false 

# --- FLUJO PRINCIPAL (Solo se ejecuta en el Servidor) ---

func _ready() -> void:
	pass

func _iniciar_juego() -> void:
	if not multiplayer.is_server(): return
	
	cargar_cartas()
	barajar_cartas()
	repartir_cartas_inicio()
	
	juego_en_curso = true
	turno_actual_index = 0
	acciones_bloqueadas = false
	
	_iniciar_ronda() 
	actualizar_turno_en_clientes()


func cargar_cartas() -> void:
	baraja.clear()
	var valores = ["As", "Dos", "Tres", "Cuatro", "Cinco", "Seis", "Siete", "Sota", "Caballo", "Rey"]
	var palos = ["oros", "copas", "espadas", "bastos"]
	
	for palo in palos:
		for valor in valores:
			var ruta = path_cartas + valor + "_" + palo + ".tres"
			if ResourceLoader.exists(ruta):
				var recurso_carta = load(ruta) as Carta
				if recurso_carta:
					baraja.append(recurso_carta)
			else:
				push_error("No se encontró el archivo: " + ruta)
	print("Se han cargado ", baraja.size(), " cartas en la baraja.")

func barajar_cartas() -> void:
	randomize()
	baraja.shuffle()

func repartir_cartas_inicio(num_cartas : int = cartas_repartir_inicio) -> void:
	for jugador in jugadores:
		jugador.vaciar_mano()
		var ids_repartidas : Array[String] = []
		for i in range(num_cartas):
			if baraja.size() > 0:
				var carta = baraja.pop_back()
				jugador.recibir_carta(carta)
				ids_repartidas.append(carta.id)
		rpc_id(jugador.peer_id, "recibir_mano_inicial", ids_repartidas)


# --- COMUNICACIÓN CLIENTE -> SERVIDOR ---

@rpc("any_peer", "call_remote", "reliable")
func intentar_jugar_carta(id_carta: String) -> void:
	if not multiplayer.is_server() or not juego_en_curso: return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var jugador = obtener_jugador_por_id(sender_id)
	
	if jugador == null: return
	
	# --- NUEVO: Evitamos que jueguen cartas si el servidor está bloqueado (evaluando baza) ---
	if acciones_bloqueadas:
		rpc_id(sender_id, "mostrar_mensaje_error", "Espera a que termine la acción actual.")
		rpc_id(sender_id, "jugada_rechazada", id_carta)
		return
	
	if jugadores[turno_actual_index] != jugador:
		rpc_id(sender_id, "mostrar_mensaje_error", "No es tu turno.")
		rpc_id(sender_id, "jugada_rechazada", id_carta)
		return
	
	var carta = jugador.obtener_carta_por_id(id_carta)
	if carta == null:
		rpc_id(sender_id, "mostrar_mensaje_error", "No tienes esa carta.")
		return
	
	if _es_jugada_valida(jugador, carta):
		jugador.quitar_carta(carta)
		_procesar_jugada(jugador, carta)
	else:
		rpc_id(sender_id, "jugada_rechazada", id_carta)


# --- HELPERS ---
func obtener_jugador_por_id(peer_id: int) -> Jugador:
	for j in jugadores:
		if j.peer_id == peer_id: return j
	return null

func pasar_al_siguiente_turno() -> void:
	turno_actual_index = (turno_actual_index + 1) % jugadores.size()
	actualizar_turno_en_clientes()

func actualizar_turno_en_clientes() -> void:
	var id_jugador_activo = jugadores[turno_actual_index].peer_id
	rpc("sincronizar_turno", id_jugador_activo)


# ==========================================
# MÉTODOS VIRTUALES 
# ==========================================
func _iniciar_ronda() -> void: pass
func _es_jugada_valida(jugador: Jugador, carta: Carta) -> bool: return true
func _procesar_jugada(jugador: Jugador, carta: Carta) -> void:
	rpc("carta_jugada_en_mesa", jugador.peer_id, carta.id)
	pasar_al_siguiente_turno()


# ==========================================
# RPCS (Visuales del cliente)
# ==========================================
@rpc("authority", "call_remote", "reliable")
func recibir_mano_inicial(cartas_ids: Array):
	var tapete = get_node("../Tapete")
	if tapete: tapete.generar_mano_desde_array(cartas_ids)

@rpc("authority", "call_remote", "reliable")
func carta_jugada_en_mesa(peer_id_jugador: int, id_carta: String):
	var tapete = get_node("../Tapete")
	if tapete: tapete.mostrar_carta_jugada_por_rival(peer_id_jugador, id_carta)

@rpc("authority", "call_remote", "reliable")
func sincronizar_turno(peer_id_activo: int):
	var tapete = get_node("../Tapete")
	if tapete: tapete.actualizar_interfaz_turno(peer_id_activo)

@rpc("authority", "call_remote", "reliable")
func mostrar_mensaje_error(mensaje: String):
	print("Servidor informa: ", mensaje)

@rpc("authority", "call_remote", "reliable")
func jugada_rechazada(id_carta: String):
	var tapete = get_node("../Tapete")
	if tapete: tapete.devolver_carta_rechazada(id_carta)
