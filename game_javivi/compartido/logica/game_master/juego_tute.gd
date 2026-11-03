extends Controlador_juego_Base
class_name Juego_Tute
## Tute por parejas para 4 jugadores (§10 del análisis funcional del equipo),
## montado sobre el controlador de red del prototipo de Javier.
##
## Todo lo que decide la partida corre en el servidor, que no juega: los
## clientes solo proponen jugadas. Las reglas están en ReglasTute, sin red,
## para poder probarlas con GUT.
##
## Diferencias con Juego_Guinote: 10 cartas cada uno y ninguna en el mazo, la
## pinta es la última carta del dador, arrastre obligatorio desde la primera
## baza (asistir, montar, fallar y pisar), cantes de Rey y Caballo, Tute de
## reyes o caballos, y tanteo por parejas.

## Lo que va pasando en la partida, para que el servidor lo muestre.
signal aviso_emitido(texto: String)
signal partida_terminada(texto: String)

var carta_triunfo: Carta = null
var palo_triunfo: int = -1
## Asiento del dador; sale el jugador de su derecha.
var dador: int = 0
## Cartas de la baza en curso: [{ "jugador": Jugador, "carta": Carta }].
var baza_actual: Array = []
var bazas_por_pareja := [0, 0]
var palos_cantados: Array = []
var ultimo_ganador: Jugador = null
## Segundos que la baza completa se queda a la vista antes de recogerla.
var pausa_baza: float = 2.0
## Con una semilla (>= 0) el barajado y el dador salen siempre igual, para
## poder repetir una partida al probar. -1 = al azar, que es lo normal.
var semilla: int = -1

var _tapete: Node


func _ready() -> void:
	cartas_repartir_inicio = ReglasTute.CARTAS_POR_JUGADOR
	num_max_jugadores = ReglasTute.JUGADORES
	_tapete = get_node_or_null("../Tapete")


# --- FLUJO PRINCIPAL (solo en el servidor) ---

func _iniciar_juego() -> void:
	if not multiplayer.is_server():
		return
	if jugadores.size() != ReglasTute.JUGADORES:
		push_error("El Tute por parejas necesita %d jugadores y hay %d." % [ReglasTute.JUGADORES, jugadores.size()])
		return
	cargar_cartas()
	barajar_cartas()
	_repartir()
	juego_en_curso = true
	acciones_bloqueadas = false
	turno_actual_index = (dador + 1) % jugadores.size()
	_actualizar_marcador()
	actualizar_turno_en_clientes()


func barajar_cartas() -> void:
	if semilla < 0:
		super()
		return
	seed(semilla)
	baraja.shuffle()


func _repartir() -> void:
	for jugador in jugadores:
		jugador.vaciar_mano()
	baza_actual.clear()
	palos_cantados.clear()
	bazas_por_pareja = [0, 0]
	ultimo_ganador = null
	dador = randi() % jugadores.size()

	var manos := ReglasTute.repartir(baraja, dador, jugadores.size())
	baraja.clear()
	for asiento in jugadores.size():
		for carta in manos[asiento]:
			jugadores[asiento].recibir_carta(carta)
	# La última carta del reparto es del dador y se vuelve boca arriba: es la pinta.
	carta_triunfo = jugadores[dador].mano.back()
	palo_triunfo = carta_triunfo.palo

	var peers: Array = []
	var nombres: Array = []
	for jugador in jugadores:
		peers.append(jugador.peer_id)
		nombres.append(jugador.nombre)
	if _tapete:
		_tapete.rpc("configurar_mesa", peers, nombres, carta_triunfo.id, jugadores[dador].peer_id)
		_tapete.rpc("sincronizar_mazo", 1, carta_triunfo.id)
	for jugador in jugadores:
		var ids: Array = []
		for carta in jugador.mano:
			ids.append(carta.id)
		rpc_id(jugador.peer_id, "recibir_mano_inicial", ids)

	_avisar_todos("Reparte %s. Triunfo: %s (la pinta es el %s). Sale %s." % [
		jugadores[dador].nombre, ReglasTute.nombre_palo(palo_triunfo),
		ReglasTute.nombre_carta(carta_triunfo), jugadores[(dador + 1) % jugadores.size()].nombre])


