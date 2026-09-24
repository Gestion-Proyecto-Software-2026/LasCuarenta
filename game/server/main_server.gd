extends Node
## Punto de entrada del servidor de partida (headless).
##
## Arranque (las variables de entorno son obligatorias salvo BACKEND_URL):
##   JWT_SECRET=... INTERNAL_API_SECRET=... [BACKEND_URL=http://localhost:3000/api] \
##     godot --headless --path game res://server/main_server.tscn [-- --puerto=9001]
##
## Abre el ENetMultiplayerPeer y conecta la red (CanalRed) con RoomManager, que
## es quien gestiona salas y partidas (arquitectura.md §2).

const PUERTO_POR_DEFECTO := 9000
## NFR: al menos 5 partidas simultáneas de hasta 4 jugadores, con margen.
const MAX_CLIENTES := 32
const URL_BACKEND_POR_DEFECTO := "http://localhost:3000/api"
const ESPERA_ANTES_DE_EXPULSAR_S := 1.0

## Juegos disponibles: nombre (como lo devuelve el backend) -> script del motor.
## Cada PBI de juego añade aquí su línea, p. ej.
## "guinote": preload("res://server/game_engine/guinote/motor_guinote.gd").
const MOTORES := {}

var room_manager: RoomManager


func _ready() -> void:
	var jwt_secret := OS.get_environment("JWT_SECRET")
	var secreto_interno := OS.get_environment("INTERNAL_API_SECRET")
	var url_backend := OS.get_environment("BACKEND_URL")
	if url_backend.is_empty():
		url_backend = URL_BACKEND_POR_DEFECTO
	if jwt_secret.is_empty() or secreto_interno.is_empty():
		push_error("Faltan JWT_SECRET y/o INTERNAL_API_SECRET en el entorno: "
			+ "deben tener el mismo valor que en el backend (arquitectura.md §5)")
		get_tree().quit(1)
		return

	var puerto := leer_puerto(OS.get_cmdline_user_args())
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(puerto, MAX_CLIENTES)
	if err != OK:
		push_error("No se pudo abrir el servidor ENet en el puerto %d: %s" % [puerto, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	# Los clientes solo hablan con el servidor, nunca entre ellos.
	multiplayer.server_relay = false

	var backend := ClienteBackend.new(url_backend, secreto_interno)
	add_child(backend)
	room_manager = RoomManager.new(backend, jwt_secret, MOTORES)
	add_child(room_manager)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	CanalRed.mensaje_recibido.connect(room_manager.recibir)
	room_manager.mensaje_para.connect(CanalRed.enviar)
	room_manager.expulsar.connect(_expulsar)
	print("Servidor de partida escuchando en UDP %d (backend: %s, juegos: %s)"
		% [puerto, url_backend, MOTORES.keys()])


## Lee [code]--puerto=N[/code] de los argumentos de usuario (los que van tras [code]--[/code]).
static func leer_puerto(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with("--puerto="):
			var valor := arg.trim_prefix("--puerto=")
			if valor.is_valid_int() and valor.to_int() > 0 and valor.to_int() <= 65535:
				return valor.to_int()
			push_warning("Puerto no válido '%s'; se usa %d" % [valor, PUERTO_POR_DEFECTO])
	return PUERTO_POR_DEFECTO


func _on_peer_connected(peer_id: int) -> void:
	print("Cliente conectado: %d" % peer_id)
	room_manager.conectar(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Cliente desconectado: %d" % peer_id)
	room_manager.desconectar(peer_id)


## Cierra la conexión tras un margen para que el cliente procese antes el
## mensaje de error que explica el motivo: si se cierra en el acto, el cliente
## atiende la desconexión antes que ese último mensaje y nunca lo ve.
func _expulsar(peer_id: int) -> void:
	await get_tree().create_timer(ESPERA_ANTES_DE_EXPULSAR_S).timeout
	if peer_id in multiplayer.get_peers():
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
