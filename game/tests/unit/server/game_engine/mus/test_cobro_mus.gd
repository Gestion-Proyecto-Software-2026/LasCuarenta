extends GutTest
## Cobro de cada mano, amarracos y fin del juego y de la partida de Mus
## (analisis_funcional_app.md §9). Los estados se construyen a mano, con el mus
## ya cortado y el 0 de mano.

const L := EstadoMus.Lance

# Mesa de ejemplo (parejas 0-2 contra 1-3):
# - Grande la gana el 0 (R R C 4) y Chica el 1 (A A 4 5).
# - Pares: el 0 (reyes), el 1 (ases) y el 3 (caballos); gana el 0.
# - Juego: el 0 (34), el 2 (33) y el 3 (37); gana el 3.
const MESA := [
	["oros_12", "copas_12", "espadas_11", "bastos_4"],
	["oros_1", "copas_2", "espadas_4", "bastos_5"],
	["oros_3", "copas_7", "espadas_6", "bastos_10"],
	["oros_11", "copas_11", "espadas_10", "bastos_7"],
]

const PASAR := {"tipo": "pasar"}
const QUIERO := {"tipo": "quiero"}
const NO_QUIERO := {"tipo": "no_quiero"}
const ORDAGO := {"tipo": "ordago"}
const ENVIDO := {"tipo": "envidar", "cantidad": 2}

var motor: MotorMus


func before_each() -> void:
	motor = _motor()


func _motor(piedras := MotorMus.PIEDRAS_POR_JUEGO, juegos := MotorMus.JUEGOS_PARA_GANAR) -> MotorMus:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return MotorMus.new(rng, piedras, juegos)


func _cartas(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


func _estado(manos: Array = MESA, piedras: Array[int] = [0, 0]) -> EstadoMus:
	var e := EstadoMus.new()
	e.num_jugadores = manos.size()
	e.piedras = piedras
	var en_mesa := {}
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
		e.cartas_pedidas.append(-1)
		e.descarte_ronda.append([] as Array[Carta])
		for id: String in ids:
			en_mesa[id] = true
	for carta in Baraja.crear():
		if not en_mesa.has(carta.id):
			e.mazo.append(carta)
	motor._empezar_lances(e)
	return e


func _aplicar(e: EstadoMus, jugador_id: int, jugada: Dictionary) -> EstadoMus:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, "%s del %d: %s" % [jugada, jugador_id, resultado.error])
	return resultado.estado if resultado.ok else e


## Pasan todos en lo que queda de mano.
func _pasan_todos(e: EstadoMus) -> EstadoMus:
	var mano := e.jugador_mano
	while e.fase == EstadoMus.Fase.LANCES and e.jugador_mano == mano and not motor.ha_terminado(e):
		e = _aplicar(e, e.turno, PASAR)
	return e


## Los cobros de la última mano como [lance, equipo, piedras, concepto].
func _cobros(e: EstadoMus) -> Array:
	return e.ultima_mano["cobros"].map(func(c: Dictionary) -> Array:
		return [c["lance"], c["equipo"], c["piedras"], c["concepto"]])


# --- Cobro al final de la mano ---

func test_todo_en_paso() -> void:
	var e := _pasan_todos(_estado())
	assert_eq(_cobros(e), [
		[L.GRANDE, 0, 1, "paso"],
		[L.CHICA, 1, 1, "paso"],
		[L.PARES, 0, 1, "jugada"],  # par de reyes del 0; el 2 no tiene
		[L.JUEGO, 1, 2, "jugada"],  # juego de 37 del 3; el 1 no tiene
	])
	assert_eq(e.piedras, [2, 3] as Array[int])
	assert_eq(e.jugador_mano, 1, "y se reparte otra mano")
	assert_eq(e.ultima_mano["juego_para"], -1)