func _es_jugada_valida(jugador: Jugador, carta: Carta) -> bool:
	var motivo := ReglasTute.motivo_rechazo(jugador.mano, _cartas_baza(), palo_triunfo, carta)
	if motivo == "":
		return true
	# Además de rechazarla, le decimos por qué: el arrastre no es evidente.
	_avisar(jugador, motivo)
	return false


func _procesar_jugada(jugador: Jugador, carta: Carta) -> void:
	# Al echar carta se pierde el cante que tuviera pendiente de la baza anterior.
	jugador.cantes_pendientes.clear()
	if _tapete:
		_tapete.rpc_id(jugador.peer_id, "desactivar_acciones_post_baza")
	baza_actual.append({"jugador": jugador, "carta": carta})
	rpc("carta_jugada_en_mesa", jugador.peer_id, carta.id)
	if baza_actual.size() == jugadores.size():
		evaluar_baza()
	else:
		pasar_al_siguiente_turno()


func evaluar_baza() -> void:
	acciones_bloqueadas = true
	await get_tree().create_timer(pausa_baza).timeout
	if not juego_en_curso:
		return

	var indice := ReglasTute.indice_ganador(_cartas_baza(), palo_triunfo)
	var ganador: Jugador = baza_actual[indice]["jugador"]
	var carta_ganadora: Carta = baza_actual[indice]["carta"]
	for jugada in baza_actual:
		ganador.cartas_ganadas.append(jugada["carta"])
	var asiento := jugadores.find(ganador)
	var pareja := ReglasTute.equipo(asiento)
	bazas_por_pareja[pareja] += 1
	ultimo_ganador = ganador
	baza_actual.clear()
	rpc("limpiar_mesa_clientes")

	var bazas: int = bazas_por_pareja[0] + bazas_por_pareja[1]
	_avisar_todos("Baza %d para %s (%s) con el %s." % [
		bazas, ganador.nombre, ReglasTute.NOMBRE_PAREJA[pareja], ReglasTute.nombre_carta(carta_ganadora)])

	if jugadores.all(func(j): return j.mano.is_empty()):
		_terminar_por_tantos()
		return

	_ofrecer_cantes(asiento)
	_actualizar_marcador()
	turno_actual_index = asiento
	acciones_bloqueadas = false
	actualizar_turno_en_clientes()


## Tras ganar una baza, el ganador y su compañero pueden cantar un acuse cada uno.
func _ofrecer_cantes(asiento_ganador: int) -> void:
	for jugador in jugadores:
		jugador.cantes_pendientes.clear()
	for asiento in [asiento_ganador, ReglasTute.companero(asiento_ganador)]:
		var jugador: Jugador = jugadores[asiento]
		var opcion := ReglasTute.mejor_cante(jugador.mano, palo_triunfo, palos_cantados)
		if opcion.is_empty():
			continue
		jugador.cantes_pendientes.append(opcion)
		if _tapete:
			_tapete.rpc_id(jugador.peer_id, "ofrecer_cante", ReglasTute.texto_cante(opcion))


# --- COMUNICACIÓN CLIENTE -> SERVIDOR ---

@rpc("any_peer", "call_remote", "reliable")
func ejecutar_cantar() -> void:
	if not multiplayer.is_server() or not juego_en_curso:
		return
	var jugador := obtener_jugador_por_id(multiplayer.get_remote_sender_id())
	if jugador == null or jugador.cantes_pendientes.is_empty():
		return
	var opcion: Dictionary = jugador.cantes_pendientes.pop_front()
	jugador.cantes_pendientes.clear()
	if _tapete:
		_tapete.rpc_id(jugador.peer_id, "desactivar_boton_cantar")

	var asiento := jugadores.find(jugador)
	if opcion["tipo"] == "tute":
		var figura := String(opcion["figura"])
		_terminar("¡%s canta TUTE DE %s!\nGana la %s." % [
				jugador.nombre, figura.to_upper(), ReglasTute.NOMBRE_PAREJA[ReglasTute.equipo(asiento)]],
			ReglasTute.equipo(asiento), "motivo=tute | figura=%s | asiento=%d" % [figura, asiento])
		return

	var palo: int = opcion["palo"]
	if palos_cantados.has(palo):
		return
	palos_cantados.append(palo)
	jugador.puntos_cantes += opcion["puntos"]
	if opcion["puntos"] == ReglasTute.PUNTOS_CUARENTA:
		_avisar_todos("%s canta las 40 en %s." % [jugador.nombre, ReglasTute.nombre_palo(palo)])
	else:
		_avisar_todos("%s canta las 20 en %s." % [jugador.nombre, ReglasTute.nombre_palo(palo)])
	_actualizar_marcador()


