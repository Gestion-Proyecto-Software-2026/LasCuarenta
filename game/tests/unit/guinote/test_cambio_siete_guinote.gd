extends GutTest
## Cambio del 7 de triunfo por la pinta en Guiñote (analisis_funcional_app.md §8).
## Copia de game/tests/unit/server/game_engine/guinote/ (Carlos), adaptada al prototipo: cartas como ids de texto.
## Estados construidos a mano: triunfo oros, pinta el As de oros.

const CAMBIAR := {"tipo": "cambiar_siete"}
const NO_CAMBIAR := {"tipo": "no_cambiar_siete"}

var motor: MotorGuinote


func before_each() -> void:
	motor = MotorGuinote.new()


func _cartas(ids: Array) -> Array[String]:
	var cartas: Array[String] = []
	for id: String in ids:
		cartas.append(id)
	return cartas


func _ids(cartas: Array) -> Array[String]:
	return _ids_de(cartas)


func _aplicar(e: EstadoGuinote, jugador_id: int, jugada: Dictionary) -> EstadoGuinote:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, resultado.error)
	return resultado.estado


## Fase de robo, tras la 2ª baza, que ganó [param ganador].
func _estado_en_robo(manos: Array, ganador: int) -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.palo_triunfo = 0
	e.pinta = "As_oros"
	e.mazo = _cartas(["Dos_bastos", "Cuatro_bastos", "Cinco_bastos", "Seis_bastos", "Siete_bastos", "Dos_espadas", "Cuatro_espadas"])
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
	e.bazas_jugadas = 2
	e.ultima_baza = {"ganador": ganador, "cartas": [] as Array[Dictionary]}
	e.turno = ganador
	return e


const MANOS := [
	["Siete_oros", "Dos_copas", "Cuatro_copas", "Cinco_espadas", "Seis_espadas", "As_bastos"],
	["Cinco_copas", "Seis_copas", "Siete_espadas", "Tres_bastos", "Sota_bastos", "Caballo_bastos"],
	["Siete_copas", "As_copas", "As_espadas", "Tres_espadas", "Rey_bastos", "Dos_oros"],
	["Tres_copas", "Tres_oros", "Cuatro_oros", "Sota_espadas", "Caballo_espadas", "Rey_espadas"],
]


# --- Tras las bazas 1 a 3: cuando se quiera, sin parar la partida ---

func test_tras_ganar_baza_quien_tiene_el_siete_puede_cambiarlo() -> void:
	var e := _estado_en_robo(MANOS, 0)
	assert_has(motor.jugadas_validas(e, 0), CAMBIAR)
	e = _aplicar(e, 0, CAMBIAR)
	assert_has(_ids(e.manos[0]), "As_oros", "se queda la pinta")
	assert_does_not_have(_ids(e.manos[0]), "Siete_oros")
	assert_eq(e.pinta, "Siete_oros", "el 7 pasa a ser la pinta y se robará el último")
	assert_eq(e.turno, 0)
	assert_eq(e.mazo.size(), 7, "cambiar no roba")


func test_tambien_puede_su_companero_fuera_de_turno() -> void:
	var manos := MANOS.duplicate(true)
	manos[0][0] = "Cinco_oros"
	manos[2][5] = "Siete_oros"
	assert_has(motor.jugadas_validas(_estado_en_robo(manos, 0), 2), CAMBIAR)


func test_no_puede_la_pareja_que_no_gano_la_baza_ni_nadie_antes_de_la_primera() -> void:
	var manos := MANOS.duplicate(true)
	manos[0][0] = "Cinco_oros"
	manos[1][0] = "Siete_oros"
	assert_does_not_have(motor.jugadas_validas(_estado_en_robo(manos, 0), 1), CAMBIAR)
	var nueva := MotorGuinote.new().iniciar(4) as EstadoGuinote
	for jugador in 4:
		assert_does_not_have(motor.jugadas_validas(nueva, jugador), CAMBIAR)


func test_el_derecho_dura_hasta_que_se_cierra_la_baza_siguiente() -> void:
	var e := _estado_en_robo(MANOS, 0)
	e.baza_actual = [
		{"jugador_id": 0, "carta": "Dos_copas"},
		{"jugador_id": 1, "carta": "Cinco_copas"},
	] as Array[Dictionary]
	assert_true(MotorGuinote.new().puede_cambiar_siete(e, 0), "aunque un rival ya haya jugado (a diferencia del cante)")
	e.ultima_baza["ganador"] = 1
	assert_false(MotorGuinote.new().puede_cambiar_siete(e, 0), "la última baza ya es de los rivales")


