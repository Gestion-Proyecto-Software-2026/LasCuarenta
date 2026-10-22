extends GutTest
## Reparto, fase de Mus y descartes (analisis_funcional_app.md §9).

const SEMILLA := 2026


func _motor(semilla := SEMILLA) -> MotorMus:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return MotorMus.new(rng)


func _aplicar(motor: MotorMus, e: EstadoMus, jugador_id: int, jugada: Dictionary) -> EstadoMus:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, resultado.error)
	return resultado.estado


## Todos piden mus.
func _todos_mus(motor: MotorMus, e: EstadoMus) -> EstadoMus:
	for i in e.num_jugadores:
		e = _aplicar(motor, e, e.turno, {"tipo": "mus"})
	return e


## Cada uno, en su turno, se descarta de las [param cuantas] primeras cartas de su mano.
func _todos_descartan(motor: MotorMus, e: EstadoMus, cuantas := 4) -> EstadoMus:
	for i in e.num_jugadores:
		var ids: Array = MotorMus._ids(e.manos[e.turno]).slice(0, cuantas)
		e = _aplicar(motor, e, e.turno, {"tipo": "descartar", "cartas": ids})
	return e


func _todas_las_cartas(e: EstadoMus) -> Array[String]:
	var ids: Array[String] = []
	for mano: Array in e.manos:
		ids.append_array(MotorMus._ids(mano))
	ids.append_array(MotorMus._ids(e.mazo))
	ids.append_array(MotorMus._ids(e.descartes))
	for descarte: Array in e.descarte_ronda:
		ids.append_array(MotorMus._ids(descarte))
	return ids


func _sin_repetidas(ids: Array[String]) -> bool:
	var unicas := {}
	for id in ids:
		unicas[id] = true
	return unicas.size() == ids.size()


# --- Reparto ---

func test_admite_dos_y_cuatro_jugadores() -> void:
	assert_eq(_motor().jugadores_admitidos(), [2, 4])
	assert_null(_motor().iniciar(3))
	assert_push_error("no admite 3 jugadores")


func test_reparte_cuatro_cartas_a_cada_jugador_con_cuatro() -> void:
	var e := _motor().iniciar(4) as EstadoMus
	for mano: Array in e.manos:
		assert_eq(mano.size(), 4)
	assert_eq(e.mazo.size(), 24)
	assert_eq(_todas_las_cartas(e).size(), 40)
	assert_true(_sin_repetidas(_todas_las_cartas(e)), "ninguna carta repetida")


func test_reparte_cuatro_cartas_a_cada_jugador_con_dos() -> void:
	var e := _motor().iniciar(2) as EstadoMus
	assert_eq(e.manos.size(), 2)
	for mano: Array in e.manos:
		assert_eq(mano.size(), 4)
	assert_eq(e.mazo.size(), 32)


func test_reparte_de_una_en_una_empezando_por_la_mano() -> void:
	var e := _motor().iniciar(4) as EstadoMus
	# Se reproduce el mismo sorteo y barajado que hace el motor con esa semilla.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA
	var mano := rng.randi_range(0, 3)
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)
	var ids := MotorMus._ids(cartas)

	assert_eq(e.jugador_mano, mano)
	for i in 4:
		var jugador := (mano + i) % 4
		var esperada: Array[String] = []
		for vuelta in 4:
			esperada.append(ids[vuelta * 4 + i])
		assert_eq(MotorMus._ids(e.manos[jugador]), esperada, "mano del jugador %d" % jugador)


func test_la_mano_se_sortea() -> void:
	var manos := {}
	for semilla in 40:
		manos[(_motor(semilla).iniciar(4) as EstadoMus).jugador_mano] = true
	assert_eq(manos.size(), 4, "con distintas semillas sale mano cualquiera")


func test_misma_semilla_mismo_reparto() -> void:
	var a := _motor().iniciar(4) as EstadoMus
	var b := _motor().iniciar(4) as EstadoMus
	assert_eq(_todas_las_cartas(a), _todas_las_cartas(b))