func test_grande_querida_cobra_lo_envidado_en_vez_de_la_piedra_en_paso() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, ENVIDO), 1, QUIERO)
	e = _pasan_todos(e)
	assert_eq(_cobros(e)[0], [L.GRANDE, 0, 2, "envite"])
	assert_eq(e.piedras, [3, 3] as Array[int])


func test_chica_querida_la_cobra_la_mejor_aunque_envidase_el_otro() -> void:
	var e := _aplicar(_estado(), 0, PASAR)  # Grande en paso
	for j in [1, 2, 3]:
		e = _aplicar(e, j, PASAR)
	e = _aplicar(_aplicar(e, 0, {"tipo": "envidar", "cantidad": 4}), 1, QUIERO)
	e = _pasan_todos(e)
	assert_eq(_cobros(e)[1], [L.CHICA, 1, 4, "envite"], "la mejor chica es del 1")


func test_no_querido_solo_cobra_el_deje() -> void:
	var e := _aplicar(_estado(), 0, ENVIDO)
	e = _aplicar(_aplicar(e, 1, NO_QUIERO), 3, NO_QUIERO)
	e = _pasan_todos(e)
	assert_eq(_cobros(e)[0], [L.GRANDE, 0, 1, "deje"])
	assert_eq(_cobros(e)[1][0], L.CHICA, "la Grande no da nada más al final")


func test_pares_queridos_cobran_lo_envidado_y_lo_que_valen() -> void:
	var e := _estado([
		["oros_12", "copas_12", "espadas_12", "bastos_4"],  # medias de reyes
		["oros_1", "copas_2", "espadas_4", "bastos_5"],  # par de ases
		["oros_7", "copas_7", "espadas_6", "bastos_6"],  # duples
		["oros_11", "copas_11", "espadas_10", "bastos_7"],  # par de caballos
	])
	for lance in 2:
		for i in 4:
			e = _aplicar(e, e.turno, PASAR)
	assert_eq(e.lance, L.PARES)
	e = _aplicar(_aplicar(e, 0, {"tipo": "envidar", "cantidad": 3}), 1, QUIERO)
	e = _pasan_todos(e)
	# Gana el 2 (duples) para la pareja 0-2: lo envidado más sus duples (3) y las medias del 0 (2).
	assert_eq(_cobros(e).filter(func(c: Array) -> bool: return c[0] == L.PARES), [
		[L.PARES, 0, 3, "envite"],
		[L.PARES, 0, 5, "jugada"],
	])


func test_pares_no_queridos_los_cobra_quien_envido_aunque_sean_peores() -> void:
	var e := _estado()
	for lance in 2:
		for i in 4:
			e = _aplicar(e, e.turno, PASAR)
	e = _aplicar(e, 0, PASAR)
	e = _aplicar(e, 1, ENVIDO)
	assert_eq(e.envite["responden"], [0] as Array[int], "el 2 no tiene pares")
	e = _aplicar(e, 0, NO_QUIERO)
	assert_eq(e.piedras, [0, 1] as Array[int], "el deje, en el acto")
	e = _pasan_todos(e)
	# Los reyes del 0 son mejores, pero al no querer pierde el derecho: la pareja
	# 1-3 cobra su par de ases y su par de caballos.
	assert_eq(_cobros(e).filter(func(c: Array) -> bool: return c[0] == L.PARES), [
		[L.PARES, 1, 1, "deje"],
		[L.PARES, 1, 2, "jugada"],
	])


func test_juego_de_31_vale_3() -> void:
	var e := _estado([
		["oros_12", "copas_11", "espadas_10", "bastos_1"],  # 31
		["oros_1", "copas_2", "espadas_4", "bastos_5"],
		["oros_3", "copas_7", "espadas_6", "bastos_10"],  # 33
		["oros_11", "copas_11", "espadas_10", "bastos_7"],  # 37
	])
	e = _pasan_todos(e)
	assert_eq(_cobros(e).filter(func(c: Array) -> bool: return c[0] == L.JUEGO), [[L.JUEGO, 0, 5, "jugada"]],
		"la de 31 (3) más la del compañero (2)")


