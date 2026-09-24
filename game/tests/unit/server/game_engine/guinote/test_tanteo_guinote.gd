extends GutTest
## Tanteo, fin de partida y vuelta del Guiñote (analisis_funcional_app.md §8).

var motor: MotorGuinote


func before_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	motor = MotorGuinote.new(rng)


func _tanteo(cartas: Array, total: Array) -> Dictionary:
	return {"cartas": cartas, "total": total}


# --- Quién gana al acabar las idas ---

func test_si_solo_una_pareja_pasa_de_100_gana_esa() -> void:
	assert_eq(MotorGuinote.decidir_idas(_tanteo([80, 50], [101, 60]), 1), 0)
	assert_eq(MotorGuinote.decidir_idas(_tanteo([50, 80], [60, 120]), 0), 1)


func test_con_100_justos_no_se_gana() -> void:
	assert_eq(MotorGuinote.decidir_idas(_tanteo([70, 60], [100, 90]), 0), -1, "hay que superar los 100")


func test_si_las_dos_pasan_de_100_gana_la_de_la_ultima_baza() -> void:
	var tanteo := _tanteo([70, 60], [130, 110])
	assert_eq(MotorGuinote.decidir_idas(tanteo, 1), 1)
	assert_eq(MotorGuinote.decidir_idas(tanteo, 0), 0)


func test_la_pareja_de_la_ultima_baza_con_menos_de_30_de_cartas_pierde() -> void:
	# La pareja 1 hizo la última baza pero solo tiene 25 de cartas (el resto, cantes).
	assert_eq(MotorGuinote.decidir_idas(_tanteo([105, 25], [115, 105]), 1), 0)


func test_una_pareja_con_menos_de_30_de_cartas_no_gana_aunque_sea_la_unica_que_pasa() -> void:
	# 20 de cartas + 100 de cantes: supera los 100, pero sin el mínimo de cartas pierde.
	assert_eq(MotorGuinote.decidir_idas(_tanteo([20, 110], [120, 100]), 0), 1)


func test_si_nadie_pasa_de_100_hay_vuelta() -> void:
	assert_eq(MotorGuinote.decidir_idas(_tanteo([70, 60], [80, 60]), 0), -1)


# --- Paso a la vuelta y fin de la vuelta ---

## Estado justo antes de cerrar la última baza de las idas: el 3 juega y la
## gana el 0 con el As de copas.
func _antes_de_la_ultima_baza_de_las_idas(cartas_equipo_0: Array, cartas_equipo_1: Array) -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.palo_triunfo = Carta.Palo.OROS
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.manos = [[] as Array[Carta], [] as Array[Carta], [] as Array[Carta], _cartas(["copas_2"])]
	e.cartas_ganadas = [_cartas(cartas_equipo_0), _cartas(cartas_equipo_1)]
	e.bazas_jugadas = 9
	e.ultima_baza = {"ganador": 1, "cartas": [] as Array[Dictionary]}
	e.baza_actual = [
		{"jugador_id": 0, "carta": Carta.desde_id("copas_1")},
		{"jugador_id": 1, "carta": Carta.desde_id("copas_4")},
		{"jugador_id": 2, "carta": Carta.desde_id("copas_5")},
	] as Array[Dictionary]
	e.turno = 3
	return e


func _cartas(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


func _jugar(e: EstadoGuinote, jugador_id: int, jugada: Dictionary) -> EstadoGuinote:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, resultado.error)
	return resultado.estado


func test_al_acabar_las_idas_con_mas_de_100_termina_la_partida() -> void:
	# Equipo 0: 11+10+10+11+11+10+10 + 4+4+4 (85) + As de copas de la última baza (11)
	# + 10 de las diez últimas = 106. Equipo 1: el Rey de espadas, 4.
	var e := _antes_de_la_ultima_baza_de_las_idas(
		["oros_1", "oros_3", "espadas_3", "espadas_1", "bastos_1", "bastos_3", "copas_3",
			"oros_12", "bastos_12", "copas_12"],
		["espadas_12"])
	e = _jugar(e, 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})
	assert_true(motor.ha_terminado(e))
	var resultado := motor.calcular_resultado(e)
	assert_eq(resultado["equipo_ganador"], 0)
	assert_eq(resultado["motivo"], "tantos")
	assert_eq(resultado["puntos_por_equipo"], [106, 4])
	assert_eq(resultado["manos"][0]["diez_ultimas"], [10, 0])


