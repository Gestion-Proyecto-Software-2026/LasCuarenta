extends GutTest
## Motores de bazas con mazo: Guiñote a 2 y a 4 y Tute de 2. Partidas
## completas jugadas al azar con las jugadas que permite el motor, y casos
## concretos de las reglas que cambian entre juegos.

const PARTIDAS := 300


func _motor(juego: String, semilla: int) -> MotorGuinote:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	match juego:
		"tute":
			return MotorTuteDos.new(rng)
		"tute_parejas":
			return MotorTute.new(rng)
	return MotorGuinote.new(rng)


## Juega una partida entera eligiendo al azar entre las jugadas válidas. Si
## [param cantar] es true, canta y cambia la pinta siempre que puede.
func _jugar(juego: String, jugadores: int, semilla: int, cantar := true, capote := false) -> Dictionary:
	var motor := _motor(juego, semilla)
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla * 7 + 1
	var e: EstadoGuinote = motor.iniciar(jugadores)
	var rechazadas := 0
	var pasos := 0
	var sumas_mal := 0
	var mano_anterior := e.mano_actual
	while not motor.ha_terminado(e) and pasos < 500:
		pasos += 1
		var elegida := {}
		var quien := -1
		for j in jugadores:
			for jugada: Dictionary in motor.jugadas_validas(e, j):
				var tipo: String = jugada["tipo"]
				var apetece := (tipo == MotorDeJuego.CAPOTE and capote) \
					or (tipo != MotorDeJuego.CAPOTE and tipo != MotorDeJuego.JUGAR_CARTA and cantar) \
					or tipo == MotorDeJuego.NO_CAMBIAR_SIETE
				if apetece and elegida.is_empty():
					elegida = jugada
					quien = j
		if elegida.is_empty():
			var cartas := motor.jugadas_validas(e, e.turno).filter(func(j: Dictionary) -> bool:
				return j["tipo"] == MotorDeJuego.JUGAR_CARTA)
			if cartas.is_empty():
				return {"error": "nadie puede jugar", "pasos": pasos}
			elegida = cartas[rng.randi_range(0, cartas.size() - 1)]
			quien = e.turno
		var r := motor.aplicar_jugada(e, quien, elegida)
		if not r.ok:
			rechazadas += 1
			break
		var antes := e
		e = r.estado
		if e.mano_actual != mano_anterior:
			# Al empezar la vuelta, las idas tienen que cuadrar: 120 de cartas.
			if e.tanteo_idas["cartas"][0] + e.tanteo_idas["cartas"][1] != 120:
				sumas_mal += 1
			mano_anterior = e.mano_actual
		elif antes.bazas_jugadas != e.bazas_jugadas and e.bazas_jugadas == e.bazas_por_mano:
			var t := motor.tanteo_de_la_mano(e)
			if t["cartas"][0] + t["cartas"][1] != 120:
				sumas_mal += 1
	return {"estado": e, "motor": motor, "rechazadas": rechazadas, "pasos": pasos, "sumas_mal": sumas_mal}


func _comprobar_muchas(juego: String, jugadores: int, cantar := true, capote := false) -> Dictionary:
	var motivos := {}
	var errores := 0
	for semilla in PARTIDAS:
		var r := _jugar(juego, jugadores, semilla, cantar, capote)
		if r.has("error") or r["rechazadas"] > 0 or r["sumas_mal"] > 0 or not r["motor"].ha_terminado(r["estado"]):
			errores += 1
			gut.p("%s %d semilla %d: %s" % [juego, jugadores, semilla, r])
			continue
		var motivo: String = r["estado"].motivo_fin
		motivos[motivo] = motivos.get(motivo, 0) + 1
	gut.p("%s a %d: %s" % [juego, jugadores, motivos])
	assert_eq(errores, 0, "%s a %d: todas las partidas acaban sin errores" % [juego, jugadores])
	return motivos


func test_guinote_de_dos_partidas_completas() -> void:
	var motivos := _comprobar_muchas("guinote", 2)
	assert_true(motivos.has("tantos"), "Alguna partida se gana por tantos al acabar las idas")
	assert_true(motivos.has("vuelta"), "Alguna partida necesita vuelta")


func test_guinote_de_cuatro_partidas_completas() -> void:
	var motivos := _comprobar_muchas("guinote", 4)
	assert_true(motivos.has("tantos"))


func test_tute_de_dos_partidas_completas() -> void:
	var motivos := _comprobar_muchas("tute", 2)
	assert_false(motivos.has("tute"), "En el Tute de 2 no existe la jugada de Tute")
	assert_true(motivos.has("tantos"))


