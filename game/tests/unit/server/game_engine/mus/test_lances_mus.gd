extends GutTest
## Lances y envites del Mus: pasar, envidar, reenvidar, órdago, quiero y no
## quiero (analisis_funcional_app.md §9). Los estados se construyen a mano,
## con el mus ya cortado y el 0 de mano.

const L := EstadoMus.Lance

# Mesa de ejemplo (parejas 0-2 contra 1-3):
# - 0: R R C 4 -> buena a Grande, par de reyes, juego de 34.
# - 1: A A 4 5 -> la mejor Chica, par de ases, 11 (sin juego).
# - 2: 3 7 6 S -> sin pares, juego de 33.
# - 3: C C S 7 -> par de caballos, juego de 37.
const MESA := [
	["oros_12", "copas_12", "espadas_11", "bastos_4"],
	["oros_1", "copas_2", "espadas_4", "bastos_5"],
	["oros_3", "copas_7", "espadas_6", "bastos_10"],
	["oros_11", "copas_11", "espadas_10", "bastos_7"],
]

var motor: MotorMus


func before_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	motor = MotorMus.new(rng)


func _cartas(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


## Estado al empezar los lances, con las manos [param manos] y la mano en [param mano].
func _estado(manos: Array = MESA, mano := 0) -> EstadoMus:
	var e := EstadoMus.new()
	e.num_jugadores = manos.size()
	e.jugador_mano = mano
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


## Pasan todos los que hablan en el lance en curso.
func _pasan_todos(e: EstadoMus) -> EstadoMus:
	for jugador in e.hablan.duplicate():
		e = _aplicar(e, jugador, {"tipo": "pasar"})
	return e


func _ultimo(e: EstadoMus) -> Dictionary:
	return e.lances_jugados[-1]


const PASAR := {"tipo": "pasar"}
const QUIERO := {"tipo": "quiero"}
const NO_QUIERO := {"tipo": "no_quiero"}
const ORDAGO := {"tipo": "ordago"}


func _envido(cantidad := 2) -> Dictionary:
	return {"tipo": "envidar", "cantidad": cantidad}


# --- Orden de los lances ---

func test_empieza_por_la_grande_hablando_la_mano() -> void:
	var e := _estado()
	assert_eq(e.fase, EstadoMus.Fase.LANCES)
	assert_eq(e.lance, L.GRANDE)
	assert_eq(e.hablan, [0, 1, 2, 3] as Array[int])
	assert_eq(e.turno, 0)


func test_la_palabra_empieza_por_la_mano_aunque_no_sea_el_0() -> void:
	var e := _estado(MESA, 2)
	assert_eq(e.hablan, [2, 3, 0, 1] as Array[int])
	assert_eq(e.turno, 2)


func test_si_pasan_todos_se_juegan_los_lances_en_orden() -> void:
	var e := _pasan_todos(_estado())
	assert_eq(e.lance, L.CHICA)
	assert_eq(e.turno, 0)
	e = _pasan_todos(e)
	assert_eq(e.lance, L.PARES)
	assert_eq(e.hablan, [0, 1, 3] as Array[int], "en Pares solo hablan quienes los tienen")
	assert_eq(e.turno, 0)
	e = _pasan_todos(e)
	assert_eq(e.lance, L.JUEGO)
	assert_eq(e.hablan, [0, 2, 3] as Array[int], "en Juego solo hablan quienes lo tienen")
	var resultados := e.lances_jugados.map(func(l: Dictionary) -> Array: return [l["lance"], l["resultado"]])
	assert_eq(resultados, [[L.GRANDE, "paso"], [L.CHICA, "paso"], [L.PARES, "paso"]])


func test_al_acabar_el_ultimo_lance_es_mano_el_de_la_derecha_y_se_reparte() -> void:
	var e := _estado()
	for lance in 4:
		e = _pasan_todos(e)
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	assert_eq(e.jugador_mano, 1)
	assert_eq(e.turno, 1)
	for mano: Array in e.manos:
		assert_eq(mano.size(), 4)


func test_punto_si_nadie_tiene_juego() -> void:
	var manos := [
		["oros_12", "copas_12", "espadas_5", "bastos_4"],
		["oros_1", "copas_2", "espadas_4", "bastos_5"],
		["oros_3", "copas_7", "espadas_6", "bastos_1"],
		["oros_11", "copas_4", "espadas_5", "bastos_7"],
	]
	var e := _pasan_todos(_pasan_todos(_estado(manos)))
	assert_eq(e.lance, L.PARES)
	e = _pasan_todos(e)
	assert_eq(e.lance, L.PUNTO)
	assert_eq(e.hablan, [0, 1, 2, 3] as Array[int], "al Punto hablan todos")


func test_pares_sin_rivales_no_se_envida_y_se_pasa_al_juego() -> void:
	# Solo la pareja 0-2 tiene pares.
	var manos := [
		["oros_12", "copas_12", "espadas_11", "bastos_4"],
		["oros_1", "copas_6", "espadas_4", "bastos_5"],
		["oros_3", "copas_3", "espadas_6", "bastos_10"],
		["oros_11", "copas_5", "espadas_10", "bastos_7"],
	]
	var e := _pasan_todos(_pasan_todos(_estado(manos)))
	assert_eq(e.lance, L.JUEGO, "los pares se cobran al final, sin envite")
	assert_eq(e.lances_jugados[2], {"lance": L.PARES, "resultado": "paso", "apuesta": 0, "equipo": -1, "ordago": false})


func test_si_nadie_tiene_pares_el_lance_no_se_juega() -> void:
	var manos := [
		["oros_12", "copas_7", "espadas_11", "bastos_4"],
		["oros_1", "copas_6", "espadas_4", "bastos_5"],
		["oros_7", "copas_10", "espadas_6", "bastos_5"],
		["oros_11", "copas_5", "espadas_10", "bastos_7"],
	]
	var e := _pasan_todos(_pasan_todos(_estado(manos)))
	assert_eq(e.lances_jugados[2]["resultado"], "sin_jugada")
	assert_ne(e.lance, L.PARES)


# --- Envites ---

func test_sin_envite_se_puede_pasar_envidar_de_2_a_10_u_ordago() -> void:
	var validas := motor.jugadas_validas(_estado(), 0)
	assert_eq(validas[0], PASAR)
	assert_true(_envido(2) in validas)
	assert_true(_envido(10) in validas)
	assert_false(_envido(1) in validas)
	assert_false(_envido(11) in validas)
	assert_true(ORDAGO in validas)
	assert_false(QUIERO in validas)
	assert_eq(validas.size(), 1 + 9 + 1)


func test_solo_habla_quien_tiene_la_palabra() -> void:
	var e := _estado()
	for otro in [1, 2, 3]:
		assert_eq(motor.jugadas_validas(e, otro), [] as Array[Dictionary])
		assert_false(motor.aplicar_jugada(e, otro, PASAR).ok)


func test_contesta_el_primer_rival_y_el_companero_no_habla() -> void:
	var e := _aplicar(_estado(), 0, _envido(3))
	assert_eq(e.turno, 1)
	assert_eq(e.envite["apuesta"], 3)
	assert_eq(e.envite["responden"], [1, 3] as Array[int])
	assert_eq(motor.jugadas_validas(e, 2), [] as Array[Dictionary], "el compañero del que envida no contesta")
	var validas := motor.jugadas_validas(e, 1)
	assert_true(QUIERO in validas)
	assert_true(NO_QUIERO in validas)
	assert_false(PASAR in validas)
	assert_true(_envido(2) in validas, "puede subir")
	assert_true(ORDAGO in validas)


func test_envite_querido() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, _envido()), 1, QUIERO)
	assert_eq(_ultimo(e), {"lance": L.GRANDE, "resultado": "querido", "apuesta": 2, "equipo": 0, "ordago": false})
	assert_eq(e.lance, L.CHICA)
	assert_eq(e.envite, {})
	assert_eq(e.piedras, [0, 0] as Array[int], "lo querido se cobra al final de la mano")


