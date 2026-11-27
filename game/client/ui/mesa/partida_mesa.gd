extends Control
## Pantalla de partida de los tres juegos (Guiñote, Tute y Mus) a 2 y a 4
## jugadores: la mesa común (tapete_mesa.gd) conectada al servidor de partida
## (PBI-12). Sustituye a las dos pantallas que había solo para el Guiñote.
##
## El canal es el de siempre: `ClienteRed.estado_actualizado` trae la vista del
## jugador con sus `jugadas_validas` y `red.enviar(tipo, payload)` manda lo que
## quiere hacer; aquí nunca se decide si una jugada es válida.
##
## El servidor manda el estado nuevo en cuanto alguien juega. Para que dé
## tiempo a ver lo que ha pasado, esta pantalla enseña los estados de uno en
## uno y hace las pausas que hacía el prototipo unificado: la baza completa se
## queda un momento en la mesa antes de recogerla, y en el Mus se enseñan las
## cartas de todos al acabar cada mano.
##
## Los sonidos (PBI-21) van con lo que se ve: suenan al enseñar cada estado,
## no al recibirlo, y cuáles tocan lo decide sonidos_mesa.gd.

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
const ESCENA_TAPETE := preload("res://client/ui/mesa/tapete_mesa.tscn")
const Textos := preload("res://client/ui/mesa/textos_mesa.gd")
const CuentaAtras := preload("res://client/ui/mesa/cuenta_atras.gd")
const ChatMesa := preload("res://client/ui/mesa/chat_mesa.gd")
const SonidosMesa := preload("res://client/ui/mesa/sonidos_mesa.gd")
const PanelAjustes := preload("res://client/ui/ajustes/panel_ajustes.gd")
const ANUNCIO_PAUSA := "Partida en pausa: denuncia en el chat"

## En el Mus, al acabar cada mano se enseñan las cartas este tiempo (por pausa_baza).
const FACTOR_PAUSA_MANO := 2.5
## La mesa está pensada para esta ventana; si es mayor, se amplía todo en proporción.
const TAMANO_BASE := Vector2i(1152, 648)

## Inyectable en tests (doble), igual que en el resto de pantallas.
var red = ClienteRed
## Igual: el autoload Sonidos (PBI-21) o un doble que apunta lo que suena.
var sonidos = Sonidos
## Segundos que la baza completa se queda a la vista antes de recogerla. Con 0
## no hay pausas (tests).
var pausa_baza := 2.0
## Para probar sin pantalla: la mesa juega sola.
var autojugar := false

var tapete: Control
## Tiempo límite para decidir (PBI-14): cuánto le queda a quien tiene que jugar.
var cuenta_atras: Label
## Chat de la mesa (PBI-08), abajo a la izquierda.
var chat: Control
## Ajustes del cliente (PBI-21); se crea la primera vez que se abre.
var panel_ajustes: AcceptDialog

var _boton_lobby: Button
## Lo que queda por enseñar, en orden: { "estado": … } o { "resultado": … }.
var _cola: Array[Dictionary] = []
var _procesando := false
## El último estado enseñado en la mesa (vista + jugadas_validas + ultima_jugada).
var _estado_en_mesa: Dictionary = {}
var _configurada := false
var _terminada := false
var _juego := ""
var _nombres: Array = []
## Hay una denuncia del chat pendiente: nadie juega hasta que se resuelva.
var _en_pausa := false
## Una denuncia ha pausado la partida: al reanudarse, si te toca, se vuelve a
## avisar (en pausa no suena el turno, y el tuyo pudo llegar entonces).
var _turno_por_avisar := false

## Cómo estaba la ventana antes de abrir la primera mesa, y cuántas hay abiertas
## (en los tests hay varias a la vez): se restaura al cerrar la última.
static var _escala_original: Array = []
static var _mesas_abiertas := 0


