extends Node
## Punto de entrada del servidor de partida (headless).
##
## Arranque:
##   godot --headless --path game res://server/main_server.tscn
##   godot --headless --path game res://server/main_server.tscn -- --puerto=9001
##
## Abre el ENetMultiplayerPeer y registra conexiones. RoomManager y los motores
## de juego se enchufan aquí cuando existan (arquitectura.md §2).

const PUERTO_POR_DEFECTO := 9000
## NFR: al menos 5 partidas simultáneas de hasta 4 jugadores, con margen.
const MAX_CLIENTES := 32


func _ready() -> void:
	var puerto := leer_puerto(OS.get_cmdline_user_args())
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(puerto, MAX_CLIENTES)
	if err != OK:
		push_error("No se pudo abrir el servidor ENet en el puerto %d: %s" % [puerto, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Servidor de partida escuchando en UDP %d" % puerto)


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


func _on_peer_disconnected(peer_id: int) -> void:
	print("Cliente desconectado: %d" % peer_id)