# --- Fase de Mus ---

func test_empieza_hablando_la_mano_y_solo_ella() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoMus
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	assert_eq(e.turno, e.jugador_mano)
	assert_eq(motor.jugadas_validas(e, e.turno), [{"tipo": "mus"}, {"tipo": "no_mus"}] as Array[Dictionary])
	for otro in 4:
		if otro != e.turno:
			assert_eq(motor.jugadas_validas(e, otro), [] as Array[Dictionary])
			assert_false(motor.aplicar_jugada(e, otro, {"tipo": "mus"}).ok, "fuera de turno")


func test_mus_pasa_la_palabra_a_la_derecha() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoMus
	var mano := e.jugador_mano
	e = _aplicar(motor, e, mano, {"tipo": "mus"})
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	assert_eq(e.turno, (mano + 1) % 4)


func test_no_hay_mus_corta_para_todos_y_empieza_el_juego() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoMus
	var mano := e.jugador_mano
	var antes := _todas_las_cartas(e)
	e = _aplicar(motor, e, mano, {"tipo": "mus"})
	e = _aplicar(motor, e, (mano + 1) % 4, {"tipo": "no_mus"})
	assert_eq(e.fase, EstadoMus.Fase.LANCES)
	assert_eq(e.turno, mano, "en los lances también habla primero la mano")
	assert_eq(_todas_las_cartas(e), antes, "se juega con las cartas repartidas")


func test_si_todos_piden_mus_se_descartan_empezando_por_la_mano() -> void:
	var motor := _motor()
	var e := _todos_mus(motor, motor.iniciar(4) as EstadoMus)
	assert_eq(e.fase, EstadoMus.Fase.DESCARTE)
	assert_eq(e.turno, e.jugador_mano)
	assert_eq(motor.jugadas_validas(e, e.turno).size(), 15, "de 1 a 4 de sus 4 cartas")
	assert_eq(motor.jugadas_validas(e, (e.turno + 1) % 4), [] as Array[Dictionary])


func test_mus_a_dos_jugadores() -> void:
	var motor := _motor()
	var e := motor.iniciar(2) as EstadoMus
	e = _aplicar(motor, e, e.turno, {"tipo": "mus"})
	assert_eq(e.fase, EstadoMus.Fase.MUS)
	e = _aplicar(motor, e, e.turno, {"tipo": "mus"})
	assert_eq(e.fase, EstadoMus.Fase.DESCARTE)


# --- Descarte ---

func test_descarte_en_cualquier_orden_y_con_array_sin_tipo() -> void:
	var motor := _motor()
	var e := _todos_mus(motor, motor.iniciar(4) as EstadoMus)
	var ids := MotorMus._ids(e.manos[e.turno])
	# Por la red llega un Array sin tipo, y el orden lo elige el cliente.
	var resultado := motor.aplicar_jugada(e, e.turno, {"tipo": "descartar", "cartas": [ids[2], ids[0]]})
	assert_true(resultado.ok, resultado.error)
	var mano_tras := MotorMus._ids((resultado.estado as EstadoMus).manos[e.turno])
	assert_eq(mano_tras, [ids[1], ids[3]] as Array[String], "hasta que se completen las manos")


func test_descartes_no_validos() -> void:
	var motor := _motor()
	var e := _todos_mus(motor, motor.iniciar(4) as EstadoMus)
	var ids := MotorMus._ids(e.manos[e.turno])
	var ajena: String = MotorMus._ids(e.manos[(e.turno + 1) % 4])[0]
	for cartas: Variant in [[], [ajena], [ids[0], ids[0]], ids + [ajena], "oros_1", ["no_es_carta"]]:
		assert_false(motor.aplicar_jugada(e, e.turno, {"tipo": "descartar", "cartas": cartas}).ok,
			"descarte %s" % [cartas])
	assert_false(motor.aplicar_jugada(e, e.turno, {"tipo": "descartar"}).ok, "sin cartas")
	assert_false(motor.aplicar_jugada(e, e.turno, {"tipo": "mus"}).ok, "ya no se dice mus")


