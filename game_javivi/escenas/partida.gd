extends Node
## Partida de cualquiera de los modos de [Modos] sobre el prototipo de red de
## Javier: una ventana hace de servidor dedicado (no juega) y las demás de jugadores.
## Generaliza test_escenas/main_tute.gd: el controlador y el número de jugadores
## salen del modo elegido en el menú.
##
## Argumentos opcionales de cada instancia, detrás de "--":
##   modo=ID              modo de Modos.LISTA (si no, el elegido en el menú)
##   servidor | cliente   arranca sin pulsar botones
##   autojugar            el cliente juega solo (para probar sin pantalla)
##   no_cantar            con autojugar, nunca canta ni cambia la pinta
##   pausa_corta          el servidor recoge cada baza en 0,2 s en vez de 2 s
##   salir_al_terminar    la instancia se cierra al acabar la partida
##   puerto=NNNN          usa otro puerto (por defecto, el del modo)
##   semilla=N            reparto reproducible (siempre la misma partida)
##   captura=RUTA.png     el cliente guarda una captura de la mesa a los pocos segundos

const DIRECCION := "127.0.0.1"
const MAX_REINTENTOS := 10
const ESCENA_TAPETE := preload("res://compartido/Escenas/tapete/Tapete.tscn")
const ESCENA_MENU := "res://escenas/menu.tscn"
const SEGUNDOS_HASTA_CAPTURA := 7.0

var modo: Dictionary
## Juego_Tute o Juego_Motor (sin tipo: cada uno tiene sus propias propiedades, como la semilla).
var controlador
var tapete: Control

var _botones: Control
var _estado: Label
var _boton_menu: Button
var _args := PackedStringArray()
var _reintentos := 0
var _puerto := 0
var _jugadores := 0


func _ready() -> void:
	_args = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	modo = Modos.elegido
	for arg in _args:
		if arg.begins_with("modo="):
			modo = Modos.buscar(arg.trim_prefix("modo="))
	if modo.is_empty() or not Modos.disponible(modo):
		get_tree().change_scene_to_file.call_deferred(ESCENA_MENU)
		return
	_jugadores = modo["jugadores"]
	_puerto = modo["puerto"]

	tapete = ESCENA_TAPETE.instantiate()
	tapete.name = "Tapete"
	tapete.visible = false
	add_child(tapete)
	controlador = _crear_controlador()
	controlador.name = "juego"
	add_child(controlador)
	_construir_pantalla()

	multiplayer.peer_connected.connect(_on_jugador_conectado)
	multiplayer.peer_disconnected.connect(_on_jugador_desconectado)
	multiplayer.connected_to_server.connect(_on_conectado_al_servidor)
	multiplayer.connection_failed.connect(_on_conexion_fallida)
	controlador.aviso_emitido.connect(_on_aviso_servidor)
	controlador.partida_terminada.connect(_on_partida_terminada)
	tapete.partida_finalizada.connect(_on_partida_terminada)

	for arg in _args:
		if arg.begins_with("puerto="):
			_puerto = arg.trim_prefix("puerto=").to_int()
		if arg.begins_with("semilla="):
			controlador.semilla = arg.trim_prefix("semilla=").to_int()
		if arg.begins_with("captura="):
			_capturar_mas_tarde(arg.trim_prefix("captura="))
	tapete.autojugar = _args.has("autojugar")
	tapete.autocantar = not _args.has("no_cantar")
	if _args.has("pausa_corta"):
		controlador.pausa_baza = 0.2
	if _args.has("salir_al_terminar"):
		# Red de seguridad para las pruebas sin pantalla: nunca más de 4 minutos.
		get_tree().create_timer(240.0).timeout.connect(get_tree().quit)

	if _args.has("servidor"):
		_on_server_pressed()
	elif _args.has("cliente"):
		_botones.hide()
		_mostrar_estado("Arrancando como cliente…")
		# Le damos un segundo al servidor para que empiece a escuchar.
		await get_tree().create_timer(1.0).timeout
		_on_client_pressed()


## Juego_Tute para el Tute por parejas; Juego_Motor con su motor para el resto.
func _crear_controlador() -> Controlador_juego_Base:
	if modo["juego"] == "tute":
		return Juego_Tute.new()
	var motor := Juego_Motor.new()
	motor.juego = modo["juego"]
	return motor