func test_basta_con_que_lo_quiera_uno_de_la_pareja() -> void:
	var e := _aplicar(_aplicar(_aplicar(_estado(), 0, _envido()), 1, NO_QUIERO), 3, QUIERO)
	assert_eq(_ultimo(e)["resultado"], "querido")


func test_no_querido_por_los_dos_rivales_cobra_el_deje_en_el_acto() -> void:
	var e := _aplicar(_estado(), 0, _envido(5))
	e = _aplicar(e, 1, NO_QUIERO)
	assert_eq(e.turno, 3, "contesta el compañero")
	e = _aplicar(e, 3, NO_QUIERO)
	assert_eq(e.piedras, [1, 0] as Array[int])
	assert_eq(_ultimo(e), {"lance": L.GRANDE, "resultado": "no_querido", "apuesta": 1, "equipo": 0, "ordago": false})
	assert_eq(e.lance, L.CHICA)


func test_envidar_despues_de_que_otros_pasen() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, PASAR), 1, _envido())
	assert_eq(e.envite["responden"], [2, 0] as Array[int], "contestan por orden desde quien envida")
	assert_eq(e.turno, 2)


func test_reenvite_no_querido_cobra_lo_que_habia_antes() -> void:
	var e := _aplicar(_estado(), 0, _envido(2))
	e = _aplicar(e, 1, _envido(3))
	assert_eq(e.envite["apuesta"], 5)
	assert_eq(e.envite["apuesta_previa"], 2)
	assert_eq(e.envite["equipo"], 1)
	assert_eq(e.envite["responden"], [2, 0] as Array[int])
	e = _aplicar(e, 2, NO_QUIERO)
	e = _aplicar(e, 0, NO_QUIERO)
	assert_eq(e.piedras, [0, 2] as Array[int], "el envite de 2 que no se quiso subir")