func _ready() -> void:
	_ampliar_con_la_ventana()
	tapete = ESCENA_TAPETE.instantiate()
	tapete.name = "Tapete"
	tapete.autojugar = autojugar
	add_child(tapete)
	tapete.jugada_solicitada.connect(_on_jugada_solicitada)
	_crear_cuenta_atras()
	_crear_boton_lobby()
	_crear_chat()

	red.estado_actualizado.connect(_on_estado_recibido)
	red.error_recibido.connect(_on_error_recibido)
	red.partida_terminada.connect(_on_partida_terminada)
	red.desconectado_del_servidor.connect(_on_servidor_perdido)
	red.denuncia_actualizada.connect(_on_denuncia_actualizada)
	# Al reconectarse en plena pausa, la denuncia ya ha llegado (ClienteRed la guarda).
	_en_pausa = not red.denuncia.is_empty()
	_turno_por_avisar = _en_pausa
	# El primer estado suele llegar antes de entrar en esta escena (ClienteRed
	# lo guarda): se pinta lo que ya haya.
	if not red.ultimo_estado.is_empty():
		_on_estado_recibido(red.ultimo_estado)


func _exit_tree() -> void:
	_mesas_abiertas -= 1
	if _mesas_abiertas > 0 or _escala_original.is_empty():
		return
	var ventana := get_window()
	if ventana:
		ventana.content_scale_mode = _escala_original[0]
		ventana.content_scale_aspect = _escala_original[1]
		ventana.content_scale_size = _escala_original[2]
	_escala_original = []


## Como en el prototipo: en una ventana más grande la mesa se ve más grande, no
## más vacía. Solo mientras dura esta pantalla; al salir se deja como estaba.
func _ampliar_con_la_ventana() -> void:
	_mesas_abiertas += 1
	var ventana := get_window()
	if ventana == null or _mesas_abiertas > 1:
		return
	_escala_original = [ventana.content_scale_mode, ventana.content_scale_aspect, ventana.content_scale_size]
	ventana.content_scale_size = TAMANO_BASE
	ventana.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	ventana.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _crear_cuenta_atras() -> void:
	cuenta_atras = CuentaAtras.new()
	cuenta_atras.name = "CuentaAtras"
	cuenta_atras.z_index = 110
	# Bajo la etiqueta de tu nombre, arriba a la izquierda.
	cuenta_atras.position = Vector2(14, 84)
	add_child(cuenta_atras)


func _crear_chat() -> void:
	chat = ChatMesa.new()
	chat.name = "Chat"
	chat.red = red
	add_child(chat)
	chat.configurar(red.config.get("jugadores", []), _mi_asiento())
	chat.ajustes_pulsado.connect(abrir_ajustes)


func abrir_ajustes() -> void:
	if panel_ajustes == null:
		panel_ajustes = PanelAjustes.new()
		panel_ajustes.name = "PanelAjustes"
		add_child(panel_ajustes)
	panel_ajustes.popup_centered()


func _crear_boton_lobby() -> void:
	_boton_lobby = Button.new()
	_boton_lobby.name = "BotonVolverLobby"
	_boton_lobby.text = "Volver al lobby"
	_boton_lobby.custom_minimum_size = Vector2(180, 40)
	_boton_lobby.add_theme_font_size_override("font_size", 22)
	_boton_lobby.visible = false
	_boton_lobby.z_index = 200
	_boton_lobby.pressed.connect(_on_boton_lobby_pressed)
	add_child(_boton_lobby)


# --- Lo que llega del servidor ---

func _on_estado_recibido(estado: Dictionary) -> void:
	# En cuanto llega, no cuando se enseña: el tiempo corre aunque la mesa aún
	# esté mostrando la baza anterior.
	if not _terminada and not _en_pausa:
		cuenta_atras.actualizar(estado, _mi_asiento(), red.config.get("jugadores", []).size())
	_cola.append({"estado": estado})
	_procesar_cola()


func _on_partida_terminada(resultado: Dictionary) -> void:
	_cola.append({"resultado": resultado})
	_procesar_cola()


