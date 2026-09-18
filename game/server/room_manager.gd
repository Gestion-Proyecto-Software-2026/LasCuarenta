extends Node
## Gestiona las salas activas y delega en el MotorDeJuego correspondiente
## (ver docs/analisis_funcional_app.md §7). No conoce las reglas de
## ningún juego concreto — solo sabe hablar contra esa interfaz.

var salas_activas: Dictionary = {}  # sala_id (String) -> MotorDeJuego

func crear_sala(sala_id: String, juego: String, jugadores: Array) -> void:
	# TODO: instanciar el módulo correspondiente
	# (game_engine/guinote, /mus o /tute) y guardarlo en salas_activas
	pass
