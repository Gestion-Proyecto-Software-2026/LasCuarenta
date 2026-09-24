extends GutTest
## Prueba la lógica común de MotorDeJuego a través de un juego mínimo.

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")


func _motor(semilla := 7) -> MotorDeJuego:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return MotorFalso.new(rng)


func _primera_jugada_valida(motor: MotorDeJuego, estado: EstadoPartida, jugador_id: int) -> Dictionary:
	return motor.jugadas_validas(estado, jugador_id)[0]


func test_iniciar_rellena_num_jugadores() -> void:
	var estado := _motor().iniciar(4)
	assert_not_null(estado)
	assert_eq(estado.num_jugadores, 4)


func test_iniciar_con_num_jugadores_no_admitido_devuelve_null() -> void:
	assert_null(_motor().iniciar(3))
	assert_push_error("no admite 3 jugadores")


func test_jugada_valida_devuelve_estado_nuevo_sin_tocar_el_original() -> void:
	var motor := _motor()
	var estado := motor.iniciar(4)
	var antes := motor.vista_para_jugador(estado, 0)
	var resultado := motor.aplicar_jugada(estado, 0, _primera_jugada_valida(motor, estado, 0))
	assert_true(resultado.ok)
	assert_eq(resultado.error, "")
	assert_ne(resultado.estado, estado)
	assert_eq(motor.vista_para_jugador(estado, 0), antes, "el estado original no debe cambiar")
	assert_eq(motor.vista_para_jugador(resultado.estado, 0)["mi_mano"].size(), 1)


func test_jugada_fuera_de_turno_se_rechaza() -> void:
	var motor := _motor()
	var estado := motor.iniciar(4)
	var carta_del_jugador_1: String = motor.vista_para_jugador(estado, 1)["mi_mano"][0]
	var resultado := motor.aplicar_jugada(estado, 1, {"tipo": "jugar_carta", "carta_id": carta_del_jugador_1})
	assert_false(resultado.ok)
	assert_null(resultado.estado)
	assert_eq(resultado.error, MotorDeJuego.ERROR_SIN_JUGADAS)


func test_carta_que_no_esta_en_la_mano_se_rechaza() -> void:
	var motor := _motor()
	var estado := motor.iniciar(4)
	var ajena: String = motor.vista_para_jugador(estado, 2)["mi_mano"][0]
	var resultado := motor.aplicar_jugada(estado, 0, {"tipo": "jugar_carta", "carta_id": ajena})
	assert_false(resultado.ok)
	assert_eq(resultado.error, MotorDeJuego.ERROR_JUGADA_NO_VALIDA)


func test_jugada_con_campos_de_mas_o_de_menos_se_rechaza() -> void:
	var motor := _motor()
	var estado := motor.iniciar(4)
	var con_extra := _primera_jugada_valida(motor, estado, 0).duplicate()
	con_extra["trampa"] = true
	assert_false(motor.aplicar_jugada(estado, 0, con_extra).ok)
	assert_false(motor.aplicar_jugada(estado, 0, {"tipo": "jugar_carta"}).ok)
	assert_false(motor.aplicar_jugada(estado, 0, {}).ok)


func test_jugador_inexistente_se_rechaza() -> void:
	var motor := _motor()
	var estado := motor.iniciar(2)
	for jugador_id in [-1, 2, 5]:
		var resultado := motor.aplicar_jugada(estado, jugador_id, {"tipo": "jugar_carta", "carta_id": "oros_1"})
		assert_eq(resultado.error, MotorDeJuego.ERROR_JUGADOR_INEXISTENTE, str(jugador_id))


func test_partida_completa_y_despues_se_rechaza_todo() -> void:
	var motor := _motor()
	var estado := _jugar_partida_entera(motor, 4)
	assert_true(motor.ha_terminado(estado))
	var resultado := motor.aplicar_jugada(estado, 0, {"tipo": "jugar_carta", "carta_id": "oros_1"})
	assert_eq(resultado.error, MotorDeJuego.ERROR_PARTIDA_TERMINADA)
	var final := motor.calcular_resultado(estado)
	assert_has(final, "equipo_ganador")
	assert_eq(final["puntos_por_equipo"].size(), 2)


func test_misma_semilla_misma_partida() -> void:
	var a := _motor(99)
	var b := _motor(99)
	var resultado_a := a.calcular_resultado(_jugar_partida_entera(a, 4))
	var resultado_b := b.calcular_resultado(_jugar_partida_entera(b, 4))
	assert_eq(resultado_a, resultado_b)


func test_equipo_de_agrupa_por_posicion() -> void:
	assert_eq([0, 1, 2, 3].map(MotorDeJuego.equipo_de), [0, 1, 0, 1])


func _jugar_partida_entera(motor: MotorDeJuego, num_jugadores: int) -> EstadoPartida:
	var estado := motor.iniciar(num_jugadores)
	var limite := 100
	while not motor.ha_terminado(estado) and limite > 0:
		limite -= 1
		for jugador_id in num_jugadores:
			var validas := motor.jugadas_validas(estado, jugador_id)
			if not validas.is_empty():
				var resultado := motor.aplicar_jugada(estado, jugador_id, validas[0])
				assert_true(resultado.ok, resultado.error)
				estado = resultado.estado
				break
	return estado