func test_si_nadie_pasa_de_100_se_reparte_la_vuelta() -> void:
	var e := _antes_de_la_ultima_baza_de_las_idas(["oros_1", "oros_3"], ["espadas_1", "espadas_3"])
	e.cantes = [{"jugador_id": 1, "palo": Carta.Palo.BASTOS, "puntos": 20, "mano": EstadoGuinote.Mano.IDAS}] as Array[Dictionary]
	e = _jugar(e, 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})

	assert_false(motor.ha_terminado(e))
	assert_eq(e.mano_actual, EstadoGuinote.Mano.VUELTA)
	# Equipo 0: 21 + 11 (As de copas) + 10 últimas = 42. Equipo 1: 21 + 20 de cante = 41.
	assert_eq(e.tanteo_idas["total"], [42, 41])
	assert_eq(e.dador, 0, "reparte quien ganó la última baza de las idas")
	assert_eq(e.turno, 1, "sale el de su derecha")
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)
	assert_eq(e.mazo.size(), 15)
	assert_eq(e.bazas_jugadas, 0)
	assert_eq(e.fase, EstadoGuinote.Fase.ROBO)
	var vista := motor.vista_para_jugador(e, 2)
	assert_eq(vista["mano"], "vuelta")
	assert_eq(vista["tanteo_idas"], [42, 41])
	assert_eq(motor.calcular_resultado(e)["puntos_por_equipo"], [42, 41], "se arrastra el tanteo")


## Vuelta en curso con el tanteo de las idas dado; el 0 va a ganar la baza con
## el As de copas cuando juegue el 3.
func _vuelta_con_baza_a_punto_de_cerrarse(tanteo_idas: Array) -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.palo_triunfo = Carta.Palo.OROS
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.mano_actual = EstadoGuinote.Mano.VUELTA
	e.tanteo_idas = {"cartas": [0, 0], "cantes": [0, 0], "diez_ultimas": [0, 0], "total": tanteo_idas}
	e.manos = [_cartas(["bastos_10", "bastos_12"]), _cartas(["espadas_2"]), _cartas(["espadas_4"]),
		_cartas(["copas_2", "espadas_5"])]
	e.bazas_jugadas = 6
	e.ultima_baza = {"ganador": 1, "cartas": [] as Array[Dictionary]}
	e.baza_actual = [
		{"jugador_id": 0, "carta": Carta.desde_id("copas_1")},
		{"jugador_id": 1, "carta": Carta.desde_id("copas_4")},
		{"jugador_id": 2, "carta": Carta.desde_id("copas_5")},
	] as Array[Dictionary]
	e.turno = 3
	return e


func test_la_vuelta_termina_cuando_quien_gana_una_baza_pasa_de_100() -> void:
	var e := _vuelta_con_baza_a_punto_de_cerrarse([95, 90])
	e = _jugar(e, 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})  # +11 para el equipo 0
	assert_true(motor.ha_terminado(e))
	var resultado := motor.calcular_resultado(e)
	assert_eq(resultado["equipo_ganador"], 0)
	assert_eq(resultado["motivo"], "vuelta")
	assert_eq(resultado["puntos_por_equipo"], [106, 90])
	assert_eq(resultado["manos"].size(), 2, "desglose de idas y vuelta")


func test_la_vuelta_sigue_si_quien_gana_la_baza_no_pasa_de_100() -> void:
	var e := _jugar(_vuelta_con_baza_a_punto_de_cerrarse([80, 99]), 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})
	assert_false(motor.ha_terminado(e), "80 + 11 no pasa de 100")


func test_en_la_vuelta_un_cante_que_hace_pasar_de_100_termina_la_partida() -> void:
	var e := _jugar(_vuelta_con_baza_a_punto_de_cerrarse([70, 99]), 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})
	assert_false(motor.ha_terminado(e), "70 + 11 = 81")
	e = _jugar(e, 0, {"tipo": "cantar", "palo": "bastos"})  # +20 = 101
	assert_true(motor.ha_terminado(e))
	assert_eq(motor.calcular_resultado(e)["equipo_ganador"], 0)


func test_en_la_vuelta_se_puede_volver_a_cantar_un_palo_de_las_idas() -> void:
	var e := _vuelta_con_baza_a_punto_de_cerrarse([10, 20])
	e.cantes = [{"jugador_id": 0, "palo": Carta.Palo.BASTOS, "puntos": 20, "mano": EstadoGuinote.Mano.IDAS}] as Array[Dictionary]
	e = _jugar(e, 3, {"tipo": "jugar_carta", "carta_id": "copas_2"})
	assert_has(motor.jugadas_validas(e, 0), {"tipo": "cantar", "palo": "bastos"})
