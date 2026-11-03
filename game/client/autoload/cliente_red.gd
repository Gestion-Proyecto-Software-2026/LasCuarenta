extends Node
## Cliente de red de la partida (ENet) para la app de escritorio (autoload,
## igual que ClienteApi). Mantiene la conexión con el servidor de partida y
## cachea el último mensaje de cada tipo, para que una pantalla que se crea
## después de que llegue un mensaje (p. ej. estado_partida justo después de
## partida_iniciada) pueda leerlo sin haberlo "perdido" por no estar todavía
## escuchando. Protocolo completo en docs/mapa/protocolo.md.

signal conectado
signal fallo_conexion
signal desconectado_del_servidor
signal partida_iniciada(config: Dictionary)
signal estado_actualizado(estado: Dictionary)
signal partida_terminada(resultado: Dictionary)
signal error_recibido(mensaje: String)

## Datos de la sala a la que se quiere jugar, guardados por el lobby antes de
## cambiar a la pantalla de espera (ver lobby.gd).
var sala_id: String = ""
var servidor_direccion: String = ""

## Último `partida_iniciada.config` y `estado_partida` recibidos (se limpian al
## desconectar). `resultado` es el último `partida_terminada.resultado`.
var config: Dictionary = {}
var ultimo_estado: Dictionary = {}
var resultado: Dictionary = {}

var _peer: ENetMultiplayerPeer = null


## Escucha siempre CanalRed (no solo mientras hay una conexión ENet activa),
## para no tener que acordarse de conectar/desconectar el mismo callback en
## cada conectar_al_servidor()/desconectar().
func _ready() -> void:
	CanalRed.mensaje_recibido.connect(_on_mensaje)


## Guarda a qué sala y servidor hay que conectarse; no conecta todavía (lo hace
## la pantalla de espera en su _ready, para poder mostrar "conectando...").
func preparar(p_sala_id: String, p_servidor_direccion: String) -> void:
	sala_id = p_sala_id
	servidor_direccion = p_servidor_direccion


## Conecta por ENet a `servidor_direccion` ("host:puerto"). Emite `conectado` o
## `fallo_conexion`; no envía nada hasta que se llame a `unirse_partida`.
func conectar_al_servidor() -> void:
	var partes := servidor_direccion.split(":")
	if partes.size() != 2 or not partes[1].is_valid_int():
		fallo_conexion.emit()
		return

	config = {}
	ultimo_estado = {}
	resultado = {}
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(partes[0], partes[1].to_int()) != OK:
		_peer = null
		fallo_conexion.emit()
		return

	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_conectado, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_fallo_conexion, CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_desconectado, CONNECT_ONE_SHOT)


## Cierra la conexión y olvida el estado de la partida (no la sala preparada).
func desconectar() -> void:
	if multiplayer.connected_to_server.is_connected(_on_conectado):
		multiplayer.connected_to_server.disconnect(_on_conectado)
	if multiplayer.connection_failed.is_connected(_on_fallo_conexion):
		multiplayer.connection_failed.disconnect(_on_fallo_conexion)
	if multiplayer.server_disconnected.is_connected(_on_desconectado):
		multiplayer.server_disconnected.disconnect(_on_desconectado)
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	config = {}
	ultimo_estado = {}
	resultado = {}


func unirse_partida(usuario_id: String, token: String) -> void:
	enviar(MensajesRed.UNIRSE_PARTIDA, {"usuario_id": usuario_id, "token": token, "sala_id": sala_id})


## Envía una jugada al servidor; `payload` es el resto de campos del mensaje
## sin "tipo" (ver docs/mapa/protocolo.md), tal y como viene en `jugadas_validas`.
func enviar(tipo: String, payload: Dictionary = {}) -> void:
	CanalRed.enviar(1, MensajesRed.crear(tipo, payload))


func _on_conectado() -> void:
	conectado.emit()


func _on_fallo_conexion() -> void:
	fallo_conexion.emit()


func _on_desconectado() -> void:
	desconectado_del_servidor.emit()


func _on_mensaje(peer_id: int, mensaje: Dictionary) -> void:
	if peer_id != 1:
		return  # Solo el servidor; ver shared/canal_red.gd.
	var payload: Dictionary = mensaje.get("payload", {})
	match mensaje.get("tipo"):
		MensajesRed.PARTIDA_INICIADA:
			config = payload.get("config", {})
			partida_iniciada.emit(config)
		MensajesRed.ESTADO_PARTIDA:
			ultimo_estado = payload
			estado_actualizado.emit(ultimo_estado)
		MensajesRed.PARTIDA_TERMINADA:
			resultado = payload.get("resultado", {})
			partida_terminada.emit(resultado)
		MensajesRed.ERROR:
			error_recibido.emit(payload.get("mensaje", ""))
