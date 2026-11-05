extends GutTest
## Cantes (veinte y las cuarenta) y Tute en Guiñote (analisis_funcional_app.md §8).
## Copia de game/tests/unit/server/game_engine/guinote/ (Carlos), adaptada al prototipo: cartas como ids de texto.
## Los estados se construyen a mano: triunfo oros, en fase de arrastre.

var motor: MotorGuinote


func before_each() -> void:
	motor = MotorGuinote.new()


func _cartas(ids: Array) -> Array[String]:
	var cartas: Array[String] = []
	for id: String in ids:
		cartas.append(id)
	return cartas


## Estado tras una baza que ganó [param ganador], que sale en la siguiente.
func _estado(manos: Array, ganador: int) -> EstadoGuinote:
	var e := EstadoGuinote.new()
	e.num_jugadores = 4
	e.palo_triunfo = 0
	e.fase = EstadoGuinote.Fase.ARRASTRE
	for ids: Array in manos:
		e.manos.append(_cartas(ids))
	e.bazas_jugadas = 5
	e.ultima_baza = {"ganador": ganador, "cartas": [] as Array[Dictionary]}
	e.turno = ganador
	return e


func _cantes(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	return motor.jugadas_validas(e, jugador_id).filter(func(j: Dictionary) -> bool:
		return j["tipo"] in [MotorDeJuego.CANTAR, MotorDeJuego.CANTAR_TUTE])


func _aplicar(e: EstadoGuinote, jugador_id: int, jugada: Dictionary) -> EstadoGuinote:
	var resultado := motor.aplicar_jugada(e, jugador_id, jugada)
	assert_true(resultado.ok, resultado.error)
	return resultado.estado


const CANTE_COPAS := {"tipo": "cantar", "palo": "copas"}
const CANTE_BASTOS := {"tipo": "cantar", "palo": "bastos"}

# Manos de ejemplo: el 0 tiene Sota y Rey de copas y de bastos; el 2 (su
# compañero), de espadas; el 1 (rival), de oros.
const MANOS := [
	["Sota_copas", "Rey_copas", "Sota_bastos", "Rey_bastos", "Dos_copas", "Cuatro_espadas"],
	["Sota_oros", "Rey_oros", "Cuatro_copas", "Cinco_bastos", "Seis_espadas", "Siete_copas"],
	["Sota_espadas", "Rey_espadas", "As_bastos", "Cinco_copas", "Seis_bastos", "Dos_espadas"],
	["As_oros", "Tres_oros", "As_copas", "Tres_bastos", "Siete_espadas", "As_espadas"],
]


# --- Quién y cuándo ---

func test_no_se_canta_antes_de_ganar_ninguna_baza() -> void:
	var e := MotorGuinote.new().iniciar(4) as EstadoGuinote
	for jugador in 4:
		assert_eq(_cantes(e, jugador), [] as Array[Dictionary], "jugador %d" % jugador)


func test_canta_la_pareja_que_gano_la_baza_y_no_la_rival() -> void:
	var e := _estado(MANOS, 0)
	assert_eq(_cantes(e, 0), [CANTE_COPAS, CANTE_BASTOS] as Array[Dictionary])
	assert_eq(_cantes(e, 2), [{"tipo": "cantar", "palo": "espadas"}] as Array[Dictionary],
		"el compañero puede cantar aunque no sea su turno")
	assert_eq(_cantes(e, 1), [] as Array[Dictionary], "el rival tiene las 40 pero no ganó la baza")


func test_se_puede_cantar_fuera_de_turno_sin_cambiar_el_turno() -> void:
	var e := _aplicar(_estado(MANOS, 0), 2, {"tipo": "cantar", "palo": "espadas"})
	assert_eq(e.turno, 0)
	assert_eq(e.cantes.size(), 1)


func test_la_ventana_sigue_tras_salir_y_se_cierra_cuando_juega_un_rival() -> void:
	var e := _aplicar(_estado(MANOS, 0), 0, {"tipo": "jugar_carta", "carta_id": "Cuatro_espadas"})
	assert_eq(_cantes(e, 0).size(), 2, "se puede cantar tras haber salido con la primera carta")
	e = _aplicar(e, 1, {"tipo": "jugar_carta", "carta_id": "Seis_espadas"})
	assert_eq(_cantes(e, 0), [] as Array[Dictionary], "un rival ya ha jugado en la baza")
	assert_eq(_cantes(e, 2), [] as Array[Dictionary])


# --- Cuánto vale y cuántas veces ---

func test_las_cuarenta_en_triunfo_y_veinte_en_otro_palo() -> void:
	var e := _aplicar(_estado(MANOS, 1), 1, {"tipo": "cantar", "palo": "oros"})
	assert_eq(e.cantes[0]["puntos"], 40)
	e = _aplicar(_estado(MANOS, 0), 0, CANTE_COPAS)
	assert_eq(e.cantes[0]["puntos"], 20)
	assert_eq(motor.calcular_resultado(e)["manos"][0]["cantes"], [20, 0])


func test_un_cante_por_miembro_y_por_baza_ganada() -> void:
	var e := _aplicar(_estado(MANOS, 0), 0, CANTE_COPAS)
	assert_eq(_cantes(e, 0), [] as Array[Dictionary], "ya ha cantado en esta baza")
	assert_eq(_cantes(e, 2).size(), 1, "su compañero todavía puede")
	# Su pareja gana otra baza: vuelve a poder cantar, pero ya no copas.
	e.bazas_jugadas += 1
	assert_eq(_cantes(e, 0), [CANTE_BASTOS] as Array[Dictionary])


func test_un_palo_ya_cantado_no_se_vuelve_a_cantar() -> void:
	var e := _aplicar(_estado(MANOS, 0), 0, CANTE_COPAS)
	e.bazas_jugadas += 1
	assert_does_not_have(_cantes(e, 0), CANTE_COPAS)


func test_no_se_puede_cantar_un_palo_que_no_se_tiene() -> void:
	var resultado := motor.aplicar_jugada(_estado(MANOS, 0), 0, {"tipo": "cantar", "palo": "espadas"})
	assert_false(resultado.ok)
	assert_eq(resultado.error, MotorDeJuego.ERROR_JUGADA_NO_VALIDA)


# --- Tute ---

const MANOS_TUTE := [
	["Rey_copas", "Rey_oros", "Rey_espadas", "Rey_bastos", "Dos_copas", "Cuatro_espadas"],
	["Sota_copas", "Sota_oros", "Sota_espadas", "Sota_bastos", "Seis_espadas", "Siete_copas"],
	["As_espadas", "As_copas", "As_bastos", "Cinco_copas", "Seis_bastos", "Dos_espadas"],
	["As_oros", "Tres_oros", "Tres_copas", "Tres_bastos", "Siete_espadas", "Tres_espadas"],
]


func test_tute_de_reyes_gana_la_partida_al_instante() -> void:
	var e := _estado(MANOS_TUTE, 0)
	assert_has(_cantes(e, 0), {"tipo": "cantar_tute", "figura": "reyes"})
	e = _aplicar(e, 0, {"tipo": "cantar_tute", "figura": "reyes"})
	assert_true(motor.ha_terminado(e))
	var resultado := motor.calcular_resultado(e)
	assert_eq(resultado["equipo_ganador"], 0)
	assert_eq(resultado["motivo"], "tute")
	for jugador in 4:
		assert_eq(motor.jugadas_validas(e, jugador), [] as Array[Dictionary])


func test_tute_de_sotas_solo_si_su_pareja_gano_la_baza() -> void:
	assert_eq(_cantes(_estado(MANOS_TUTE, 0), 1), [] as Array[Dictionary])
	assert_has(_cantes(_estado(MANOS_TUTE, 3), 1), {"tipo": "cantar_tute", "figura": "sotas"})


# --- Lo que ven los jugadores ---

func test_la_vista_muestra_los_cantes_a_todos() -> void:
	var e := _aplicar(_estado(MANOS, 0), 0, CANTE_COPAS)
	var vista := motor.vista_para_jugador(e, 1)
	assert_eq(vista["cantes"], [{"jugador_id": 0, "palo": "copas", "puntos": 20, "mano": "idas"}])
	assert_eq(vista["tute"], {})


## Las cartas ya son ids de texto: solo hace falta una copia tipada.
func _ids_de(cartas: Array) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(cartas)
	return ids
