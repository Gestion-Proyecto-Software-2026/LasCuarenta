extends Node
## Partida de cualquiera de los modos de [Modos] sobre el prototipo de red de
## Javier: una ventana hace de servidor dedicado (no juega) y las demás de jugadores.
## El motor de reglas y el número de jugadores salen del modo elegido en el menú.
##
## Argumentos opcionales de cada instancia, detrás de "--":
##   modo=ID              modo de Modos.LISTA (si no, el elegido en el menú)
##   servidor | cliente   arranca sin pulsar botones
##   autojugar            el cliente juega solo (para probar sin pantalla)
##   no_cantar            con autojugar, nunca canta ni cambia la pinta
##   pausa_corta          el servidor recoge cada baza en 0,2 s en vez de 2 s
##   salir_al_terminar    la instancia se cierra al acabar la partida (o si el
##                        servidor no puede abrir su puerto)
##   limite=SEGUNDOS      la instancia se cierra pase lo que pase a los N segundos
##                        (red de seguridad para las pruebas sin pantalla)
##   puerto=NNNN          usa otro puerto (por defecto, el del modo)
##   semilla=N            reparto reproducible (siempre la misma partida)
##   captura=RUTA.png     el cliente guarda una captura de la mesa a los pocos segundos
##   nombre=TEXTO         el nombre con el que se sienta este jugador
##   ventana=N            la ventana ocupa el hueco N (1-4) de una rejilla de 2x2 en
##                        la pantalla y se titula "Las Cuarenta - jugador N" (jugar.bat)

const DIRECCION := "127.0.0.1"
const MAX_REINTENTOS := 10
const ESCENA_TAPETE := preload("res://compartido/Escenas/tapete/Tapete.tscn")
const ESCENA_MENU := "res://escenas/menu.tscn"
const SEGUNDOS_HASTA_CAPTURA := 7.0
const LARGO_MAXIMO_NOMBRE := 14

var modo: Dictionary
## El Juego_Motor de la partida.
var controlador: Juego_Motor
var tapete: Control

var _botones: Control
var _estado: Label
var _boton_menu: Button
var _args := PackedStringArray()
var _reintentos := 0
var _puerto := 0
var _jugadores := 0
## En el servidor: ya se repartió (aunque luego se haya acabado o cancelado).
var _partida_empezada := false
## En el servidor: el nombre que ha elegido cada jugador (peer_id -> nombre), o
## "" si no ha elegido ninguno. La partida no empieza hasta tener el de todos.
var _nombres_elegidos := {}
var _campo_nombre: LineEdit
## La partida ha terminado o se ha cancelado: ya no hay nada que avisar.
var _terminada := false


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
	multiplayer.server_disconnected.connect(_on_servidor_perdido)
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
		if arg.begins_with("nombre="):
			_campo_nombre.text = limpiar_nombre(arg.trim_prefix("nombre="))
		if arg.begins_with("ventana="):
			_colocar_ventana(arg.trim_prefix("ventana=").to_int())
		if arg.begins_with("limite="):
			get_tree().create_timer(arg.trim_prefix("limite=").to_float()).timeout.connect(get_tree().quit)
	tapete.autojugar = _args.has("autojugar")
	tapete.autocantar = not _args.has("no_cantar")
	if _args.has("pausa_corta"):
		controlador.pausa_baza = 0.2

	if _args.has("servidor"):
		_on_server_pressed()
	elif _args.has("cliente"):
		_botones.hide()
		_mostrar_estado("Arrancando como cliente…")
		# Le damos un segundo al servidor para que empiece a escuchar.
		await get_tree().create_timer(1.0).timeout
		_on_client_pressed()


## Juego_Motor con el motor de reglas del modo (los 6 modos van igual).
func _crear_controlador() -> Controlador_juego_Base:
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

	_campo_nombre = LineEdit.new()
	_campo_nombre.placeholder_text = "Tu nombre (opcional)"
	# Algo de margen para espacios de más: el nombre se recorta al limpiarlo.
	_campo_nombre.max_length = LARGO_MAXIMO_NOMBRE + 6
	_campo_nombre.text = Modos.nombre_jugador
	_campo_nombre.custom_minimum_size = Vector2(320, 44)
	_campo_nombre.add_theme_font_size_override("font_size", 20)
	_campo_nombre.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_campo_nombre.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	columna.add_child(_campo_nombre)

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
		if _args.has("salir_al_terminar"):
			get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	# Los clientes solo hablan con el servidor, nunca entre ellos (como en el
	# servidor de partida del equipo): así un cliente no puede llamar a la mesa de otro.
	multiplayer.server_relay = false
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
	if _partida_empezada or controlador.jugadores.size() >= _jugadores:
		_rechazar_conexion(id)
		return
	controlador.jugadores.append(Jugador.new(id, "Jugador %d" % (controlador.jugadores.size() + 1)))
	_avisar_espera()
	_empezar_si_estan_todos()


## Lo primero que hace un cliente al conectar: decir con qué nombre se sienta.
@rpc("any_peer", "call_remote", "reliable")
func presentarse(nombre: String) -> void:
	if not multiplayer.is_server() or _partida_empezada:
		return
	var peer := multiplayer.get_remote_sender_id()
	var jugador: Jugador = controlador.obtener_jugador_por_id(peer)
	if jugador == null:
		return
	_nombres_elegidos[peer] = limpiar_nombre(nombre)
	_poner_nombres()
	_empezar_si_estan_todos()