func test_al_punto_se_cobra_1_y_lo_envidado() -> void:
	var e := _estado([
		["oros_12", "copas_12", "espadas_5", "bastos_4"],  # 29
		["oros_1", "copas_2", "espadas_4", "bastos_5"],  # 11
		["oros_3", "copas_7", "espadas_6", "bastos_1"],  # 24
		["oros_11", "copas_4", "espadas_5", "bastos_7"],  # 26
	])
	for lance in 3:
		for i in e.hablan.size():
			e = _aplicar(e, e.turno, PASAR)
	assert_eq(e.lance, L.PUNTO)
	e = _aplicar(_aplicar(e, 0, ENVIDO), 1, QUIERO)
	assert_eq(_cobros(e).filter(func(c: Array) -> bool: return c[0] == L.PUNTO), [
		[L.PUNTO, 0, 2, "envite"],
		[L.PUNTO, 0, 1, "jugada"],
	])


func test_empate_lo_gana_el_mas_cercano_a_la_mano() -> void:
	# El 0 y el 1 tienen la misma Grande (R R 7 4 contra 3 3 7 4); es mano el 1.
	var manos := [
		["oros_12", "copas_12", "espadas_7", "bastos_4"],
		["oros_3", "copas_3", "copas_7", "copas_4"],
		["oros_1", "copas_1", "espadas_2", "bastos_2"],
		["oros_5", "copas_5", "espadas_6", "bastos_6"],
	]
	var e := EstadoMus.new()
	e.num_jugadores = 4
	e.jugador_mano = 1
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
	assert_eq(MotorMus.mejor_jugador(e, L.GRANDE), 1)
	e.jugador_mano = 0
	assert_eq(MotorMus.mejor_jugador(e, L.GRANDE), 0)


# --- Fin del juego ---

func test_el_juego_se_gana_en_cuanto_se_llega_y_no_se_cobra_nada_mas() -> void:
	var e := _pasan_todos(_estado(MESA, [39, 39] as Array[int]))
	assert_eq(e.juegos, [1, 0] as Array[int], "la Grande en paso se cobra antes que la Chica")
	assert_eq(e.juegos_jugados, [{"equipo": 0, "piedras": [40, 39], "motivo": "piedras"}] as Array[Dictionary])
	assert_eq(_cobros(e), [[L.GRANDE, 0, 1, "paso"]])
	assert_eq(e.ultima_mano["juego_para"], 0)
	assert_eq(e.piedras, [0, 0] as Array[int], "el juego siguiente empieza de cero")
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	assert_false(motor.ha_terminado(e), "la partida es al mejor de 3")


func test_el_deje_puede_ganar_el_juego_en_el_acto() -> void:
	var e := _aplicar(_estado(MESA, [0, 39] as Array[int]), 0, PASAR)
	e = _aplicar(e, 1, ENVIDO)
	e = _aplicar(_aplicar(e, 2, NO_QUIERO), 0, NO_QUIERO)
	assert_eq(e.juegos, [0, 1] as Array[int])
	assert_eq(e.ultima_mano["lances"].size(), 1, "no se juegan los demás lances")
	assert_eq(e.jugador_mano, 1)


func test_ordago_querido_gana_el_juego_la_mejor_jugada() -> void:
	var e := _aplicar(_aplicar(_estado(MESA, [10, 30] as Array[int]), 0, ORDAGO), 1, QUIERO)
	assert_eq(e.juegos, [1, 0] as Array[int], "la mejor Grande es del 0")
	assert_eq(e.juegos_jugados[0]["motivo"], "ordago")
	assert_eq(e.juegos_jugados[0]["piedras"], [10, 30])
	assert_eq(e.ultima_mano["manos"], MESA, "se enseñan todas las cartas")


