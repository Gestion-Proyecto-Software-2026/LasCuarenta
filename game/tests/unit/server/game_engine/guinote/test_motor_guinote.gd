extends GutTest
## Reparto, bazas con robada y robo del Guiñote (analisis_funcional_app.md §8).

const SEMILLA := 2026


func _motor(semilla := SEMILLA) -> MotorGuinote:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return MotorGuinote.new(rng)


func _baza(ids: Array[String], primero := 0) -> Array[Dictionary]:
	var baza: Array[Dictionary] = []
	for i in ids.size():
		baza.append({"jugador_id": (primero + i) % 4, "carta": Carta.desde_id(ids[i])})
	return baza


## Juega una baza completa: cada jugador, en su turno, su primera carta válida.
## Si al cerrarla hay que decidir el cambio del siete, no se cambia.
func _jugar_baza(motor: MotorGuinote, estado: EstadoGuinote) -> EstadoGuinote:
	for i in 4:
		var jugada: Dictionary = motor.jugadas_validas(estado, estado.turno)[0]
		var resultado := motor.aplicar_jugada(estado, estado.turno, jugada)
		assert_true(resultado.ok, resultado.error)
		estado = resultado.estado
	if estado.siete_pendiente != -1:
		estado = motor.aplicar_jugada(estado, estado.siete_pendiente, {"tipo": "no_cambiar_siete"}).estado
	return estado


func _todas_las_cartas(e: EstadoGuinote) -> Array[String]:
	var ids: Array[String] = []
	for mano: Array in e.manos:
		ids.append_array(MotorGuinote._ids(mano))
	ids.append_array(MotorGuinote._ids(e.mazo))
	if e.pinta != null:
		ids.append(e.pinta.id)
	for cartas: Array in e.cartas_ganadas:
		ids.append_array(MotorGuinote._ids(cartas))
	return ids


# --- Reparto ---

func test_solo_admite_cuatro_jugadores() -> void:
	assert_eq(_motor().jugadores_admitidos(), [4])


func test_reparto_seis_cartas_por_jugador_pinta_y_mazo() -> void:
	var e := _motor().iniciar(4) as EstadoGuinote
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)
	assert_not_null(e.pinta)
	assert_eq(e.palo_triunfo, e.pinta.palo, "la pinta marca el triunfo")
	assert_eq(e.mazo.size(), 15)
	var ids := _todas_las_cartas(e)
	assert_eq(ids.size(), 40)
	var unicas := {}
	for id in ids:
		unicas[id] = true
	assert_eq(unicas.size(), 40, "ninguna carta repetida ni perdida")


func test_reparto_en_dos_tandas_de_tres_desde_la_derecha_del_dador() -> void:
	var e := _motor().iniciar(4) as EstadoGuinote
	# Se reproduce el mismo sorteo y barajado que hace el motor con esa semilla.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA
	var dador := rng.randi_range(0, 3)
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)
	var ids := MotorGuinote._ids(cartas)

	assert_eq(e.dador, dador)
	for i in 4:
		var jugador := (dador + 1 + i) % 4
		var esperada := ids.slice(i * 3, i * 3 + 3) + ids.slice(12 + i * 3, 12 + i * 3 + 3)
		assert_eq(MotorGuinote._ids(e.manos[jugador]), esperada, "mano del jugador %d" % jugador)
	assert_eq(e.pinta.id, ids[24], "la pinta es la carta siguiente al reparto")
	assert_eq(MotorGuinote._ids(e.mazo), ids.slice(25), "el resto queda en el mazo en orden")


func test_el_dador_se_sortea() -> void:
	var dadores := {}
	for semilla in 40:
		dadores[(_motor(semilla).iniciar(4) as EstadoGuinote).dador] = true
	assert_eq(dadores.size(), 4, "con 40 semillas deberían salir los cuatro asientos")


func test_sale_el_jugador_a_la_derecha_del_dador_y_puede_jugar_cualquier_carta() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	var primero := (e.dador + 1) % 4
	assert_eq(e.turno, primero)
	assert_eq(motor.jugadas_validas(e, primero).size(), 6)
	for otro in 4:
		if otro != primero:
			assert_eq(motor.jugadas_validas(e, otro), [] as Array[Dictionary], "jugador %d" % otro)


# --- Quién gana la baza ---

func test_sin_triunfo_gana_la_mas_alta_del_palo_de_salida() -> void:
	# Triunfo oros. El As de espadas es más alto, pero no es del palo de salida.
	var baza := _baza(["copas_2", "copas_3", "espadas_1", "copas_12"])
	assert_eq(MotorGuinote.ganador_de_baza(baza, Carta.Palo.OROS), 1)


func test_cualquier_triunfo_gana_a_otro_palo() -> void:
	var baza := _baza(["copas_1", "oros_2", "copas_3", "espadas_1"])
	assert_eq(MotorGuinote.ganador_de_baza(baza, Carta.Palo.OROS), 1)


func test_gana_el_triunfo_mas_alto() -> void:
	var baza := _baza(["copas_1", "oros_2", "oros_3", "oros_12"], 2)
	assert_eq(MotorGuinote.ganador_de_baza(baza, Carta.Palo.OROS), 0, "el tres de oros lo juega el jugador 0")


