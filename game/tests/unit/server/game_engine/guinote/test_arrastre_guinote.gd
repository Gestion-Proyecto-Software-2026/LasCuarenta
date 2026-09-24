extends GutTest
## Fase de arrastre del Guiñote: obligaciones de asistir, montar y fallar
## (analisis_funcional_app.md §8) y partidas completas de 10 bazas.
##
## En todos los casos sueltos el triunfo es oros.

const TRIUNFO := Carta.Palo.OROS


func _cartas(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


## Baza en curso: [[jugador_id, carta_id], ...] en orden de juego.
func _baza(jugadas: Array) -> Array[Dictionary]:
	var baza: Array[Dictionary] = []
	for jugada: Array in jugadas:
		baza.append({"jugador_id": jugada[0], "carta": Carta.desde_id(jugada[1])})
	return baza


func _permitidas(mano: Array, baza: Array, jugador_id: int) -> Array[String]:
	var cartas := MotorGuinote.cartas_permitidas_en_arrastre(_cartas(mano), _baza(baza), TRIUNFO, jugador_id)
	return MotorGuinote._ids(cartas)


# --- Casos de cada obligación ---

func test_quien_abre_juega_libremente() -> void:
	var mano := ["copas_2", "oros_1", "espadas_7"]
	assert_eq(_permitidas(mano, [], 0), mano)


func test_asistir_y_montar_si_puede() -> void:
	# Sale copas_4: tiene copas_2 y copas_1; solo el As monta.
	assert_eq(_permitidas(["copas_2", "copas_1", "oros_3", "espadas_1"], [[0, "copas_4"]], 1), ["copas_1"])


func test_asistir_sin_montar_si_no_puede() -> void:
	# Sale el As de copas: nadie lo supera, pero hay que asistir con cualquier copa.
	assert_eq(_permitidas(["copas_2", "copas_7", "oros_3"], [[0, "copas_1"]], 1), ["copas_2", "copas_7"])


func test_montar_sobre_la_mas_alta_del_palo_aunque_sea_del_companero() -> void:
	# El compañero (jugador 0) va ganando con el Rey; aun así hay que superarlo.
	var baza := [[0, "copas_12"], [1, "copas_4"]]
	assert_eq(_permitidas(["copas_7", "copas_3"], baza, 2), ["copas_3"])


func test_montar_respeta_que_la_sota_supera_al_caballo() -> void:
	assert_eq(_permitidas(["copas_10", "copas_7"], [[0, "copas_11"]], 1), ["copas_10"])


func test_si_alguien_ha_fallado_basta_con_asistir() -> void:
	var baza := [[0, "copas_4"], [1, "oros_2"]]
	assert_eq(_permitidas(["copas_2", "copas_1", "oros_5"], baza, 2), ["copas_2", "copas_1"])


func test_si_sale_triunfo_hay_que_montar_en_triunfo() -> void:
	assert_eq(_permitidas(["oros_2", "oros_1", "copas_1"], [[0, "oros_4"]], 1), ["oros_1"])
	var baza := [[0, "oros_4"], [1, "oros_3"]]
	assert_eq(_permitidas(["oros_2", "oros_12", "copas_1"], baza, 2), ["oros_2", "oros_12"],
		"si no puede superar al Tres, asiste con cualquier triunfo")


func test_sin_el_palo_hay_que_fallar_si_ningun_rival_ha_fallado() -> void:
	assert_eq(_permitidas(["oros_2", "oros_1", "espadas_1"], [[0, "copas_4"]], 1), ["oros_2", "oros_1"])


func test_sin_el_palo_hay_que_superar_el_fallo_del_rival() -> void:
	# El jugador 1 (rival del 2) ha fallado con el Rey de oros.
	var baza := [[0, "copas_4"], [1, "oros_12"]]
	assert_eq(_permitidas(["oros_2", "oros_3", "espadas_1"], baza, 2), ["oros_3"])


func test_si_no_puede_superar_el_fallo_del_rival_juega_libre() -> void:
	var baza := [[0, "copas_4"], [1, "oros_12"]]
	assert_eq(_permitidas(["oros_2", "espadas_1"], baza, 2), ["oros_2", "espadas_1"])


func test_solo_cuenta_el_fallo_de_los_rivales() -> void:
	# Solo ha fallado el compañero (jugador 1 para el 3): hay que fallar igual,
	# con cualquier triunfo, sin necesidad de superarlo.
	var baza := [[0, "copas_4"], [1, "oros_12"], [2, "copas_5"]]
	assert_eq(_permitidas(["oros_2", "espadas_1"], baza, 3), ["oros_2"])


func test_sin_el_palo_ni_triunfo_juega_libre() -> void:
	assert_eq(_permitidas(["espadas_1", "bastos_2"], [[0, "copas_4"]], 1), ["espadas_1", "bastos_2"])


# --- Integración con el motor ---

func _motor(semilla: int) -> MotorGuinote:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return MotorGuinote.new(rng)


## Juega una partida entera eligiendo al azar entre las jugadas válidas de
## quien tiene que actuar (cartas, cantes y cambio del siete) y comprueba por el
## camino que nunca se queda sin jugada posible.
func _partida_al_azar(motor: MotorGuinote, rng: RandomNumberGenerator) -> EstadoGuinote:
	var e := motor.iniciar(4) as EstadoGuinote
	for paso in 1000:
		if motor.ha_terminado(e):
			break
		var actua := e.siete_pendiente if e.siete_pendiente != -1 else e.turno
		var validas := motor.jugadas_validas(e, actua)
		assert_false(validas.is_empty(), "el jugador %d se ha quedado sin jugadas (baza %d)" % [actua, e.bazas_jugadas + 1])
		if validas.is_empty():
			break
		var resultado := motor.aplicar_jugada(e, actua, validas[rng.randi_range(0, validas.size() - 1)])
		assert_true(resultado.ok, resultado.error)
		e = resultado.estado
	return e


func test_partidas_completas_hasta_el_final() -> void:
	var motivos := {}
	for semilla in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = semilla
		var motor := _motor(semilla)
		var e := _partida_al_azar(motor, rng)
		assert_true(motor.ha_terminado(e), "semilla %d" % semilla)
		var resultado := motor.calcular_resultado(e)
		assert_has([0, 1], resultado["equipo_ganador"])
		motivos[resultado["motivo"]] = true
		for jugador in 4:
			assert_eq(motor.jugadas_validas(e, jugador), [] as Array[Dictionary], "terminada, no se juega más")
		if resultado["motivo"] == "tute" and resultado["manos"].size() == 1:
			continue  # un Tute en las idas las corta antes de la 10ª baza
		# Las idas se juegan enteras: 120 tantos de cartas + 10 de las diez últimas.
		var idas: Dictionary = resultado["manos"][0]
		assert_eq(idas["cartas"][0] + idas["cartas"][1], 120, "semilla %d" % semilla)
		assert_eq(idas["diez_ultimas"][0] + idas["diez_ultimas"][1], 10, "semilla %d" % semilla)
	assert_has(motivos, "tantos", "alguna partida termina en las idas")
	assert_has(motivos, "vuelta", "alguna partida necesita vuelta")


func test_en_arrastre_se_rechaza_una_carta_no_permitida() -> void:
	# Busca, en partidas al azar, un momento del arrastre en que la mano tenga
	# cartas que no se pueden jugar, e intenta jugar una de ellas.
	for semilla in 50:
		var rng := RandomNumberGenerator.new()
		rng.seed = semilla
		var motor := _motor(semilla)
		var e := motor.iniciar(4) as EstadoGuinote
		while not motor.ha_terminado(e):
			if e.siete_pendiente != -1:
				e = motor.aplicar_jugada(e, e.siete_pendiente, {"tipo": "no_cambiar_siete"}).estado
				continue
			var validas := motor.jugadas_validas(e, e.turno).filter(func(j: Dictionary) -> bool:
				return j["tipo"] == MensajesRed.JUGAR_CARTA)
			if e.fase == EstadoGuinote.Fase.ARRASTRE and validas.size() < e.manos[e.turno].size():
				var permitidas := validas.map(func(j: Dictionary) -> String: return j["carta_id"])
				for carta: Carta in e.manos[e.turno]:
					if carta.id not in permitidas:
						var resultado := motor.aplicar_jugada(e, e.turno, {"tipo": "jugar_carta", "carta_id": carta.id})
						assert_false(resultado.ok)
						assert_eq(resultado.error, MotorDeJuego.ERROR_JUGADA_NO_VALIDA)
						return
			e = motor.aplicar_jugada(e, e.turno, validas[rng.randi_range(0, validas.size() - 1)]).estado
	fail_test("ninguna de las 50 partidas tuvo una situación con cartas no permitidas")
