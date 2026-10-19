extends Node

@onready var controlador = $"juego_guiñote"

func _ready():
	# Conectamos las señales nativas de Godot para el multijugador
	multiplayer.peer_connected.connect(_on_jugador_conectado)
	multiplayer.peer_disconnected.connect(_on_jugador_desconectado)

# Llama a esta función si pulsas un botón de "Crear Partida" (Host)
func crear_servidor():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(8910) 
	multiplayer.multiplayer_peer = peer
	
	print("Servidor dedicado creado. Esperando jugadores...")
	
	# ¡BORRAMOS _on_jugador_conectado(1)! 
	# El servidor ya no es un jugador, solo escucha.

# Llama a esta función si pulsas un botón de "Unirse" (Cliente)
func unirse_como_cliente():
	var peer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 8910) # 127.0.0.1 es tu propia red local (localhost)
	multiplayer.multiplayer_peer = peer
	print("Intentando conectar al servidor...")

# Esta función salta automáticamente cuando alguien se conecta
func _on_jugador_conectado(id: int):
	# Solo el servidor gestiona la creación de jugadores reales
	if multiplayer.is_server():
		print("Nuevo jugador conectado con ID: ", id)
		
		# Creamos el objeto Jugador y lo metemos al controlador
		var nuevo_jugador = Jugador.new(id, "Jugador " + str(id))
		controlador.jugadores.append(nuevo_jugador)
		
		# Para esta prueba, si ya hay 2 jugadores, ¡empezamos!
		if controlador.jugadores.size() == 2:
			print("¡2 Jugadores listos! Iniciando partida...")
			controlador._iniciar_juego()

func _on_jugador_desconectado(id: int):
	print("El jugador ", id, " se ha ido.")
	# Aquí podrías borrarlo de la lista controlador.jugadores


func _on_client_pressed() -> void:
	unirse_como_cliente()
	$"botones holder".hide()
	$Tapete.visible = true

func _on_server_pressed() -> void:
	crear_servidor()
	$"botones holder".hide()
	$Tapete.visible = true
