extends GutTest
## La máquina del Guiñote y del Tute (PBI-20): juega siempre jugadas válidas, tiene
## el criterio que promete cada nivel y los niveles se notan al jugar.

const JUEGOS := [["guinote", 2], ["guinote", 4], ["tute", 2], ["tute", 4]]
const MOTORES := {
	"guinote": preload("res://server/game_engine/guinote/motor_guinote.gd"),
	"tute": preload("res://server/game_engine/tute/motor_tute.gd"),
}


## Juega una partida entera entre máquinas y devuelve el equipo ganador (o -1 si
## alguna jugada no fue válida, o la partida no terminó).
func _partida(juego: String, n: int, dificultades: Array, semilla: int) -> int:
	var rng_motor := RandomNumberGenerator.new()
	rng_motor.seed = semilla
	var motor: MotorDeJuego = MOTORES[juego].new(rng_motor)
	var bots: Array[JugadorMaquina] = []
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = semilla * 31 + i
		bots.append(FabricaDeMaquinas.para_juego(juego, n, dificultades[i], rng))
	var estado := motor.iniciar(n)
	var pasos := 0
	while not motor.ha_terminado(estado) and pasos < 5000:
		pasos += 1
		var esperados := motor.jugadores_esperados(estado)
		if esperados.is_empty():
			break
		var jugador := esperados[0]
		var jugada := bots[jugador].decidir(
			motor.vista_para_jugador(estado, jugador), motor.jugadas_validas(estado, jugador))
		var resultado := motor.aplicar_jugada(estado, jugador, jugada)
		if not resultado.ok:
			push_error("%s a %d, nivel %s: jugada no válida %s (%s)" % [juego, n, dificultades, jugada, resultado.error])
			return -1
		estado = resultado.estado
	if not motor.ha_terminado(estado):
		return -1
	return motor.calcular_resultado(estado)["equipo_ganador"]


func test_los_tres_niveles_juegan_partidas_enteras_con_jugadas_validas() -> void:
	for juego: Array in JUEGOS:
		for nivel: int in JugadorMaquina.Dificultad.values():
			for semilla in 4:
				var ganador := _partida(juego[0], juego[1], [nivel, nivel, nivel, nivel], semilla + 1)
				assert_true(ganador in [0, 1], "%s a %d, nivel %d, semilla %d: la partida acabó" % [juego[0], juego[1], nivel, semilla + 1])


func test_niveles_mezclados_tambien_acaban() -> void:
	var niveles := [JugadorMaquina.Dificultad.DIFICIL, JugadorMaquina.Dificultad.FACIL,
		JugadorMaquina.Dificultad.NORMAL, JugadorMaquina.Dificultad.DIFICIL]
	for juego: Array in JUEGOS:
		var ganador := _partida(juego[0], juego[1], niveles, 7)
		assert_true(ganador in [0, 1], "%s a %d: la partida acabó" % [juego[0], juego[1]])


func test_nombres_de_dificultad() -> void:
	assert_eq(JugadorMaquina.nombre_de(JugadorMaquina.Dificultad.DIFICIL), "dificil")
	assert_eq(JugadorMaquina.desde_nombre("normal"), JugadorMaquina.Dificultad.NORMAL)
	assert_eq(JugadorMaquina.desde_nombre("imposible"), -1)


func test_sin_jugadas_no_hace_nada() -> void:
	var maquina := FabricaDeMaquinas.para_juego("guinote", 2, JugadorMaquina.Dificultad.NORMAL)
	assert_eq(maquina.decidir({}, [] as Array[Dictionary]), {})


## Mide cuánto gana un nivel a otro, alternando asientos para que ninguno juegue
## siempre de salida. Devuelve las partidas ganadas por el primer nivel.
func _enfrentar(juego: String, n: int, fuerte: int, flojo: int, partidas: int) -> int:
	var ganadas := 0
	for i in partidas:
		var semilla := 100 + i
		var fuerte_en_equipo_0 := i % 2 == 0
		var niveles: Array = []
		for asiento in n:
			var es_equipo_0 := asiento % 2 == 0
			niveles.append(fuerte if es_equipo_0 == fuerte_en_equipo_0 else flojo)
		var ganador := _partida(juego, n, niveles, semilla)
		if (ganador == 0) == fuerte_en_equipo_0:
			ganadas += 1
	return ganadas


## Los niveles se notan al jugar. Las partidas usan semillas fijas, así que el
## resultado es siempre el mismo. Medido con 120 partidas por enfrentamiento
## (informe, sprint 4): la Normal gana a la Fácil el 93 % en Guiñote a 2, el 78 % en
## Guiñote a 4, el 98 % en Tute a 2 y el 61 % en Tute a 4; la Difícil gana a la
## Normal entre el 54 y el 58 % de las veces.
func test_normal_gana_a_facil_en_guinote_y_tute() -> void:
	var normal := JugadorMaquina.Dificultad.NORMAL
	var facil := JugadorMaquina.Dificultad.FACIL
	assert_gt(_enfrentar("guinote", 2, normal, facil, 40), 32, "Guiñote a 2")
	assert_gt(_enfrentar("guinote", 4, normal, facil, 40), 26, "Guiñote a 4")
	assert_gt(_enfrentar("tute", 2, normal, facil, 40), 32, "Tute a 2")
	assert_gt(_enfrentar("tute", 4, normal, facil, 120), 66, "Tute a 4")


func test_dificil_gana_a_facil_en_guinote_y_tute() -> void:
	var dificil := JugadorMaquina.Dificultad.DIFICIL
	var facil := JugadorMaquina.Dificultad.FACIL
	assert_gt(_enfrentar("guinote", 2, dificil, facil, 40), 32, "Guiñote a 2")
	assert_gt(_enfrentar("guinote", 4, dificil, facil, 40), 29, "Guiñote a 4")
	assert_gt(_enfrentar("tute", 2, dificil, facil, 40), 32, "Tute a 2")
