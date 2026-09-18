class_name MotorDeJuego
extends RefCounted
## Contrato que debe implementar cada módulo de juego
## (guinote/, mus/, tute/). Ver docs/analisis_funcional_app.md §7.
##
## Añadir un juego nuevo no debería requerir tocar room_manager.gd:
## solo implementar esta interfaz en una carpeta nueva.

func iniciar(jugadores: Array) -> Dictionary:
	push_error("iniciar() no implementado")
	return {}

func jugadas_validas(estado: Dictionary, jugador_id: int) -> Array:
	push_error("jugadas_validas() no implementado")
	return []

func aplicar_jugada(estado: Dictionary, jugador_id: int, jugada: Dictionary) -> Dictionary:
	push_error("aplicar_jugada() no implementado")
	return estado

func ha_terminado(estado: Dictionary) -> bool:
	return false

func calcular_resultado(estado: Dictionary) -> Dictionary:
	return {}

func vista_para_jugador(estado: Dictionary, jugador_id: int) -> Dictionary:
	# Debe ocultar las cartas en mano de los demás jugadores antes
	# de que esto se envíe al cliente.
	return estado