func test_tute_por_parejas_partidas_completas() -> void:
	var motivos := _comprobar_muchas("tute_parejas", 4)
	assert_true(motivos.has("tantos"))
	assert_false(motivos.has("vuelta"), "El Tute por parejas es a una sola mano")
	var sin_cantar := _comprobar_muchas("tute_parejas", 4, false)
	assert_eq(sin_cantar.keys(), ["tantos"], "Sin cantar no hay Tute: siempre por tantos")


func test_tute_por_parejas_reparto() -> void:
	var motor := _motor("tute_parejas", 4)
	var e: EstadoGuinote = motor.iniciar(4)
	for mano: Array in e.manos:
		assert_eq(mano.size(), 10)
	assert_eq(e.mazo.size(), 0, "Se reparten las 40")
	assert_eq(e.manos[e.dador].back(), e.pinta, "La pinta es la última carta del dador y se la queda")
	assert_eq(e.fase, EstadoGuinote.Fase.ARRASTRE, "Arrastre desde la primera baza")
	assert_eq(e.turno, (e.dador + 1) % 4, "Sale el de la derecha del dador")
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq([vista["pinta"], vista["cartas_en_mazo"]], [e.pinta, 1], "La mesa enseña la pinta en la esquina")


## Tute por parejas, triunfo oros, la pareja 0-2 ganó la última baza.
func _estado_tute_parejas() -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.manos = [
		["Rey_oros", "Caballo_oros", "Rey_copas", "Caballo_copas"] as Array[String],
		["As_espadas"] as Array[String],
		["Rey_bastos", "Caballo_bastos", "Siete_oros"] as Array[String],
		["As_bastos"] as Array[String],
	]
	e.pinta = "Dos_oros"
	e.palo_triunfo = 0
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_con_robo = 0
	e.bazas_jugadas = 3
	e.ultima_baza = {"ganador": 0, "cartas": []}
	e.turno = 0
	return e


func test_tute_por_parejas_cantes() -> void:
	var motor := MotorTute.new()
	var e := _estado_tute_parejas()
	var cantes := motor.jugadas_validas(e, 0).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.CANTAR)
	assert_eq(cantes[0], {"tipo": MotorDeJuego.CANTAR, "palo": "oros"}, "Primero las 40, como el botón de siempre")
	assert_eq(cantes.size(), 2)
	# Sale el jugador 0 y echa el rival 1: el compañero (2), que aún no ha echado, puede cantar.
	e.manos[0].erase("Rey_copas")
	e.baza_actual = [{"jugador_id": 0, "carta": "Rey_copas"}, {"jugador_id": 1, "carta": "As_espadas"}]
	e.turno = 2
	assert_eq(motor.jugadas_validas(e, 0).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.CANTAR), [],
		"Quien ya ha echado carta en esta baza no canta")
	assert_has(motor.jugadas_validas(e, 2), {"tipo": MotorDeJuego.CANTAR, "palo": "bastos"},
		"El compañero canta aunque ya haya jugado un rival")
	assert_eq(motor.jugadas_validas(e, 1), [], "La pareja rival no canta")


func test_tute_por_parejas_sin_cambio_de_pinta() -> void:
	var motor := MotorTute.new()
	var e := _estado_tute_parejas()
	assert_false(motor.puede_cambiar_siete(e, 2), "El jugador 2 tiene el 7 de triunfo, pero en el Tute no se cambia")


func test_tute_por_parejas_explica_con_reglas_tute() -> void:
	var motor := MotorTute.new()
	var e := _estado_tute_parejas()
	e.baza_actual = [{"jugador_id": 3, "carta": "Cuatro_espadas"}, {"jugador_id": 0, "carta": "Dos_oros"}]
	e.manos[1] = ["Tres_oros", "As_copas"] as Array[String]
	e.turno = 1
	assert_eq(motor.motivo_carta_no_valida(e, 1, "As_copas"),
		"Tienes que pisar: echa un triunfo más alto que el Dos de oros.")


func test_tute_de_dos_con_capote_siempre() -> void:
	var motivos := _comprobar_muchas("tute", 2, true, true)
	assert_true(motivos.has("capote"), "Si siempre se anuncia, alguna partida acaba por capote")


func test_guinote_sin_cantar_suma_lo_justo() -> void:
	for semilla in 50:
		var r := _jugar("guinote", 2, semilla, false)
		var e: EstadoGuinote = r["estado"]
		assert_true(e.cantes.is_empty(), "Sin pulsar cantar no hay cantes")


