extends GutTest
## Reglas propias del Tute (§10) a 2 y a 4 jugadores, y los motivos que da el
## servidor cuando rechaza una carta. Las partidas completas por red están en
## tests/integration/test_partida_tute.gd.


static func _c(id: String) -> Carta:
	return Carta.desde_id(id)


static func _mano(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(_c(id))
	return cartas


static func _ids(cartas: Array) -> Array:
	return cartas.map(func(c: Carta) -> String: return c.id)


static func _de_tipo(jugadas: Array, tipo: String) -> Array:
	return jugadas.filter(func(j: Dictionary) -> bool: return j["tipo"] == tipo)


func _motor_semilla(clase: GDScript, semilla: int) -> MotorDeJuego:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return clase.new(rng)


# --- El motor "tute" que elige variante ---

func test_tute_admite_dos_y_cuatro_y_elige_la_variante() -> void:
	var motor := MotorTute.new()
	assert_eq(motor.jugadores_admitidos(), [2, 4] as Array[int])
	var a_dos := motor.iniciar(2) as EstadoGuinote
	var a_cuatro := motor.iniciar(4) as EstadoGuinote
	assert_eq(a_dos.manos[0].size(), 8, "A 2 se reparten 8 cartas")
	assert_eq(a_cuatro.manos[0].size(), 10, "A 4 se reparten 10 cartas")


# --- Tute de 2 ---

func test_tute_de_dos_reparto() -> void:
	var motor := _motor_semilla(MotorTuteDos, 1) as MotorTuteDos
	var e := motor.iniciar(2) as EstadoGuinote
	assert_eq([e.manos[0].size(), e.manos[1].size(), e.mazo.size()], [8, 8, 23])
	assert_eq([motor.bazas_con_robo(e), motor.bazas_por_mano(e)], [12, 20])
	assert_eq(e.fase, EstadoGuinote.Fase.ROBO)


## Tute de 2 hecho a mano: triunfo según [param pinta], el jugador 0 acaba de
## ganar una baza y queda mazo.
func _estado_dos(mano0: Array, mano1: Array, pinta := "oros_12") -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 2
	e.manos = [_mano(mano0), _mano(mano1)]
	e.pinta = _c(pinta)
	e.palo_triunfo = e.pinta.palo
	e.mazo = _mano(["copas_4", "copas_5"])
	e.bazas_jugadas = 1
	e.ultimo_cante_de = [-1, -1] as Array[int]
	e.ultima_baza = {"ganador": 0, "cartas": [
		{"jugador_id": 1, "carta": _c("espadas_2")}, {"jugador_id": 0, "carta": _c("espadas_3")}]}
	e.turno = 0
	return e


func test_tute_de_dos_con_mazo_hay_que_echar_triunfo_si_sale_triunfo() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["copas_1"], ["oros_2", "copas_1", "bastos_12"])
	e.baza_actual = [{"jugador_id": 0, "carta": _c("oros_4")}]
	e.turno = 1
	var cartas := _de_tipo(motor.jugadas_validas(e, 1), MensajesRed.JUGAR_CARTA)
	assert_eq(cartas, [{"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "oros_2"}],
		"Sale triunfo: hay que echar triunfo, aunque no monte")
	assert_eq(motor.explicar_rechazo(e, 1, {"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "copas_1"}),
		"Ha salido triunfo: tienes que echar un triunfo (oros).")


func test_tute_de_dos_con_mazo_otro_palo_es_libre() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["copas_1"], ["oros_2", "copas_1", "bastos_12"])
	e.baza_actual = [{"jugador_id": 0, "carta": _c("espadas_4")}]
	e.turno = 1
	assert_eq(_de_tipo(motor.jugadas_validas(e, 1), MensajesRed.JUGAR_CARTA).size(), 3,
		"Sale espadas: puede echar cualquiera")


func test_tute_de_dos_se_canta_con_rey_y_caballo_y_no_hay_tute() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["copas_12", "copas_11", "bastos_12", "bastos_10"], ["oros_1"])
	assert_eq(_de_tipo(motor.jugadas_validas(e, 0), MensajesRed.CANTAR),
		[{"tipo": MensajesRed.CANTAR, "palo": "copas"}], "Copas sí (Rey y Caballo), bastos no (Rey y Sota)")
	var reyes := _estado_dos(["copas_12", "espadas_12", "bastos_12", "oros_12"], ["oros_1"], "oros_3")
	assert_eq(_de_tipo(motor.jugadas_validas(reyes, 0), MensajesRed.CANTAR_TUTE), [],
		"En el Tute de 2 los cuatro reyes no son Tute")
	assert_eq(_de_tipo(MotorGuinote.new().jugadas_validas(reyes, 0), MensajesRed.CANTAR_TUTE),
		[{"tipo": MensajesRed.CANTAR_TUTE, "figura": "reyes"}], "En el Guiñote, sí")


func test_tute_de_dos_cambio_de_pinta() -> void:
	var motor := MotorTuteDos.new()
	assert_eq(motor.carta_de_cambio(_c("oros_12")), MotorGuinote.SIETE, "Pinta figura: por el 7")
	assert_eq(motor.carta_de_cambio(_c("oros_1")), MotorGuinote.SIETE, "Pinta As: por el 7")
	assert_eq(motor.carta_de_cambio(_c("oros_5")), MotorGuinote.DOS, "Pinta blanca: por el 2")
	assert_eq(motor.carta_de_cambio(_c("oros_7")), MotorGuinote.DOS, "El 7 también es blanca")
	assert_eq(motor.carta_de_cambio(_c("oros_2")), -1, "El 2 no se cambia")
	var e := _estado_dos(["copas_2", "copas_7"], ["oros_1"], "copas_5")
	var r := motor.aplicar_jugada(e, 0, {"tipo": MensajesRed.CAMBIAR_SIETE})
	assert_true(r.ok, "Con la pinta blanca se cambia por el 2")
	var nuevo := r.estado as EstadoGuinote
	assert_eq(nuevo.pinta.id, "copas_2")
	assert_has(_ids(nuevo.manos[0]), "copas_5")


func test_tute_de_dos_cambio_solo_tras_ganar_la_baza() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["oros_7", "copas_1"], ["oros_1", "copas_2"])
	e.baza_actual = [{"jugador_id": 0, "carta": _c("espadas_4")}]
	e.turno = 1
	assert_has(motor.jugadas_validas(e, 0), {"tipo": MensajesRed.CAMBIAR_SIETE},
		"Aún no ha jugado el rival: puede cambiar")
	e.baza_actual.append({"jugador_id": 1, "carta": _c("copas_2")})
	assert_does_not_have(motor.jugadas_validas(e, 0), {"tipo": MensajesRed.CAMBIAR_SIETE},
		"Ya ha jugado el rival: no")


func test_tute_de_dos_capote_fallado_lo_gana_el_rival() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["copas_2"], ["copas_1"])
	e.mazo.clear()
	e.pinta = null
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_jugadas = 12
	e.capote = 0
	e.baza_actual = [{"jugador_id": 0, "carta": _c("copas_4")}]
	e.turno = 1
	var r := motor.aplicar_jugada(e, 1, {"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "copas_1"})
	assert_true(r.ok)
	assert_eq((r.estado as EstadoGuinote).equipo_ganador, 1)
	assert_eq((r.estado as EstadoGuinote).motivo_fin, "capote")


func test_tute_de_dos_el_capote_se_anuncia_al_acabarse_el_mazo() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_dos(["copas_2"], ["copas_1"])
	e.mazo.clear()
	e.pinta = null
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_jugadas = 12
	assert_has(motor.jugadas_validas(e, 0), {"tipo": MensajesRed.CAPOTE})
	assert_has(motor.jugadas_validas(e, 1), {"tipo": MensajesRed.CAPOTE}, "Cualquiera de los dos")
	e.bazas_jugadas = 11
	e.fase = EstadoGuinote.Fase.ROBO
	assert_does_not_have(motor.jugadas_validas(e, 0), {"tipo": MensajesRed.CAPOTE}, "Con mazo, no")


func test_tute_de_dos_sin_minimo_de_treinta() -> void:
	var motor := MotorTuteDos.new()
	var tanteo := {"cartas": [20, 80], "total": [105, 110]}
	assert_eq(motor.decidir_fin_de_idas(tanteo, 0), 1, "Pasan los dos: gana quien más tiene")
	assert_eq(motor.decidir_fin_de_idas({"cartas": [20, 80], "total": [105, 90]}, 1), 0,
		"Sin el mínimo de 30 de cartas del Guiñote")


# --- Tute por parejas ---

func test_tute_por_parejas_reparto() -> void:
	var motor := _motor_semilla(MotorTuteParejas, 4) as MotorTuteParejas
	var e := motor.iniciar(4) as EstadoGuinote
	for mano: Array in e.manos:
		assert_eq(mano.size(), 10)
	assert_eq(e.mazo.size(), 0, "Se reparten las 40")
	assert_true(e.manos[e.dador].back().es_igual(e.pinta), "La pinta es la última carta del dador y se la queda")
	assert_eq(e.fase, EstadoGuinote.Fase.ARRASTRE, "Arrastre desde la primera baza")
	assert_eq(e.turno, (e.dador + 1) % 4, "Sale el de la derecha del dador")
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq([vista["pinta"], vista["cartas_en_mazo"]], [e.pinta.id, 1], "La mesa enseña la pinta en la esquina")


## Tute por parejas, triunfo oros, la pareja 0-2 ganó la última baza.
func _estado_parejas() -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.manos = [
		_mano(["oros_12", "oros_11", "copas_12", "copas_11"]),
		_mano(["espadas_1"]),
		_mano(["bastos_12", "bastos_11", "oros_7"]),
		_mano(["bastos_1"]),
	]
	e.pinta = _c("oros_2")
	e.palo_triunfo = Carta.Palo.OROS
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_jugadas = 3
	e.ultima_baza = {"ganador": 0, "cartas": []}
	e.turno = 0
	return e


func test_tute_por_parejas_cantes() -> void:
	var motor := MotorTuteParejas.new()
	var e := _estado_parejas()
	var cantes := _de_tipo(motor.jugadas_validas(e, 0), MensajesRed.CANTAR)
	assert_eq(cantes[0], {"tipo": MensajesRed.CANTAR, "palo": "oros"}, "Primero las 40")
	assert_eq(cantes.size(), 2)
	# Sale el 0 y echa el rival 1: el compañero (2), que aún no ha echado, puede cantar.
	e.manos[0].remove_at(2)
	e.baza_actual = [{"jugador_id": 0, "carta": _c("copas_12")}, {"jugador_id": 1, "carta": _c("espadas_1")}]
	e.turno = 2
	assert_eq(_de_tipo(motor.jugadas_validas(e, 0), MensajesRed.CANTAR), [],
		"Quien ya ha echado carta en esta baza no canta")
	assert_has(motor.jugadas_validas(e, 2), {"tipo": MensajesRed.CANTAR, "palo": "bastos"},
		"El compañero canta aunque ya haya jugado un rival")
	assert_eq(motor.jugadas_validas(e, 1), [] as Array[Dictionary], "La pareja rival no canta")


func test_tute_por_parejas_sin_cambio_de_pinta() -> void:
	var motor := MotorTuteParejas.new()
	var e := _estado_parejas()
	assert_does_not_have(motor.jugadas_validas(e, 2), {"tipo": MensajesRed.CAMBIAR_SIETE},
		"El jugador 2 tiene el 7 de triunfo, pero en el Tute por parejas no se cambia")


func test_tute_por_parejas_montar_tambien_sobre_el_companero() -> void:
	var motor := MotorTuteParejas.new()
	var e := _estado_parejas()
	e.manos[2] = _mano(["copas_4", "copas_1", "bastos_12"])
	e.baza_actual = [{"jugador_id": 0, "carta": _c("copas_3")}, {"jugador_id": 1, "carta": _c("copas_2")}]
	e.turno = 2
	assert_eq(_ids(motor.permitidas_en_arrastre(e.manos[2], e.baza_actual, e.palo_triunfo, 2)), ["copas_1"],
		"Va ganando su compañero con el 3, y aun así tiene que montar con el As")


func test_tute_por_parejas_pisar_y_contrafallo() -> void:
	var motor := MotorTuteParejas.new()
	var e := _estado_parejas()
	e.baza_actual = [{"jugador_id": 3, "carta": _c("espadas_4")}, {"jugador_id": 0, "carta": _c("oros_4")}]
	e.manos[1] = _mano(["oros_3", "copas_1"])
	e.turno = 1
	assert_eq(_ids(motor.permitidas_en_arrastre(e.manos[1], e.baza_actual, e.palo_triunfo, 1)), ["oros_3"],
		"Sin espadas, tiene que pisar el 4 de oros con el 3")
	assert_eq(motor.explicar_rechazo(e, 1, {"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "copas_1"}),
		"Tienes que pisar: echa un triunfo más alto que el Cuatro de oros.")
	e.manos[1] = _mano(["oros_2", "copas_1"])
	assert_eq(_ids(motor.permitidas_en_arrastre(e.manos[1], e.baza_actual, e.palo_triunfo, 1)), ["oros_2", "copas_1"],
		"Si no puede pisar, contrafallo: cualquier carta")


func test_tute_por_parejas_una_sola_mano() -> void:
	var motor := MotorTuteParejas.new()
	assert_eq(motor.decidir_fin_de_idas({"cartas": [70, 50], "total": [80, 60]}, 1), 0,
		"Gana quien más tiene, aunque no pase de 100")
	assert_eq(motor.decidir_fin_de_idas({"cartas": [60, 60], "total": [70, 70]}, 1), 1,
		"Empate: la pareja de la última baza")


# --- Motivos del Guiñote ---

## Guiñote de 2 en arrastre, triunfo oros, sale el jugador 0 y le toca al 1.
func _arrastre_guinote(mano1: Array, salida: String) -> EstadoGuinote:
	var e := _estado_dos(["bastos_7"], mano1)
	e.pinta = null
	e.mazo.clear()
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_jugadas = 15
	e.baza_actual = [{"jugador_id": 0, "carta": _c(salida)}]
	e.turno = 1
	return e


func test_motivos_de_carta_no_valida_en_el_guinote() -> void:
	var motor := MotorGuinote.new()
	var e := _arrastre_guinote(["copas_2", "copas_1", "espadas_12"], "copas_4")
	assert_eq(motor.motivo_carta_no_valida(e, 0, "bastos_7"), "Espera tu turno.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "espadas_12"), "Tienes que asistir: echa una carta de copas.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "copas_2"),
		"Tienes que montar: echa una carta de copas más alta que el Cuatro de copas.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "copas_1"), "", "El As monta: vale")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "copas_3"), "No tienes esa carta.")
	var sin_copas := _arrastre_guinote(["oros_2", "bastos_12"], "copas_4")
	assert_eq(motor.motivo_carta_no_valida(sin_copas, 1, "bastos_12"),
		"No tienes copas: tienes que fallar con un triunfo (oros).")


func test_cantar_o_cambiar_la_pinta_fuera_de_plazo_tambien_se_explica() -> void:
	# No van por turno, así que se puede llegar tarde si otro juega a la vez.
	var motor := MotorGuinote.new()
	var e := _arrastre_guinote(["copas_2", "copas_1", "espadas_12"], "copas_4")
	assert_eq(motor.explicar_rechazo(e, 1, {"tipo": MensajesRed.CANTAR, "palo": "copas"}),
		"Ya no se puede cantar: solo justo después de ganar una baza, antes de que juegue un rival.")
	assert_eq(motor.explicar_rechazo(e, 1, {"tipo": MensajesRed.CAMBIAR_SIETE}), "Ya no se puede cambiar la pinta.")
	assert_eq(motor.explicar_rechazo(e, 1, {"tipo": "bailar"}), "", "lo que no conoce, error genérico")


func test_el_error_del_motor_sigue_siendo_el_generico() -> void:
	var motor := MotorGuinote.new()
	var e := _arrastre_guinote(["copas_2", "copas_1", "espadas_12"], "copas_4")
	var r := motor.aplicar_jugada(e, 1, {"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "espadas_12"})
	assert_false(r.ok)
	assert_eq(r.error, MotorDeJuego.ERROR_JUGADA_NO_VALIDA, "El motivo concreto lo da explicar_rechazo")