## El servidor rechaza lo que se ha intentado: se explica, la carta vuelve a la
## mano y se vuelven a ofrecer las jugadas (la mesa quita los botones al pulsar).
func _on_error_recibido(mensaje: String) -> void:
	# La partida ya ha acabado (o su resultado está esperando a enseñarse): lo
	# que se intentó llegó tarde y el error ya no le dice nada al jugador.
	if _terminada or _cola.any(func(pendiente: Dictionary) -> bool: return pendiente.has("resultado")):
		return
	tapete.avisar_error(mensaje)
	tapete.devolver_carta_rechazada()
	if not _procesando and not _terminada and not _estado_en_mesa.is_empty():
		tapete.actualizar_vista(_estado_en_mesa, _jugadas_de(_estado_en_mesa))


## Denuncia del chat (PBI-08): mientras está pendiente, la partida está en
## pausa: no corre la cuenta atrás ni se ofrece ninguna jugada. Al resolverse no
## hay que hacer nada más: si se sigue jugando, el servidor manda un
## estado_partida nuevo, y si se admite, partida_terminada.
func _on_denuncia_actualizada(denuncia: Dictionary) -> void:
	_en_pausa = denuncia.get("estado") == "pendiente" and not _terminada
	if not _en_pausa:
		return
	_turno_por_avisar = true
	cuenta_atras.parar()
	if not _procesando and not _estado_en_mesa.is_empty():
		tapete.actualizar_vista(_estado_en_mesa, [])
	tapete.anunciar(-1, ANUNCIO_PAUSA)


## Lo que se puede hacer con [param estado] en la mesa: nada en pausa.
func _jugadas_de(estado: Dictionary) -> Array:
	return [] if _en_pausa else estado.get("jugadas_validas", [])


func _on_servidor_perdido() -> void:
	if _terminada:
		return
	_cola.clear()
	_terminar("SE HA PERDIDO LA CONEXIÓN\nEl servidor se ha cerrado.")


# --- Enseñar los estados de uno en uno ---

func _procesar_cola() -> void:
	if _procesando:
		return
	_procesando = true
	while not _cola.is_empty() and not _terminada:
		var siguiente: Dictionary = _cola.pop_front()
		if siguiente.has("estado"):
			await _mostrar_estado(siguiente["estado"])
		else:
			_terminar(Textos.resultado(_juego, siguiente["resultado"], _nombres))
	_procesando = false


func _mostrar_estado(estado: Dictionary) -> void:
	if not _configurada:
		_configurar_mesa(estado)
	var anterior := _estado_en_mesa
	var jugada: Dictionary = estado.get("ultima_jugada", {})
	var es_nueva: bool = not anterior.is_empty() and not jugada.is_empty() \
		and jugada.get("numero") != (anterior.get("ultima_jugada", {}) as Dictionary).get("numero")
	var por_sonar := SonidosMesa.sonidos_entre(anterior, estado, _mi_asiento())
	# La carta suena al caer en la mesa; lo demás (robo, turno), al final, con
	# el estado nuevo ya a la vista (tras la pausa de la baza completa, si la hay).
	if por_sonar.has(SonidosMesa.Sonido.CARTA):
		por_sonar.erase(SonidosMesa.Sonido.CARTA)
		sonidos.reproducir(SonidosMesa.Sonido.CARTA)
	if es_nueva:
		await _mostrar_jugada(jugada, anterior, estado)
		if not is_inside_tree() or _terminada:
			return
	tapete.actualizar_vista(estado, _jugadas_de(estado))
	_estado_en_mesa = estado
	_sonar(por_sonar, estado)


## Lo que suena al enseñar [param estado]. En pausa no suena el turno: no se
## puede jugar hasta que se resuelva la denuncia.
func _sonar(por_sonar: Array[String], estado: Dictionary) -> void:
	var turno := SonidosMesa.Sonido.TURNO
	if _en_pausa:
		por_sonar.erase(turno)
	elif _turno_por_avisar:
		_turno_por_avisar = false
		if SonidosMesa.me_toca(estado, _mi_asiento()) and not por_sonar.has(turno):
			por_sonar.append(turno)
	for nombre in por_sonar:
		sonidos.reproducir(nombre)