func test_bazas_de_cada_variante() -> void:
	var e2: EstadoGuinote = _motor("guinote", 1).iniciar(2)
	assert_eq([e2.bazas_con_robo, e2.bazas_por_mano, e2.manos[0].size(), e2.mazo.size()], [14, 20, 6, 27])
	var e4: EstadoGuinote = _motor("guinote", 1).iniciar(4)
	assert_eq([e4.bazas_con_robo, e4.bazas_por_mano, e4.manos[0].size(), e4.mazo.size()], [4, 10, 6, 15])
	var t2: EstadoGuinote = _motor("tute", 1).iniciar(2)
	assert_eq([t2.bazas_con_robo, t2.bazas_por_mano, t2.manos[0].size(), t2.mazo.size()], [12, 20, 8, 23])


func test_tute_de_dos_no_admite_cuatro() -> void:
	assert_eq(MotorTuteDos.new().jugadores_admitidos(), [2] as Array[int])


## Estado de Tute de 2 hecho a mano: triunfo oros, el jugador 0 acaba de ganar una baza.
func _estado_tute(mano0: Array[String], mano1: Array[String], pinta := "Rey_oros") -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 2
	e.manos = [mano0, mano1]
	e.pinta = pinta
	e.palo_triunfo = Cartas.palo(pinta)
	var mazo: Array[String] = ["Cuatro_copas", "Cinco_copas"]
	e.mazo = mazo
	e.bazas_con_robo = 12
	e.bazas_por_mano = 20
	e.bazas_jugadas = 1
	e.ultimo_cante_de.assign([-1, -1])
	e.ultima_baza = {"ganador": 0, "cartas": [{"jugador_id": 1, "carta": "Dos_espadas"}, {"jugador_id": 0, "carta": "Tres_espadas"}]}
	e.turno = 0
	return e


## Guiñote de 2 en arrastre, triunfo oros, sale el jugador 0 y le toca al 1.
func _arrastre(mano1: Array[String], salida: String) -> EstadoGuinote:
	var e := _estado_tute(["Siete_bastos"], mano1, "Rey_oros")
	e.pinta = ""
	e.mazo.clear()
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_con_robo = 14
	e.baza_actual = [{"jugador_id": 0, "carta": salida}]
	e.turno = 1
	return e


func test_motivo_de_carta_no_valida() -> void:
	var motor := MotorGuinote.new()
	var e := _arrastre(["Dos_copas", "As_copas", "Rey_espadas"], "Cuatro_copas")
	assert_eq(motor.motivo_carta_no_valida(e, 0, "Siete_bastos"), "Espera tu turno.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "Rey_espadas"), "Tienes que asistir: echa una carta de copas.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "Dos_copas"),
		"Tienes que montar: echa una carta de copas más alta que el Cuatro de copas.")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "As_copas"), "", "El As monta: vale")
	assert_eq(motor.motivo_carta_no_valida(e, 1, "Tres_copas"), "No tienes esa carta.")
	var sin_copas := _arrastre(["Dos_oros", "Rey_bastos"], "Cuatro_copas")
	assert_eq(motor.motivo_carta_no_valida(sin_copas, 1, "Rey_bastos"),
		"No tienes copas: tienes que fallar con un triunfo (oros).")


func test_motivo_en_el_tute_de_dos_con_mazo() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["As_copas"], ["Dos_oros", "As_copas"])
	e.baza_actual = [{"jugador_id": 0, "carta": "Cuatro_oros"}]
	e.turno = 1
	assert_eq(motor.motivo_carta_no_valida(e, 1, "As_copas"), "Tienes que asistir: echa una carta de oros.",
		"Sale triunfo con mazo: hay que echar triunfo")


func test_tute_de_dos_se_canta_con_rey_y_caballo() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["Rey_copas", "Caballo_copas", "Rey_bastos", "Sota_bastos"], ["As_oros"])
	var cantes := motor.jugadas_validas(e, 0).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.CANTAR)
	assert_eq(cantes, [{"tipo": MotorDeJuego.CANTAR, "palo": "copas"}], "Copas sí (Rey+Caballo), bastos no (Rey+Sota)")


func test_tute_de_dos_cuatro_reyes_no_es_tute() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["Rey_copas", "Rey_espadas", "Rey_bastos", "Rey_oros"], ["As_oros"], "Tres_oros")
	var tutes := motor.jugadas_validas(e, 0).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.CANTAR_TUTE)
	assert_eq(tutes, [])


