class_name MotorTute
extends MotorDeJuego
## El Tute tal como lo pide el backend ("tute"), a 2 o a 4 jugadores. Las reglas
## cambian tanto de una mesa a otra que son dos motores: [MotorTuteDos] (con
## mazo, robo y capote) y [MotorTuteParejas] (sin mazo, arrastre desde la
## primera baza). Este motor elige el que toca según los jugadores de la
## partida y le pasa cada llamada.

var _dos: MotorTuteDos
var _parejas: MotorTuteParejas


func _init(p_rng: RandomNumberGenerator = null) -> void:
	super(p_rng)
	_dos = MotorTuteDos.new(rng)
	_parejas = MotorTuteParejas.new(rng)


func jugadores_admitidos() -> Array[int]:
	return [2, 4]


func _iniciar(num_jugadores: int) -> EstadoPartida:
	return _segun(num_jugadores)._iniciar(num_jugadores)


func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	return _del(estado).jugadas_validas(estado, jugador_id)


func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	_del(estado)._ejecutar_jugada(estado, jugador_id, jugada)


func ha_terminado(estado: EstadoPartida) -> bool:
	return _del(estado).ha_terminado(estado)


func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	return _del(estado).calcular_resultado(estado)


func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	return _del(estado).vista_para_jugador(estado, jugador_id)


func explicar_rechazo(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> String:
	return _del(estado).explicar_rechazo(estado, jugador_id, jugada)


func _segun(num_jugadores: int) -> MotorGuinote:
	return _dos if num_jugadores == 2 else _parejas


func _del(estado: EstadoPartida) -> MotorGuinote:
	return _segun(estado.num_jugadores)
