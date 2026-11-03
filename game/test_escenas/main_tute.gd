extends Node
## Escena de prueba del Tute por parejas sobre el prototipo de red de Javier:
## una instancia hace de servidor dedicado (no juega) y cuatro de clientes.
##
## Argumentos opcionales de cada instancia, detrás de "--":
##   servidor | cliente   arranca sin pulsar botones
##   autojugar            el cliente juega solo (para probar sin pantalla)
##   pausa_corta          el servidor recoge cada baza en 0,2 s en vez de 2 s
##   salir_al_terminar    la instancia se cierra al acabar la partida
##   puerto=NNNN          usa otro puerto (por defecto 8910)
##   semilla=N            reparto reproducible (siempre la misma partida)
##   no_cantar            con autojugar, el cliente nunca pulsa el botón de cantar

const PUERTO := 8910
const DIRECCION := "127.0.0.1"
const MAX_REINTENTOS := 10

@onready var controlador: Juego_Tute = $juego_tute
@onready var tapete: Control = $Tapete
@onready var botones: Control = $"botones holder"
@onready var estado: Label = $Estado

var _args := PackedStringArray()
var _reintentos := 0
var _puerto := PUERTO


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_jugador_conectado)
	multiplayer.peer_disconnected.connect(_on_jugador_desconectado)
	multiplayer.connected_to_server.connect(_on_conectado_al_servidor)
	multiplayer.connection_failed.connect(_on_conexion_fallida)
	controlador.aviso_emitido.connect(_on_aviso_servidor)
	controlador.partida_terminada.connect(_on_partida_terminada)
	tapete.partida_finalizada.connect(_on_partida_terminada)

	_args = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for arg in _args:
		if arg.begins_with("puerto="):
			_puerto = arg.trim_prefix("puerto=").to_int()
		if arg.begins_with("semilla="):
			controlador.semilla = arg.trim_prefix("semilla=").to_int()
	tapete.autojugar = _args.has("autojugar")
	tapete.autocantar = not _args.has("no_cantar")
	if _args.has("pausa_corta"):
		controlador.pausa_baza = 0.2
	if _args.has("salir_al_terminar"):
		# Red de seguridad para las pruebas sin pantalla: nunca más de 3 minutos.
		get_tree().create_timer(180.0).timeout.connect(get_tree().quit)

	if _args.has("servidor"):
		_on_server_pressed()
	elif _args.has("cliente"):
		botones.hide()
		_estado("Arrancando como cliente…")
		# Le damos un segundo al servidor para que empiece a escuchar.
		await get_tree().create_timer(1.0).timeout
		_on_client_pressed()


func crear_servidor() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(_puerto, ReglasTute.JUGADORES)
	if error != OK:
		_estado("No se pudo abrir el puerto %d (error %d). ¿Hay otro servidor abierto?" % [_puerto, error])
		return
	multiplayer.multiplayer_peer = peer
	_estado("Servidor del Tute escuchando en el puerto %d.\nJugadores: 0/%d" % [_puerto, ReglasTute.JUGADORES])


func unirse_como_cliente() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(DIRECCION, _puerto)
	if error != OK:
		_estado("No se pudo crear el cliente (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	_estado("Conectando con el servidor…")


# Solo el servidor gestiona la creación de jugadores reales.
func _on_jugador_conectado(id: int) -> void:
	if not multiplayer.is_server():
		return
	if controlador.juego_en_curso or controlador.jugadores.size() >= ReglasTute.JUGADORES:
		return
	var numero := controlador.jugadores.size() + 1
	controlador.jugadores.append(Jugador.new(id, "Jugador %d" % numero))
	_estado("Servidor del Tute escuchando en el puerto %d.\nJugadores: %d/%d" % [
		_puerto, numero, ReglasTute.JUGADORES])
	tapete.rpc("mostrar_aviso", "Esperando jugadores: %d/%d" % [numero, ReglasTute.JUGADORES])
	if numero == ReglasTute.JUGADORES:
		print("¡%d jugadores listos! Iniciando partida de Tute..." % numero)
		controlador._iniciar_juego()


func _on_jugador_desconectado(id: int) -> void:
	print("El jugador ", id, " se ha ido.")
	if multiplayer.is_server() and controlador.juego_en_curso:
		_estado("Un jugador se ha desconectado: la partida no puede seguir.")


func _on_conectado_al_servidor() -> void:
	estado.hide()


func _on_conexion_fallida() -> void:
	if _reintentos >= MAX_REINTENTOS:
		_estado("No se pudo conectar con el servidor en %s:%d." % [DIRECCION, _puerto])
		return
	_reintentos += 1
	_estado("El servidor aún no responde. Reintento %d/%d…" % [_reintentos, MAX_REINTENTOS])
	await get_tree().create_timer(1.0).timeout
	unirse_como_cliente()


func _on_aviso_servidor(texto: String) -> void:
	if multiplayer.is_server():
		estado.text += "\n" + texto


func _on_partida_terminada(_texto: String) -> void:
	if _args.has("salir_al_terminar"):
		# Un segundo para que salgan los últimos mensajes de red.
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _estado(texto: String) -> void:
	estado.show()
	estado.text = texto
	print(texto)


func _on_client_pressed() -> void:
	unirse_como_cliente()
	botones.hide()
	tapete.visible = true


func _on_server_pressed() -> void:
	crear_servidor()
	botones.hide()
	# El servidor no juega: en vez de la mesa enseña lo que va pasando.
	tapete.visible = false