func _construir_pantalla() -> void:
	_botones = Control.new()
	add_child(_botones)
	_botones.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fondo := TextureRect.new()
	fondo.texture = load("res://data/Misc/tapete.png")
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_botones.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var columna := VBoxContainer.new()
	columna.alignment = BoxContainer.ALIGNMENT_CENTER
	columna.add_theme_constant_override("separation", 24)
	_botones.add_child(columna)
	columna.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columna.add_child(_texto(Modos.titulo(modo).to_upper(), 40))
	var reparto := "Cada uno juega por su cuenta." if _jugadores == 2 \
		else "Parejas: jugadores 1 y 3 contra 2 y 4, por orden de conexión."
	columna.add_child(_texto("Abre %d ventanas: en una pulsa SER SERVIDOR (no juega) y en las otras %d, SER CLIENTE.\n%s" % [
		_jugadores + 1, _jugadores, reparto], 20))

	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 40)
	columna.add_child(fila)
	fila.add_child(_boton("SER CLIENTE", _on_client_pressed, Vector2(320, 110)))
	fila.add_child(_boton("SER SERVIDOR", _on_server_pressed, Vector2(320, 110)))
	var volver := _boton("Volver al menú", _volver_al_menu, Vector2(220, 44))
	volver.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	columna.add_child(volver)

	_estado = Label.new()
	_estado.visible = false
	_estado.position = Vector2(20, 20)
	_estado.size = Vector2(1100, 600)
	_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_estado)

	# Para salir de la mesa cuando acaba la partida.
	_boton_menu = _boton("Volver al menú", _volver_al_menu, Vector2(180, 40))
	_boton_menu.visible = false
	_boton_menu.z_index = 200
	add_child(_boton_menu)


func _texto(texto: String, tam: int) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ajustes := LabelSettings.new()
	ajustes.font_size = tam
	ajustes.outline_size = 8
	ajustes.outline_color = Color.BLACK
	etiqueta.label_settings = ajustes
	return etiqueta


func _boton(texto: String, al_pulsar: Callable, tam: Vector2) -> Button:
	var boton := Button.new()
	boton.text = texto
	boton.custom_minimum_size = tam
	boton.add_theme_font_size_override("font_size", 22)
	boton.pressed.connect(al_pulsar)
	return boton


func crear_servidor() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(_puerto, _jugadores)
	if error != OK:
		_mostrar_estado("No se pudo abrir el puerto %d (error %d). ¿Hay otro servidor de %s abierto?" % [
			_puerto, error, Modos.titulo(modo)])
		return
	multiplayer.multiplayer_peer = peer
	_mostrar_estado("Servidor de %s escuchando en el puerto %d.\nJugadores: 0/%d" % [
		Modos.titulo(modo), _puerto, _jugadores])


func unirse_como_cliente() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(DIRECCION, _puerto)
	if error != OK:
		_mostrar_estado("No se pudo crear el cliente (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	_mostrar_estado("Conectando con el servidor de %s…" % Modos.titulo(modo))


# Solo el servidor gestiona la creación de jugadores reales.
func _on_jugador_conectado(id: int) -> void:
	if not multiplayer.is_server():
		return
	if controlador.juego_en_curso or controlador.jugadores.size() >= _jugadores:
		return
	var numero: int = controlador.jugadores.size() + 1
	controlador.jugadores.append(Jugador.new(id, "Jugador %d" % numero))
	_mostrar_estado("Servidor de %s escuchando en el puerto %d.\nJugadores: %d/%d" % [
		Modos.titulo(modo), _puerto, numero, _jugadores])
	tapete.rpc("mostrar_aviso", "Esperando jugadores: %d/%d" % [numero, _jugadores])
	if numero == _jugadores:
		print("¡%d jugadores listos! Empieza %s." % [numero, Modos.titulo(modo)])
		controlador._iniciar_juego()


func _on_jugador_desconectado(id: int) -> void:
	print("El jugador ", id, " se ha ido.")
	if multiplayer.is_server() and controlador.juego_en_curso:
		_mostrar_estado("Un jugador se ha desconectado: la partida no puede seguir.")


func _on_conectado_al_servidor() -> void:
	_estado.hide()


func _on_conexion_fallida() -> void:
	if _reintentos >= MAX_REINTENTOS:
		_mostrar_estado("No se pudo conectar con el servidor en %s:%d." % [DIRECCION, _puerto])
		return
	_reintentos += 1
	_mostrar_estado("El servidor aún no responde. Reintento %d/%d…" % [_reintentos, MAX_REINTENTOS])
	await get_tree().create_timer(1.0).timeout
	unirse_como_cliente()


func _on_aviso_servidor(texto: String) -> void:
	if multiplayer.is_server():
		_estado.text += "\n" + texto


func _on_partida_terminada(_texto_fin: String) -> void:
	_boton_menu.position = Vector2(tapete.get_viewport_rect().size.x - 200.0, 12.0)
	_boton_menu.show()
	if _args.has("salir_al_terminar"):
		# Un segundo para que salgan los últimos mensajes de red.
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _mostrar_estado(texto: String) -> void:
	_estado.show()
	_estado.text = texto
	print(texto)


func _on_client_pressed() -> void:
	unirse_como_cliente()
	_botones.hide()
	tapete.visible = true


func _on_server_pressed() -> void:
	crear_servidor()
	_botones.hide()
	# El servidor no juega: en vez de la mesa enseña lo que va pasando.
	tapete.visible = false


func _volver_al_menu() -> void:
	multiplayer.multiplayer_peer = null
	Modos.elegido = {}
	get_tree().change_scene_to_file(ESCENA_MENU)


func _capturar_mas_tarde(ruta: String) -> void:
	await get_tree().create_timer(SEGUNDOS_HASTA_CAPTURA).timeout
	get_viewport().get_texture().get_image().save_png(ruta)
	print("Captura guardada en ", ruta)