## Nombre en una línea, sin espacios de más y como mucho de 14 letras.
## Si no queda nada, "" (y se usa "Jugador N").
static func limpiar_nombre(nombre: String) -> String:
	var partes := nombre.strip_edges().split(" ", false)
	return " ".join(partes).replace("\n", " ").left(LARGO_MAXIMO_NOMBRE)


## "Jugador N" por orden de llegada, salvo quien haya elegido su nombre.
func _poner_nombres() -> void:
	for i in controlador.jugadores.size():
		var jugador: Jugador = controlador.jugadores[i]
		var elegido: String = _nombres_elegidos.get(jugador.peer_id, "")
		jugador.nombre = elegido if elegido != "" else "Jugador %d" % (i + 1)


## Se reparte cuando la mesa está llena y todos han dicho su nombre.
func _empezar_si_estan_todos() -> void:
	if _partida_empezada or controlador.jugadores.size() < _jugadores:
		return
	for jugador: Jugador in controlador.jugadores:
		if not _nombres_elegidos.has(jugador.peer_id):
			return
	print("¡%d jugadores listos! Empieza %s." % [_jugadores, Modos.titulo(modo)])
	_partida_empezada = true
	controlador._iniciar_juego()


func _avisar_espera() -> void:
	var hay: int = controlador.jugadores.size()
	_mostrar_estado("Servidor de %s escuchando en el puerto %d.\nJugadores: %d/%d" % [
		Modos.titulo(modo), _puerto, hay, _jugadores])
	tapete.rpc("mostrar_aviso", "Esperando jugadores: %d/%d" % [hay, _jugadores])


## Quien llega con la partida ya empezada no puede sentarse: se le avisa y se le echa.
func _rechazar_conexion(id: int) -> void:
	tapete.rpc_id(id, "mostrar_aviso", "Esta partida ya ha empezado.")
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_jugador_desconectado(id: int) -> void:
	print("El jugador ", id, " se ha ido.")
	if not multiplayer.is_server():
		return
	var jugador: Jugador = controlador.obtener_jugador_por_id(id)
	if jugador == null:
		return
	if controlador.juego_en_curso:
		_cancelar_partida("%s se ha desconectado." % jugador.nombre)
	elif not _partida_empezada:
		# Aún se estaba esperando: se libera su sitio y el resto se renumera.
		controlador.jugadores.erase(jugador)
		_nombres_elegidos.erase(id)
		_poner_nombres()
		_avisar_espera()


## Si alguien se va a mitad de partida no se puede seguir: se avisa a los que
## quedan y se les deja volver al menú.
func _cancelar_partida(motivo: String) -> void:
	controlador.juego_en_curso = false
	controlador.acciones_bloqueadas = true
	var texto := "PARTIDA CANCELADA\n%s" % motivo
	tapete.rpc("mostrar_resultado", texto)
	print("FIN CANCELADA | %s" % motivo)
	_mostrar_estado(texto)
	_on_partida_terminada(texto)


## En un cliente: el servidor se ha cerrado o nos ha echado.
func _on_servidor_perdido() -> void:
	if _terminada:
		return
	if tapete.asientos.is_empty():
		tapete.mostrar_resultado("NO SE PUDO ENTRAR\nLa partida ya había empezado o el servidor se ha cerrado.")
	else:
		tapete.mostrar_resultado("SE HA PERDIDO LA CONEXIÓN\nEl servidor se ha cerrado.")


func _on_conectado_al_servidor() -> void:
	_estado.hide()
	presentarse.rpc_id(1, Modos.nombre_jugador)


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
	if _terminada:
		return
	_terminada = true
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
	# Se recuerda para la próxima partida (mientras no se cierre el juego).
	Modos.nombre_jugador = limpiar_nombre(_campo_nombre.text)
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


## Con ventana=N: esta ventana ocupa el hueco N de una rejilla de 2x2 sobre la
## pantalla (sin la barra de tareas), para ver a todos los jugadores a la vez.
## El título la distingue de las demás (jugar.bat lo usa para cerrarlas).
func _colocar_ventana(hueco: int) -> void:
	var ventana := get_window()
	ventana.title = "Las Cuarenta - jugador %d" % hueco
	if DisplayServer.get_name() == "headless" or hueco < 1 or hueco > 4:
		return
	# Un fotograma, para que la ventana ya tenga su marco (título y bordes).
	await get_tree().process_frame
	var pantalla := DisplayServer.screen_get_usable_rect(ventana.current_screen)
	var celda := pantalla.size / 2
	var origen := pantalla.position + Vector2i((hueco - 1) % 2, 1 if hueco > 2 else 0) * celda
	# position y size son los del contenido; el marco va aparte.
	var marco := ventana.get_size_with_decorations() - ventana.size
	var borde := ventana.position - ventana.get_position_with_decorations()
	ventana.mode = Window.MODE_WINDOWED
	ventana.size = celda - marco
	ventana.position = origen + borde


func _capturar_mas_tarde(ruta: String) -> void:
	await get_tree().create_timer(SEGUNDOS_HASTA_CAPTURA).timeout
	get_viewport().get_texture().get_image().save_png(ruta)
	print("Captura guardada en ", ruta)