func test_reenvite_querido() -> void:
	var e := _aplicar(_aplicar(_aplicar(_estado(), 0, _envido(2)), 1, _envido(3)), 2, QUIERO)
	assert_eq(_ultimo(e)["apuesta"], 5)
	assert_eq(_ultimo(e)["equipo"], 1)


func test_ante_un_ordago_solo_se_quiere_o_no() -> void:
	var e := _aplicar(_estado(), 0, ORDAGO)
	assert_true(e.envite["ordago"])
	assert_eq(motor.jugadas_validas(e, 1), [QUIERO, NO_QUIERO] as Array[Dictionary])


func test_ordago_no_querido_cobra_el_deje() -> void:
	var e := _aplicar(_aplicar(_aplicar(_estado(), 0, ORDAGO), 1, NO_QUIERO), 3, NO_QUIERO)
	assert_eq(e.piedras, [1, 0] as Array[int])
	assert_eq(_ultimo(e)["resultado"], "no_querido")
	assert_true(_ultimo(e)["ordago"])


func test_ordago_sobre_un_envite_no_querido_cobra_el_envite() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, _envido(4)), 1, ORDAGO)
	e = _aplicar(_aplicar(e, 2, NO_QUIERO), 0, NO_QUIERO)
	assert_eq(e.piedras, [0, 4] as Array[int])


func test_ordago_querido_acaba_la_mano() -> void:
	var e := _aplicar(_aplicar(_estado(), 0, ORDAGO), 1, QUIERO)
	assert_eq(e.fase, EstadoMus.Fase.MUS, "no se juegan más lances")
	assert_eq(e.jugador_mano, 1)


func test_en_pares_solo_contestan_los_rivales_que_los_tienen() -> void:
	var e := _pasan_todos(_pasan_todos(_estado()))
	assert_eq(e.lance, L.PARES)
	e = _aplicar(e, 0, _envido())
	assert_eq(e.envite["responden"], [1, 3] as Array[int])
	assert_false(motor.aplicar_jugada(e, 1, PASAR).ok, "ante un envite no se pasa: se dice no quiero")


func test_en_juego_contesta_solo_el_rival_con_juego() -> void:
	var e := _pasan_todos(_pasan_todos(_pasan_todos(_estado())))
	assert_eq(e.lance, L.JUEGO)
	e = _aplicar(e, 0, _envido())
	assert_eq(e.envite["responden"], [3] as Array[int], "el 1 no tiene juego")
	e = _aplicar(e, 3, NO_QUIERO)
	assert_eq(e.piedras, [1, 0] as Array[int])


# --- A dos jugadores ---

func test_lances_a_dos_jugadores() -> void:
	var e := _estado([MESA[0], MESA[1]], 1)
	assert_eq(e.hablan, [1, 0] as Array[int])
	e = _aplicar(e, 1, _envido())
	assert_eq(e.envite["responden"], [0] as Array[int])
	e = _aplicar(e, 0, NO_QUIERO)
	assert_eq(e.piedras, [0, 1] as Array[int])
	e = _pasan_todos(e)
	assert_eq(e.lance, L.PARES, "los dos tienen pares")
	e = _pasan_todos(e)
	# Solo el 0 tiene juego: se pasa sin envite y se acaba la mano.
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	assert_eq(e.jugador_mano, 0)


# --- Vista ---

func test_la_vista_cuenta_lo_publico_de_los_lances() -> void:
	var e := _aplicar(_estado(), 0, _envido(3))
	var vista := motor.vista_para_jugador(e, 2)
	assert_eq(vista["fase"], "lances")
	assert_eq(vista["lance"], "grande")
	assert_eq(vista["envite"]["apuesta"], 3)
	assert_eq(vista["tienen_pares"], null, "en Grande aún no se ha dicho quién lleva pares")
	e = _pasan_todos(_aplicar(e, 1, QUIERO))
	vista = motor.vista_para_jugador(e, 2)
	assert_eq(vista["lance"], "pares")
	assert_eq(vista["tienen_pares"], [true, true, false, true])
	assert_eq(vista["tienen_juego"], null)
	assert_eq(vista["lances_jugados"][0]["lance"], "grande")
	assert_eq(vista["lances_jugados"][0]["resultado"], "querido")
	var texto := JSON.stringify(vista)
	for otro in [0, 1, 3]:
		for id: String in MESA[otro]:
			assert_false(texto.contains("\"%s\"" % id), "el 2 ve una carta del %d" % otro)
