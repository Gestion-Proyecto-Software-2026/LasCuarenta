extends Node
## Escena principal del cliente: solo redirige al primer paso del flujo
## (login, o directamente al lobby si ya hay sesión). Así F5 arranca el juego
## de verdad, sin tener que abrir login.tscn a mano con F6.


func _ready() -> void:
	var destino := "res://client/ui/lobby/lobby.tscn" if ClienteApi.esta_autenticado() \
		else "res://client/ui/login/login.tscn"
	get_tree().change_scene_to_file.call_deferred(destino)