# --- Tras la 4ª baza: el último robo espera la decisión ---

## Baza 4 a punto de cerrarse: el 0 gana con el As de copas cuando juegue el 3.
func _antes_de_cerrar_la_cuarta(quien_tiene_el_siete: int) -> EstadoGuinote:
	var manos := [
		["Rey_copas", "Cinco_espadas", "Seis_espadas", "As_bastos", "Tres_bastos"],
		["Seis_copas", "Siete_espadas", "Sota_bastos", "Caballo_bastos", "As_espadas"],
		["Siete_copas", "Tres_espadas", "Rey_bastos", "Dos_oros", "Rey_espadas"],
		["Cinco_copas", "Tres_oros", "Cuatro_oros", "Sota_espadas", "Caballo_espadas", "Tres_copas"],
	]
	manos[quien_tiene_el_siete][0] = "Siete_oros"
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.palo_triunfo = 0
	e.pinta = "As_oros"
	e.mazo = _cartas(["Dos_bastos", "Cuatro_bastos", "Cinco_bastos"])
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
	e.bazas_jugadas = 3
	e.ultima_baza = {"ganador": 3, "cartas": [] as Array[Dictionary]}
	e.baza_actual = [
		{"jugador_id": 0, "carta": "As_copas"},
		{"jugador_id": 1, "carta": "Dos_copas"},
		{"jugador_id": 2, "carta": "Cuatro_copas"},
	] as Array[Dictionary]
	e.turno = 3
	return _aplicar(e, 3, {"tipo": "jugar_carta", "carta_id": "Cinco_copas"})


func test_tras_la_cuarta_baza_el_robo_espera_si_la_pareja_ganadora_tiene_el_siete() -> void:
	var e := _antes_de_cerrar_la_cuarta(2)
	assert_eq(e.ultima_baza["ganador"], 0)
	assert_eq(e.siete_pendiente, 2)
	assert_eq(e.pinta, "As_oros")
	assert_eq(e.mazo.size(), 3, "todavía no ha robado nadie")
	assert_eq(motor.jugadas_validas(e, 2), [CAMBIAR, NO_CAMBIAR] as Array[Dictionary])
	assert_eq(motor.jugadas_validas(e, 0), [] as Array[Dictionary], "no se sale hasta que se decida")
	assert_eq(motor.jugadas_validas(e, 1), [] as Array[Dictionary])
	assert_eq(motor.vista_para_jugador(e, 1)["esperando_cambio_siete"], 2)


func test_si_cambia_el_siete_lo_roba_el_ultimo_rival() -> void:
	var e := _aplicar(_antes_de_cerrar_la_cuarta(2), 2, CAMBIAR)
	assert_has(_ids(e.manos[2]), "As_oros")
	assert_has(_ids(e.manos[3]), "Siete_oros", "la pinta (ya el 7) la roba el último, un rival")
	_assert_robo_terminado(e)


func test_si_no_cambia_se_roba_como_siempre() -> void:
	var e := _aplicar(_antes_de_cerrar_la_cuarta(2), 2, NO_CAMBIAR)
	assert_has(_ids(e.manos[2]), "Siete_oros")
	assert_has(_ids(e.manos[3]), "As_oros")
	_assert_robo_terminado(e)


func test_si_el_siete_lo_tiene_la_pareja_que_pierde_no_se_espera() -> void:
	var e := _antes_de_cerrar_la_cuarta(1)
	assert_eq(e.siete_pendiente, -1)
	assert_has(_ids(e.manos[3]), "As_oros")
	_assert_robo_terminado(e)


func _assert_robo_terminado(e: EstadoGuinote) -> void:
	assert_eq(e.siete_pendiente, -1)
	assert_eq(e.fase, EstadoGuinote.Fase.ARRASTRE)
	assert_true(e.mazo.is_empty())
	assert_eq(e.pinta, "")
	for mano: Array in e.manos:
		assert_eq(mano.size(), 6)
	assert_eq(e.turno, 0, "sale quien ganó la 4ª baza")
	assert_false(motor.jugadas_validas(e, 0).is_empty())


## Las cartas ya son ids de texto: solo hace falta una copia tipada.
func _ids_de(cartas: Array) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(cartas)
	return ids
