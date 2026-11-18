extends GutTest
## MotorDeJuego.resultado_anticipado (PBI-08): una partida cortada por un
## renuncio admitido en el chat termina con el marcador que llevaba cada equipo
## (HU-016, CA-060). Se comprueba con los motores de verdad, a 2 y a 4, a mitad
## de partida: calcular_resultado tiene que servir también antes del final.

const SEMILLA := 2026
const MAX_JUGADAS := 400


func _motor(script: GDScript) -> MotorDeJuego:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA
	return script.new(rng)


## Juega [param jugadas] jugadas (las que elegiría el servidor por tiempo) sin
## llegar a terminar la partida.
func _a_mitad(motor: MotorDeJuego, num_jugadores: int, jugadas: int) -> EstadoPartida:
	var estado := motor.iniciar(num_jugadores)
	var hechas := 0
	var vueltas := 0
	while hechas < jugadas and vueltas < MAX_JUGADAS:
		vueltas += 1
		for jugador in num_jugadores:
			var jugada := motor.jugada_por_tiempo(estado, jugador)
			if jugada.is_empty():
				continue
			var resultado := motor.aplicar_jugada(estado, jugador, jugada)
			if resultado.ok and not motor.ha_terminado(resultado.estado):
				estado = resultado.estado
				hechas += 1
			break
	return estado


func _comprobar(script: GDScript, num_jugadores: int, jugadas: int) -> void:
	var motor := _motor(script)
	var estado := _a_mitad(motor, num_jugadores, jugadas)
	var etiqueta := "%s a %d" % [script.resource_path.get_file(), num_jugadores]
	assert_false(motor.ha_terminado(estado), etiqueta + ": la partida sigue")
	for ganador in 2:
		var resultado := motor.resultado_anticipado(estado, ganador)
		assert_eq(resultado["equipo_ganador"], ganador, etiqueta)
		var puntos: Array = resultado["puntos_por_equipo"]
		assert_eq(puntos.size(), 2, etiqueta)
		for valor: Variant in puntos:
			assert_true(valor is int and valor >= 0, "%s: %s es un entero >= 0" % [etiqueta, valor])
		assert_eq(puntos, motor.calcular_resultado(estado)["puntos_por_equipo"],
			etiqueta + ": el marcador es el que lleva la partida")


func test_guinote() -> void:
	_comprobar(load("res://server/game_engine/guinote/motor_guinote.gd"), 2, 9)
	_comprobar(load("res://server/game_engine/guinote/motor_guinote.gd"), 4, 13)


func test_tute() -> void:
	_comprobar(load("res://server/game_engine/tute/motor_tute.gd"), 2, 9)
	_comprobar(load("res://server/game_engine/tute/motor_tute.gd"), 4, 13)


func test_mus() -> void:
	_comprobar(load("res://server/game_engine/mus/motor_mus.gd"), 2, 12)
	_comprobar(load("res://server/game_engine/mus/motor_mus.gd"), 4, 20)


func test_recien_empezada_el_marcador_esta_a_cero() -> void:
	for script: GDScript in [
		load("res://server/game_engine/guinote/motor_guinote.gd"),
		load("res://server/game_engine/tute/motor_tute.gd"),
		load("res://server/game_engine/mus/motor_mus.gd"),
	]:
		var motor := _motor(script)
		var resultado := motor.resultado_anticipado(motor.iniciar(4), 1)
		assert_eq(resultado["puntos_por_equipo"], [0, 0], script.resource_path.get_file())
		assert_eq(resultado["equipo_ganador"], 1)