func test_guinote_cuatro_reyes_es_tute() -> void:
	var motor := MotorGuinote.new()
	var e := _estado_tute(["Rey_copas", "Rey_espadas", "Rey_bastos", "Rey_oros"], ["As_oros"], "Tres_oros")
	var tutes := motor.jugadas_validas(e, 0).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.CANTAR_TUTE)
	assert_eq(tutes, [{"tipo": MotorDeJuego.CANTAR_TUTE, "figura": "reyes"}])


func test_tute_de_dos_con_mazo_hay_que_asistir_a_triunfo() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["As_copas"], ["Dos_oros", "As_copas", "Rey_bastos"])
	e.baza_actual = [{"jugador_id": 0, "carta": "Cuatro_oros"}]
	e.turno = 1
	var cartas := motor.jugadas_validas(e, 1).filter(func(j: Dictionary) -> bool: return j["tipo"] == MotorDeJuego.JUGAR_CARTA)
	assert_eq(cartas, [{"tipo": MotorDeJuego.JUGAR_CARTA, "carta_id": "Dos_oros"}], "Sale triunfo: hay que echar triunfo, aunque no monte")


func test_tute_de_dos_con_mazo_otro_palo_es_libre() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["As_copas"], ["Dos_oros", "As_copas", "Rey_bastos"])
	e.baza_actual = [{"jugador_id": 0, "carta": "Cuatro_espadas"}]
	e.turno = 1
	assert_eq(motor.jugadas_validas(e, 1).size(), 3, "Sale espadas: puede echar cualquiera")


func test_tute_de_dos_cambio_de_pinta() -> void:
	var motor := MotorTuteDos.new()
	assert_eq(motor.carta_de_cambio("Rey_oros"), Cartas.SIETE)
	assert_eq(motor.carta_de_cambio("As_oros"), Cartas.SIETE)
	assert_eq(motor.carta_de_cambio("Cinco_oros"), Cartas.DOS)
	assert_eq(motor.carta_de_cambio("Siete_oros"), Cartas.DOS)
	assert_eq(motor.carta_de_cambio("Dos_oros"), -1)
	var e := _estado_tute(["Dos_copas", "Siete_copas"], ["As_oros"], "Cinco_copas")
	var r := motor.aplicar_jugada(e, 0, {"tipo": MotorDeJuego.CAMBIAR_SIETE})
	assert_true(r.ok, "Con la pinta blanca se cambia por el 2")
	assert_eq((r.estado as EstadoGuinote).pinta, "Dos_copas")
	assert_true("Cinco_copas" in (r.estado as EstadoGuinote).manos[0])


func test_tute_de_dos_cambio_solo_tras_ganar_baza() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["Siete_oros", "As_copas"], ["As_oros", "Dos_copas"])
	e.baza_actual = [{"jugador_id": 0, "carta": "Cuatro_espadas"}]
	e.turno = 1
	assert_true(motor.puede_cambiar_siete(e, 0), "Aún no ha jugado el rival: puede cambiar")
	e.baza_actual.append({"jugador_id": 1, "carta": "Dos_copas"})
	assert_false(motor.puede_cambiar_siete(e, 0), "Ya ha jugado el rival: no")


func test_capote_fallado_lo_gana_el_rival() -> void:
	var motor := MotorTuteDos.new()
	var e := _estado_tute(["Dos_copas"], ["As_copas"])
	e.mazo.clear()
	e.pinta = ""
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.bazas_jugadas = 12
	e.capote = 0
	e.baza_actual = [{"jugador_id": 0, "carta": "Cuatro_copas"}]
	e.turno = 1
	var r := motor.aplicar_jugada(e, 1, {"tipo": MotorDeJuego.JUGAR_CARTA, "carta_id": "As_copas"})
	assert_true(r.ok)
	assert_eq((r.estado as EstadoGuinote).equipo_ganador, 1)
	assert_eq((r.estado as EstadoGuinote).motivo_fin, "capote")


func test_vista_no_ensena_la_mano_del_rival() -> void:
	var motor := _motor("guinote", 3)
	var e: EstadoGuinote = motor.iniciar(2)
	var vista := motor.vista_para_jugador(e, 0)
	assert_eq(vista["mi_mano"], e.manos[0])
	assert_eq(vista["cartas_por_jugador"], [6, 6] as Array[int])
	for carta: String in e.manos[1]:
		assert_false(str(vista).contains('"%s"' % carta), "La carta %s del rival no aparece en la vista" % carta)
