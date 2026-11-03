extends GutTest
## Motores de bazas con mazo: Guiñote a 2 y a 4 y Tute de 2. Partidas
## completas jugadas al azar con las jugadas que permite el motor, y casos
## concretos de las reglas que cambian entre juegos.

const PARTIDAS := 300


func _motor(juego: String, semilla: int) -> MotorGuinote:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return MotorTuteDos.new(rng) if juego == "tute" else MotorGuinote.new(rng)


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
