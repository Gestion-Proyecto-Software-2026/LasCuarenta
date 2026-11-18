extends Node
## Canal de mensajes entre cliente y servidor de partida sobre ENet (autoload
## [code]CanalRed[/code]).
##
## Godot solo entrega un RPC si existe un nodo con la misma ruta en los dos
## extremos. Como cliente y servidor son el mismo proyecto, este autoload está
## en [code]/root/CanalRed[/code] en ambos, y todos los mensajes del protocolo
## (§6) tienen el formato [code]{ tipo, payload }[/code]. Por dentro hay dos RPC,
## uno por canal de ENet (las jugadas y el chat, ver [constant CANAL_CHAT]), que
## acaban en la misma señal: quien envía o recibe no tiene que saber cuál se usa.
##
## En el cliente, ignorad cualquier mensaje cuyo [code]peer_id[/code] no sea 1
## (el servidor). main_server.gd desactiva [code]server_relay[/code] para que un
## cliente no pueda enviar RPCs a otro, pero el cliente no debe depender solo de eso.

signal mensaje_recibido(peer_id: int, mensaje: Dictionary)

## Canal de ENet del chat (PBI-08). Los mensajes fiables de un mismo canal se
## entregan en orden, así que si el chat fuera por el de las jugadas (el 0), un
## mensaje largo podría retrasar un estado_partida. Por eso va aparte.
## ENetMultiplayerPeer se crea con el número de canales por defecto (el máximo),
## así que no hay que configurar nada más.
const CANAL_CHAT := 1


func enviar(peer_id: int, mensaje: Dictionary) -> void:
	if canal_de(mensaje) == CANAL_CHAT:
		_entregar_chat.rpc_id(peer_id, mensaje)
	else:
		_entregar.rpc_id(peer_id, mensaje)


## Canal de ENet por el que viaja [param mensaje]: [constant CANAL_CHAT] para
## los de [constant MensajesRed.TIPOS_CHAT] y 0 para todo lo demás.
static func canal_de(mensaje: Dictionary) -> int:
	return CANAL_CHAT if mensaje.get("tipo") in MensajesRed.TIPOS_CHAT else 0


@rpc("any_peer", "call_remote", "reliable")
func _entregar(mensaje: Dictionary) -> void:
	mensaje_recibido.emit(multiplayer.get_remote_sender_id(), mensaje)


@rpc("any_peer", "call_remote", "reliable", 1)
func _entregar_chat(mensaje: Dictionary) -> void:
	mensaje_recibido.emit(multiplayer.get_remote_sender_id(), mensaje)
