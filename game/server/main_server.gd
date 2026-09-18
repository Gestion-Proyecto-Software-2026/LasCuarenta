extends Node
## Punto de entrada del servidor de partida (headless).
## Arrancar con: godot --headless --path game

const PUERTO := 9000
const MAX_JUGADORES := 4

func _ready() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PUERTO, MAX_JUGADORES)
	if error != OK:
		push_error("No se pudo abrir el puerto %d (error %d)" % [PUERTO, error])
		return
	multiplayer.multiplayer_peer = peer
	print("Servidor de partida escuchando en el puerto %d (ENet)" % PUERTO)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	print("Jugador conectado: %d" % id)
	# TODO: delegar en RoomManager (unirse_partida, ver docs/analisis_funcional_app.md §6)

func _on_peer_disconnected(id: int) -> void:
	print("Jugador desconectado: %d" % id)
	# TODO: delegar en RoomManager
