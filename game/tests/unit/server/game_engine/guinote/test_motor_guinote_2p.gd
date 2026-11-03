extends GutTest
## Guiñote a 2 jugadores: sin pareja, cada jugador es su propio equipo
## (analisis_funcional_app.md §8, variante a 2 jugadores confirmada con el
## equipo: mismo mecanismo de reparto/robo que a 4, con vuelta y Tute iguales).

const CAMBIAR := {"tipo": "cambiar_siete"}
const NO_CAMBIAR := {"tipo": "no_cambiar_siete"}

var motor: MotorGuinote


func before_each() -> void:
	motor = MotorGuinote.new()


func _cartas(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


func _aplicar(e: EstadoGuinote, jugador_id: int, jugada: Dictionary) -> EstadoGuinote:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, resultado.error)
	return resultado.estado


func test_cada_jugador_es_su_propio_equipo() -> void:
	assert_eq(MotorDeJuego.equipo_de(0), 0)
	assert_eq(MotorDeJuego.equipo_de(1), 1)


func test_numero_de_bazas_con_robo_y_por_partida_a_2() -> void:
	assert_eq(EstadoGuinote.bazas_con_robo(2), 14)
	assert_eq(EstadoGuinote.bazas_por_partida(2), 20)
	# A 4 siguen dando lo mismo que antes del cambio (no regresión).
	assert_eq(EstadoGuinote.bazas_con_robo(4), 4)
	assert_eq(EstadoGuinote.bazas_por_partida(4), 10)


func test_reparto_a_2_jugadores() -> void:
	var e := motor.iniciar(2) as EstadoGuinote
	assert_eq(e.manos.size(), 2)
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)
	assert_not_null(e.pinta)
	assert_eq(e.mazo.size(), 40 - 2 * 6 - 1, "resto del mazo tras repartir y sacar la pinta")
	assert_true(e.dador == 0 or e.dador == 1)
	assert_eq(e.turno, (e.dador + 1) % 2)


## Estado en fase de robo, tras una baza que ganó [param ganador] (0 o 1).
func _estado_en_robo(manos: Array, ganador: int, bazas_jugadas: int) -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 2
	e.palo_triunfo = Carta.Palo.OROS
	e.pinta = Carta.desde_id("oros_1")
	e.mazo = _cartas(["bastos_2", "bastos_4"])
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
	e.bazas_jugadas = bazas_jugadas
	e.ultima_baza = {"ganador": ganador, "cartas": [] as Array[Dictionary]}
	e.turno = ganador
	return e


func test_quien_gana_la_baza_con_el_siete_puede_cambiarlo_sin_companero() -> void:
	# Jugador 0 tiene el siete de triunfo y acaba de ganar la baza.
	var e := _estado_en_robo([
		["oros_7", "espadas_5", "espadas_6", "bastos_1", "bastos_3", "copas_1"],
		["copas_6", "espadas_7", "bastos_10", "bastos_11", "bastos_12", "copas_5"],
	], 0, 5)
	assert_has(motor.jugadas_validas(e, 0), CAMBIAR)
	# No hay "compañero" fuera de {0,1} que comprobar: el jugador 1 (rival) no debe
	# recibir nunca la oportunidad aunque antes (a 4) se iterase sobre 2 posiciones más.
	assert_does_not_have(motor.jugadas_validas(e, 1), CAMBIAR)


func test_si_el_siete_lo_tiene_quien_pierde_no_se_ofrece_el_cambio() -> void:
	# El siete está en la mano del jugador 1, que no ganó la baza.
	var e := _estado_en_robo([
		["espadas_5", "espadas_6", "bastos_1", "bastos_3", "copas_1", "copas_2"],
		["oros_7", "espadas_7", "bastos_10", "bastos_11", "bastos_12", "copas_5"],
	], 0, 5)
	assert_does_not_have(motor.jugadas_validas(e, 0), CAMBIAR)
	assert_does_not_have(motor.jugadas_validas(e, 1), CAMBIAR)