## Lo que se ve entre el estado anterior y el nuevo: el anuncio de quien ha
## jugado, la baza completa antes de recogerla y, en el Mus, las cartas de todos
## al acabar la mano.
func _mostrar_jugada(jugada: Dictionary, anterior: Dictionary, estado: Dictionary) -> void:
	var quien: int = jugada.get("jugador_id", -1)
	if jugada.get("tipo") == MensajesRed.JUGAR_CARTA:
		var carta: String = jugada.get("carta_id", "")
		if quien == _mi_asiento():
			tapete.confirmar_carta_propia(carta)
		# Con esa carta se ha cerrado la baza: el estado nuevo ya la trae recogida.
		if (estado.get("baza_actual", []) as Array).is_empty():
			tapete.actualizar_vista(_con_la_baza_completa(anterior, quien, carta), [])
			await _pausa(pausa_baza)
	else:
		tapete.anunciar(quien, Textos.anuncio(jugada, anterior, estado))
	if not is_inside_tree():
		return

	if _juego == "mus":
		var ultima_mano: Dictionary = estado.get("ultima_mano", {})
		if not ultima_mano.is_empty() and ultima_mano != anterior.get("ultima_mano", {}):
			tapete.mostrar_fin_de_mano(ultima_mano)
			await _pausa(pausa_baza * FACTOR_PAUSA_MANO)
	elif anterior.get("mano") == "idas" and estado.get("mano") == "vuelta":
		tapete.anunciar(-1, Textos.anuncio_vuelta(estado))
		tapete.actualizar_marcador(Textos.marcador_idas(estado, _nombres))


## La vista de antes de la última carta, con esa carta ya en la baza y sin que
## le toque a nadie: lo que se ve mientras la baza completa sigue en la mesa.
func _con_la_baza_completa(anterior: Dictionary, quien: int, carta: String) -> Dictionary:
	var vista := anterior.duplicate(true)
	var baza: Array = vista.get("baza_actual", [])
	baza.append({"jugador_id": quien, "carta_id": carta})
	vista["baza_actual"] = baza
	if quien == _mi_asiento():
		(vista.get("mi_mano", []) as Array).erase(carta)
	var cartas_por_jugador: Array = vista.get("cartas_por_jugador", [])
	if quien >= 0 and quien < cartas_por_jugador.size():
		cartas_por_jugador[quien] -= 1
	vista["turno"] = -1
	vista["esperando_cambio_siete"] = -1
	return vista


func _pausa(segundos: float) -> void:
	if segundos > 0.0:
		await get_tree().create_timer(segundos).timeout


func _configurar_mesa(estado: Dictionary) -> void:
	var jugadores: Array = red.config.get("jugadores", [])
	_nombres = jugadores.map(func(j: Dictionary) -> String: return str(j.get("nombre", "")))
	_juego = juego_de_mesa(red.config.get("juego", ""), jugadores.size())
	var pinta: Variant = estado.get("pinta")
	# En el Mus no hay pinta, y en vez de quién reparte importa quién es mano.
	var dador: int = estado.get("mano", -1) if _juego == "mus" else estado.get("dador", -1)
	tapete.configurar_mesa(_juego, _nombres, _mi_asiento(), pinta if pinta is String else "", dador)
	_configurada = true


## El juego tal como lo pinta la mesa: el Tute de 2 es otro juego ("tute_dos",
## con mazo, robo y capote) que el Tute por parejas.
static func juego_de_mesa(juego: String, num_jugadores: int) -> String:
	return "tute_dos" if juego == "tute" and num_jugadores == 2 else juego


func _mi_asiento() -> int:
	return red.config.get("tu_posicion", -1)


# --- Lo que hace el jugador ---

func _on_jugada_solicitada(jugada: Dictionary) -> void:
	var payload := jugada.duplicate()
	var tipo: String = payload.get("tipo", "")
	payload.erase("tipo")
	red.enviar(tipo, payload)


# --- Fin de la partida ---

func _terminar(texto: String) -> void:
	_terminada = true
	_en_pausa = false
	cuenta_atras.parar()
	chat.marcar_terminada()
	tapete.mostrar_resultado(texto)
	_boton_lobby.position = Vector2(tapete.get_viewport_rect().size.x - 200.0, 12.0)
	_boton_lobby.show()


func _on_boton_lobby_pressed() -> void:
	red.desconectar()
	get_tree().change_scene_to_file(ESCENA_LOBBY)