# --- RPCS (visuales del cliente) ---

@rpc("authority", "call_remote", "reliable")
func limpiar_mesa_clientes() -> void:
	if _tapete and _tapete.has_method("limpiar_mesa"):
		_tapete.limpiar_mesa()


# --- FIN DE LA PARTIDA ---

func _terminar_por_tantos() -> void:
	var cartas_por_asiento: Array = []
	var cantes_por_asiento: Array = []
	for jugador in jugadores:
		cartas_por_asiento.append(jugador.cartas_ganadas)
		cantes_por_asiento.append(jugador.puntos_cantes)
	var t := ReglasTute.tanteo(cartas_por_asiento, cantes_por_asiento, jugadores.find(ultimo_ganador))
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	for pareja in 2:
		lineas.append("%s (%s): %d tantos = cartas %d + cantes %d + últimas %d" % [
			ReglasTute.NOMBRE_PAREJA[pareja].capitalize(), _miembros(pareja), t["total"][pareja],
			t["cartas"][pareja], t["cantes"][pareja], t["ultimas"][pareja]])
	lineas.append("Gana la %s." % ReglasTute.NOMBRE_PAREJA[t["ganador"]])
	_terminar("\n".join(lineas), t["ganador"],
		"motivo=tantos | cartas=%d-%d | cantes=%d-%d | ultimas=%d-%d | total=%d-%d" % [
			t["cartas"][0], t["cartas"][1], t["cantes"][0], t["cantes"][1],
			t["ultimas"][0], t["ultimas"][1], t["total"][0], t["total"][1]])


func _terminar(texto: String, pareja: int, detalle: String) -> void:
	juego_en_curso = false
	acciones_bloqueadas = true
	for jugador in jugadores:
		jugador.cantes_pendientes.clear()
	if _tapete:
		_tapete.rpc("mostrar_resultado", texto)
	print("FIN TUTE | ganadora=%s | %s" % ["AB"[pareja], detalle])
	aviso_emitido.emit(texto)
	partida_terminada.emit(texto)


# --- HELPERS ---

## Además del turno, le manda al jugador activo qué cartas puede echar.
func actualizar_turno_en_clientes() -> void:
	super()
	if not _tapete or not juego_en_curso:
		return
	var activo: Jugador = jugadores[turno_actual_index]
	var ids: Array = []
	for carta in ReglasTute.cartas_permitidas(activo.mano, _cartas_baza(), palo_triunfo):
		ids.append(carta.id)
	for jugador in jugadores:
		_tapete.rpc_id(jugador.peer_id, "marcar_cartas_jugables", ids if jugador == activo else [])


func _cartas_baza() -> Array:
	var cartas: Array = []
	for jugada in baza_actual:
		cartas.append(jugada["carta"])
	return cartas


func _miembros(pareja: int) -> String:
	return "%s y %s" % [jugadores[pareja].nombre, jugadores[pareja + 2].nombre]


func _actualizar_marcador() -> void:
	var cantes := [0, 0]
	for asiento in jugadores.size():
		cantes[ReglasTute.equipo(asiento)] += jugadores[asiento].puntos_cantes
	var lineas := PackedStringArray()
	for pareja in 2:
		lineas.append("%s (%s): %d bazas, %d de cantes" % [
			ReglasTute.NOMBRE_PAREJA[pareja].capitalize(), _miembros(pareja),
			bazas_por_pareja[pareja], cantes[pareja]])
	if _tapete:
		_tapete.rpc("actualizar_marcador", "\n".join(lineas))


func _avisar_todos(texto: String) -> void:
	print("[TUTE] ", texto)
	if _tapete:
		_tapete.rpc("mostrar_aviso", texto)
	aviso_emitido.emit(texto)


func _avisar(jugador: Jugador, texto: String) -> void:
	if _tapete:
		_tapete.rpc_id(jugador.peer_id, "mostrar_aviso", texto)