## Cierra la decimocuarta baza (la última con robo a 2 jugadores) jugando el
## jugador 1 (turno) su carta sobre lo ya jugado por el jugador 0.
func _antes_de_cerrar_la_ultima_con_robo(quien_tiene_el_siete: int) -> EstadoGuinote:
	var manos := [
		["espadas_5", "espadas_6", "bastos_1", "bastos_3", "espadas_1"],
		["copas_6", "espadas_7", "bastos_10", "bastos_11", "bastos_12", "espadas_2"],
	]
	if quien_tiene_el_siete == 0:
		manos[0][0] = "oros_7"
	else:
		manos[1][1] = "oros_7"
	var e := EstadoGuinote.new()
	e.num_jugadores = 2
	e.palo_triunfo = Carta.Palo.OROS
	e.pinta = Carta.desde_id("oros_1")
	e.mazo = _cartas(["bastos_2"])
	e.manos = [_cartas(manos[0]), _cartas(manos[1])]
	e.bazas_jugadas = 13
	e.ultima_baza = {"ganador": 1, "cartas": [] as Array[Dictionary]}
	e.baza_actual = [{"jugador_id": 0, "carta": Carta.desde_id("copas_1")}] as Array[Dictionary]
	e.turno = 1
	return _aplicar(e, 1, {"tipo": "jugar_carta", "carta_id": "copas_6"})


func test_tras_la_ultima_baza_con_robo_si_el_ganador_tiene_el_siete_espera_su_decision() -> void:
	var e := _antes_de_cerrar_la_ultima_con_robo(0)
	assert_eq(e.ultima_baza["ganador"], 0, "copas_1 (As) gana a copas_6")
	assert_eq(e.siete_pendiente, 0)
	assert_eq(motor.jugadas_validas(e, 0), [CAMBIAR, NO_CAMBIAR] as Array[Dictionary])


func test_tras_la_ultima_baza_con_robo_termina_el_robo_y_empieza_el_arrastre() -> void:
	# El siete lo tiene quien pierde: no hay que esperar ninguna decisión, el
	# robo termina directamente al cerrar la baza.
	var e := _antes_de_cerrar_la_ultima_con_robo(1)
	assert_eq(e.siete_pendiente, -1)
	assert_eq(e.fase, EstadoGuinote.Fase.ARRASTRE)
	assert_true(e.mazo.is_empty())
	assert_null(e.pinta)
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)


func test_vista_para_jugador_cuenta_bien_las_bazas_por_equipo_a_2() -> void:
	# El jugador 0 ya ha ganado una baza (2 cartas ganadas, una por jugador).
	var e := _estado_en_robo([
		["espadas_5", "espadas_6", "bastos_1", "bastos_3", "copas_1", "copas_2"],
		["espadas_7", "bastos_10", "bastos_11", "bastos_12", "copas_5", "copas_6"],
	], 0, 1)
	e.cartas_ganadas = [_cartas(["oros_2", "oros_3"]), []]
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq(vista["bazas_por_equipo"], [1, 0])


func test_tute_de_reyes_a_2_jugadores() -> void:
	var e := EstadoGuinote.new()
	e.num_jugadores = 2
	e.palo_triunfo = Carta.Palo.OROS
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.manos = [
		_cartas(["oros_12", "copas_12", "espadas_12", "bastos_12", "oros_2", "oros_3"]),
		_cartas(["copas_1", "copas_2", "copas_3", "copas_4", "copas_5", "copas_6"]),
	]
	e.bazas_jugadas = 15
	e.ultima_baza = {"ganador": 0, "cartas": [] as Array[Dictionary]}
	e.turno = 0
	assert_has(motor.jugadas_validas(e, 0), {"tipo": "cantar_tute", "figura": "reyes"})
	var resultado := _aplicar(e, 0, {"tipo": "cantar_tute", "figura": "reyes"})
	assert_eq(resultado.equipo_ganador, 0)
	assert_eq(resultado.motivo_fin, "tute")
