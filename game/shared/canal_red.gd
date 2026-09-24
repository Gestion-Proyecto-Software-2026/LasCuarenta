extends Node
## Canal de mensajes entre cliente y servidor de partida sobre ENet (autoload
## [code]CanalRed[/code]).
##
## Godot solo entrega un RPC si existe un nodo con la misma ruta en los dos
## extremos. Como cliente y servidor son el mismo proyecto, este autoload está
## en [code]/root/CanalRed[/code] en ambos, y todos los mensajes del protocolo
## (§6) pasan por un único RPC con formato [code]{ tipo, payload }[/code].
##
## En el cliente, ignorad cualquier mensaje cuyo [code]peer_id[/code] no sea 1
## (el servidor). main_server.gd desactiva [code]server_relay[/code] para que un
## cliente no pueda enviar RPCs a otro, pero el cliente no debe depender solo de eso.

signal mensaje_recibido(peer_id: int, mensaje: Dictionary)


func enviar(peer_id: int, mensaje: Dictionary) -> void:
	_entregar.rpc_id(peer_id, mensaje)


@rpc("any_peer", "call_remote", "reliable")
func _entregar(mensaje: Dictionary) -> void:
	mensaje_recibido.emit(multiplayer.get_remote_sender_id(), mensaje)