func test_orden_de_fuerza_del_guinote() -> void:
	# As > Tres > Rey > Sota > Caballo > 7 > 6 > 5 > 4 > 2
	var orden := ["bastos_1", "bastos_3", "bastos_12", "bastos_10", "bastos_11",
		"bastos_7", "bastos_6", "bastos_5", "bastos_4", "bastos_2"]
	for i in orden.size() - 1:
		var alta := Carta.desde_id(orden[i])
		var baja := Carta.desde_id(orden[i + 1])
		assert_true(MotorGuinote.gana_a(alta, baja, Carta.Palo.OROS), "%s > %s" % [alta, baja])
		assert_false(MotorGuinote.gana_a(baja, alta, Carta.Palo.OROS), "%s < %s" % [baja, alta])


func test_la_sota_gana_al_caballo() -> void:
	var baza := _baza(["bastos_11", "bastos_10"])
	assert_eq(MotorGuinote.ganador_de_baza(baza, Carta.Palo.OROS), 1)


func test_valor_de_las_cartas() -> void:
	var total := 0
	for carta in Baraja.crear():
		total += MotorGuinote.puntos_de(carta)
	assert_eq(total, 120, "con las diez últimas, las cartas suman 130 (§8)")
	assert_eq(MotorGuinote.puntos_de(Carta.desde_id("copas_10")), 3, "sota")
	assert_eq(MotorGuinote.puntos_de(Carta.desde_id("copas_11")), 2, "caballo")
	assert_eq(MotorGuinote.puntos_de(Carta.desde_id("copas_7")), 0)


# --- Bazas con robada ---

func test_el_turno_avanza_en_el_sentido_del_juego() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	var primero := e.turno
	var jugada: Dictionary = motor.jugadas_validas(e, primero)[0]
	e = motor.aplicar_jugada(e, primero, jugada).estado
	assert_eq(e.turno, (primero + 1) % 4)
	assert_eq(e.baza_actual.size(), 1)


func test_tras_la_baza_el_ganador_sale_y_todos_roban_empezando_por_el() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	var primeras_del_mazo := MotorGuinote._ids(e.mazo.slice(0, 4))
	e = _jugar_baza(motor, e)

	var ganador: int = e.ultima_baza["ganador"]
	assert_eq(e.turno, ganador, "quien gana la baza sale en la siguiente")
	for i in 4:
		var jugador := (ganador + i) % 4
		assert_eq(e.manos[jugador].size(), 6)
		assert_eq(e.manos[jugador].back().id, primeras_del_mazo[i],
			"el jugador %d roba la %dª carta del mazo" % [jugador, i + 1])
	assert_eq(e.mazo.size(), 11)
	assert_eq(e.cartas_ganadas[MotorDeJuego.equipo_de(ganador)].size(), 4)
	assert_eq(e.cartas_ganadas[1 - MotorDeJuego.equipo_de(ganador)].size(), 0)


func test_la_pinta_se_roba_la_ultima_y_empieza_el_arrastre() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	var pinta := e.pinta.id
	for baza in 3:
		e = _jugar_baza(motor, e)
		assert_eq(e.fase, EstadoGuinote.Fase.ROBO)
		assert_not_null(e.pinta, "la pinta sigue en la mesa tras la baza %d" % (baza + 1))
	e = _jugar_baza(motor, e)

	assert_eq(e.fase, EstadoGuinote.Fase.ARRASTRE)
	assert_eq(e.bazas_jugadas, 4)
	assert_true(e.mazo.is_empty())
	assert_null(e.pinta)
	var ultimo_en_robar := (int(e.ultima_baza["ganador"]) + 3) % 4
	assert_has(MotorGuinote._ids(e.manos[ultimo_en_robar]), pinta, "roba la pinta el último del turno de robo")
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)
	assert_eq(_todas_las_cartas(e).size(), 40)


# --- Vista del jugador ---

func test_la_vista_no_ensena_manos_ajenas_ni_el_mazo() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq(vista["mi_mano"], MotorGuinote._ids(e.manos[0]))
	assert_eq(vista["cartas_por_jugador"], [6, 6, 6, 6])
	assert_eq(vista["cartas_en_mazo"], 16, "15 boca abajo + la pinta")
	assert_eq(vista["pinta"], e.pinta.id)
	var visibles := _textos_de(vista)
	for otro in [1, 2, 3]:
		for carta: Carta in e.manos[otro]:
			assert_does_not_have(visibles, carta.id, "no debe aparecer %s del jugador %d" % [carta.id, otro])
	for carta: Carta in e.mazo:
		assert_does_not_have(visibles, carta.id, "no debe aparecer %s del mazo" % carta.id)


## Todos los textos que aparecen en cualquier nivel de [param valor].
func _textos_de(valor: Variant) -> Array[String]:
	var textos: Array[String] = []
	if valor is String:
		textos.append(valor)
	elif valor is Array:
		for elemento: Variant in valor:
			textos.append_array(_textos_de(elemento))
	elif valor is Dictionary:
		for clave: Variant in valor:
			textos.append_array(_textos_de(clave))
			textos.append_array(_textos_de(valor[clave]))
	return textos


func test_la_vista_muestra_la_baza_en_curso_y_la_ultima() -> void:
	var motor := _motor()
	var e := motor.iniciar(4) as EstadoGuinote
	e = _jugar_baza(motor, e)
	var jugada: Dictionary = motor.jugadas_validas(e, e.turno)[0]
	var quien := e.turno
	e = motor.aplicar_jugada(e, quien, jugada).estado
	var vista := motor.vista_para_jugador(e, 2)
	assert_eq(vista["baza_actual"], [{"jugador_id": quien, "carta_id": jugada["carta_id"]}])
	assert_eq(vista["ultima_baza"]["cartas"].size(), 4)
	assert_eq(vista["bazas_jugadas"], 1)
	assert_eq(vista["fase"], "robo")