func test_ordago_a_la_chica_lo_gana_la_otra_pareja() -> void:
	var e := _estado()
	for i in 4:
		e = _aplicar(e, e.turno, PASAR)
	e = _aplicar(_aplicar(e, 0, ORDAGO), 1, QUIERO)
	assert_eq(e.juegos, [0, 1] as Array[int])


func test_ordago_a_los_pares_entre_quienes_los_tienen() -> void:
	var e := _estado()
	for lance in 2:
		for i in 4:
			e = _aplicar(e, e.turno, PASAR)
	e = _aplicar(_aplicar(e, 0, PASAR), 1, ORDAGO)
	e = _aplicar(e, 0, QUIERO)
	assert_eq(e.juegos, [1, 0] as Array[int], "los reyes del 0 ganan a ases y caballos")


# --- Fin de la partida ---

func test_la_partida_la_gana_quien_gana_dos_juegos() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, ORDAGO), 1, QUIERO)
	assert_false(motor.ha_terminado(e))
	e.manos = []
	for ids: Array in MESA:
		e.manos.append(_cartas(ids))
	motor._empezar_lances(e)
	e = _aplicar(e, e.turno, ORDAGO)
	e = _aplicar(e, e.turno, QUIERO)
	assert_true(motor.ha_terminado(e))
	assert_eq(e.equipo_ganador, 0)
	assert_eq(motor.calcular_resultado(e), {
		"equipo_ganador": 0,
		"puntos_por_equipo": [2, 0],
		"juegos": [
			{"equipo": 0, "piedras": [0, 0], "motivo": "ordago"},
			{"equipo": 0, "piedras": [0, 0], "motivo": "ordago"},
		],
		"piedras_por_juego": 40,
	})
	for jugador in 4:
		assert_eq(motor.jugadas_validas(e, jugador), [] as Array[Dictionary])
	assert_eq(motor.aplicar_jugada(e, e.turno, PASAR).error, MotorDeJuego.ERROR_PARTIDA_TERMINADA)


func test_variante_corta_a_un_juego_de_30_piedras() -> void:
	motor = _motor(30, 1)
	var e := _pasan_todos(_estado(MESA, [29, 0] as Array[int]))
	assert_true(motor.ha_terminado(e))
	assert_eq(motor.calcular_resultado(e)["equipo_ganador"], 0)
	assert_eq(motor.calcular_resultado(e)["piedras_por_juego"], 30)


func test_resultado_antes_de_terminar() -> void:
	var resultado := motor.calcular_resultado(_estado())
	assert_eq(resultado["equipo_ganador"], -1)
	assert_eq(resultado["puntos_por_equipo"], [0, 0])


# --- Vista ---

func test_la_vista_cuenta_piedras_amarracos_y_juegos() -> void:
	var e := _pasan_todos(_estado(MESA, [12, 4] as Array[int]))
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq(vista["piedras"], [14, 7])
	assert_eq(vista["amarracos"], [2, 1])
	assert_eq(vista["juegos"], [0, 0])
	assert_eq(vista["piedras_por_juego"], 40)
	assert_eq(vista["juegos_para_ganar"], 2)
	assert_eq(vista["ultima_mano"]["manos"], MESA, "las cartas de la mano anterior ya se enseñaron")
	assert_eq(vista["ultima_mano"]["cobros"][0], {"lance": "grande", "equipo": 0, "piedras": 1, "concepto": "paso"})
	assert_eq(vista["ultima_mano"]["lances"][0]["lance"], "grande")
	# Las de la mano en curso, no.
	var texto := JSON.stringify(_sin_ultima_mano(vista))
	for otro in [1, 2, 3]:
		for id: String in MotorMus._ids(e.manos[otro]):
			assert_false(texto.contains("\"%s\"" % id), "el 0 ve una carta del %d" % otro)


func _sin_ultima_mano(vista: Dictionary) -> Dictionary:
	var copia := vista.duplicate()
	copia.erase("ultima_mano")
	return copia