func test_tras_descartarse_todos_se_completan_las_manos_y_vuelve_el_mus() -> void:
	var motor := _motor()
	var e := _todos_mus(motor, motor.iniciar(4) as EstadoMus)
	var mano := e.jugador_mano
	var pedidas := [1, 2, 3, 4]
	var descartadas: Array[String] = []
	for i in 4:
		var ids: Array = MotorMus._ids(e.manos[e.turno]).slice(0, pedidas[i])
		descartadas.append_array(ids)
		e = _aplicar(motor, e, e.turno, {"tipo": "descartar", "cartas": ids})
	for mano_jugador: Array in e.manos:
		assert_eq(mano_jugador.size(), 4)
		for id: String in MotorMus._ids(mano_jugador):
			assert_false(id in descartadas, "no le vuelve ninguna descartada")
	assert_eq(e.mazo.size(), 24 - 10)
	assert_eq(e.descartes.size(), 10)
	assert_eq(e.fase, EstadoMus.Fase.MUS, "se vuelve a preguntar mus")
	assert_eq(e.turno, mano)
	assert_eq(e.rondas_de_descarte, 1)
	var pedidas_por_asiento: Array[int] = [0, 0, 0, 0]
	for i in 4:
		pedidas_por_asiento[(mano + i) % 4] = pedidas[i]
	assert_eq(e.cartas_pedidas, pedidas_por_asiento)
	assert_eq(_todas_las_cartas(e).size(), 40)
	assert_true(_sin_repetidas(_todas_las_cartas(e)))


func test_si_se_agota_el_mazo_se_rebarajan_los_descartes_sin_devolver_los_propios() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoMus
	# 24 en el mazo: la 1ª ronda de 4 cartas deja 8 y la 2ª lo agota a mitad.
	for ronda in 2:
		e = _todos_mus(motor, e)
		var mano_antes: Array = []
		for jugador in 4:
			mano_antes.append(MotorMus._ids(e.manos[jugador]))
		e = _todos_descartan(motor, e)
		for jugador in 4:
			for id: String in MotorMus._ids(e.manos[jugador]):
				assert_false(id in mano_antes[jugador], "ronda %d, jugador %d: le vuelve %s" % [ronda, jugador, id])
		assert_eq(_todas_las_cartas(e).size(), 40)
		assert_true(_sin_repetidas(_todas_las_cartas(e)))
	assert_eq(e.rondas_de_descarte, 2)


func test_el_descarte_se_puede_repetir_muchas_veces() -> void:
	var motor := _motor()
	var e := motor.iniciar(2) as EstadoMus
	for ronda in 12:
		e = _todos_descartan(motor, _todos_mus(motor, e))
	assert_eq(e.rondas_de_descarte, 12)
	assert_true(_sin_repetidas(_todas_las_cartas(e)))
	assert_eq(_todas_las_cartas(e).size(), 40)


# --- Vista ---

func test_la_vista_no_ensena_las_cartas_de_los_demas() -> void:
	var motor := _motor()
	var e := _todos_descartan(motor, _todos_mus(motor, motor.iniciar(4) as EstadoMus), 2)
	for jugador in 4:
		var vista := motor.vista_para_jugador(e, jugador)
		assert_eq(vista["mi_mano"], MotorMus._ids(e.manos[jugador]))
		var texto := JSON.stringify(vista)
		for otro in 4:
			if otro != jugador:
				for id: String in MotorMus._ids(e.manos[otro]):
					assert_false(texto.contains("\"%s\"" % id), "el %d ve una carta del %d" % [jugador, otro])
		assert_eq(vista["fase"], "mus")
		assert_eq(vista["cartas_pedidas"], [2, 2, 2, 2])
