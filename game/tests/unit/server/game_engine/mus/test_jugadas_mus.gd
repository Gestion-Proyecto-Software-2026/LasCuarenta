extends GutTest
## Valoración de Grande, Chica, Pares, Juego y Punto (analisis_funcional_app.md §9).

const L := EstadoMus.Lance


func _m(ids: Array) -> Array[Carta]:
	var cartas: Array[Carta] = []
	for id: String in ids:
		cartas.append(Carta.desde_id(id))
	return cartas


func _gana(lance: EstadoMus.Lance, a: Array, b: Array) -> bool:
	return JugadasMus.comparar(lance, _m(a), _m(b)) > 0


# --- Grande y Chica ---

func test_el_tres_es_rey_y_el_dos_es_as() -> void:
	assert_eq(JugadasMus.comparar(L.GRANDE, _m(["oros_12", "copas_1", "oros_4", "oros_5"]),
		_m(["copas_3", "oros_2", "copas_4", "copas_5"])), 0, "R A 4 5 empata con 3 2 4 5")


func test_grande_gana_la_carta_mas_alta_y_luego_la_siguiente() -> void:
	assert_true(_gana(L.GRANDE, ["oros_12", "copas_1", "oros_2", "oros_4"], ["oros_11", "copas_11", "espadas_11", "bastos_11"]))
	assert_true(_gana(L.GRANDE, ["oros_12", "copas_11", "oros_1", "oros_2"], ["copas_12", "oros_10", "espadas_7", "bastos_7"]))
	assert_true(_gana(L.GRANDE, ["oros_12", "copas_10", "oros_5", "oros_1"], ["copas_12", "espadas_10", "bastos_4", "copas_7"]) == false)


func test_chica_gana_la_carta_mas_baja_y_luego_la_siguiente() -> void:
	assert_true(_gana(L.CHICA, ["oros_1", "copas_12", "espadas_12", "bastos_12"], ["oros_4", "copas_4", "espadas_4", "bastos_4"]))
	assert_true(_gana(L.CHICA, ["copas_1", "espadas_1", "bastos_5", "copas_4"], ["oros_1", "copas_2", "oros_4", "oros_12"]),
		"a iguales las tres más bajas, decide la cuarta")
	assert_false(_gana(L.CHICA, ["oros_1", "copas_2", "oros_5", "oros_12"], ["copas_1", "espadas_2", "bastos_4", "copas_12"]))


# --- Pares ---

func test_tipos_de_pares() -> void:
	assert_eq(JugadasMus.pares(_m(["oros_1", "copas_4", "oros_5", "oros_7"]))["tipo"], JugadasMus.Pares.NINGUNO)
	assert_eq(JugadasMus.pares(_m(["oros_1", "copas_2", "oros_5", "oros_7"]))["tipo"], JugadasMus.Pares.PAR, "As y Dos son pareja")
	assert_eq(JugadasMus.pares(_m(["oros_12", "copas_3", "oros_12", "oros_7"]))["tipo"], JugadasMus.Pares.MEDIAS)
	assert_eq(JugadasMus.pares(_m(["oros_12", "copas_3", "oros_5", "copas_5"]))["tipo"], JugadasMus.Pares.DUPLES)
	assert_eq(JugadasMus.pares(_m(["oros_11", "copas_11", "espadas_11", "bastos_11"]))["tipo"], JugadasMus.Pares.DUPLES,
		"cuatro iguales son duples")


func test_pares_gana_el_tipo_y_luego_las_cartas() -> void:
	assert_true(_gana(L.PARES, ["oros_4", "copas_4", "espadas_4", "bastos_1"], ["oros_12", "copas_12", "espadas_11", "bastos_10"]),
		"medias de cuatros a par de reyes")
	assert_true(_gana(L.PARES, ["oros_4", "copas_4", "espadas_5", "bastos_5"], ["oros_12", "copas_12", "espadas_12", "bastos_10"]),
		"duples a medias")
	assert_true(_gana(L.PARES, ["oros_12", "copas_12", "espadas_1", "bastos_4"], ["oros_11", "copas_11", "espadas_1", "bastos_4"]))
	assert_true(_gana(L.PARES, ["oros_12", "copas_12", "espadas_4", "bastos_4"], ["oros_12", "copas_3", "espadas_1", "bastos_1"]),
		"en duples, a igual par mayor decide el menor")
	assert_true(_gana(L.PARES, ["oros_12", "copas_12", "espadas_3", "bastos_3"], ["oros_12", "copas_12", "espadas_11", "bastos_11"]),
		"duples de reyes (cuatro) a reyes y caballos")
	assert_eq(JugadasMus.comparar(L.PARES, _m(["oros_12", "copas_12", "espadas_1", "bastos_4"]),
		_m(["oros_3", "copas_3", "espadas_5", "bastos_6"])), 0, "mismo par: empate")


func test_valor_de_pares() -> void:
	assert_eq(JugadasMus.valor(_m(["oros_1", "copas_4", "oros_5", "oros_7"]), L.PARES), 0)
	assert_eq(JugadasMus.valor(_m(["oros_1", "copas_1", "oros_5", "oros_7"]), L.PARES), 1)
	assert_eq(JugadasMus.valor(_m(["oros_1", "copas_1", "espadas_1", "oros_7"]), L.PARES), 2)
	assert_eq(JugadasMus.valor(_m(["oros_1", "copas_1", "espadas_7", "oros_7"]), L.PARES), 3)


# --- Juego y Punto ---

func test_puntos_de_las_cartas() -> void:
	assert_eq(JugadasMus.puntos(_m(["oros_12", "copas_11", "espadas_10", "bastos_3"])), 40)
	assert_eq(JugadasMus.puntos(_m(["oros_1", "copas_2", "espadas_7", "bastos_4"])), 13)


func test_tiene_juego_desde_31() -> void:
	assert_true(JugadasMus.tiene_juego(_m(["oros_12", "copas_11", "espadas_7", "bastos_4"])), "31")
	assert_false(JugadasMus.tiene_juego(_m(["oros_12", "copas_11", "espadas_5", "bastos_5"])), "30")


func test_orden_del_juego_31_32_40_37_y_baja() -> void:
	var j31 := ["oros_12", "copas_11", "espadas_10", "bastos_1"]
	var j32 := ["oros_12", "copas_11", "espadas_6", "bastos_6"]
	var j40 := ["oros_12", "copas_11", "espadas_10", "bastos_3"]
	var j37 := ["oros_12", "copas_11", "espadas_10", "bastos_7"]
	var j33 := ["oros_12", "copas_11", "espadas_7", "bastos_6"]
	assert_eq(JugadasMus.puntos(_m(j31)), 31)
	assert_eq(JugadasMus.puntos(_m(j32)), 32)
	assert_eq(JugadasMus.puntos(_m(j33)), 33)
	assert_true(_gana(L.JUEGO, j31, j32))
	assert_true(_gana(L.JUEGO, j32, j40))
	assert_true(_gana(L.JUEGO, j40, j37))
	assert_true(_gana(L.JUEGO, j37, j33))
	assert_true(_gana(L.JUEGO, j33, ["oros_12", "copas_11", "espadas_5", "bastos_5"]), "con juego a sin juego")


func test_punto_gana_el_que_mas_suma() -> void:
	assert_true(_gana(L.PUNTO, ["oros_12", "copas_11", "espadas_5", "bastos_5"], ["oros_12", "copas_11", "espadas_5", "bastos_4"]))
	assert_eq(JugadasMus.comparar(L.PUNTO, _m(["oros_12", "copas_4"]), _m(["oros_3", "copas_4"])), 0)


func test_valor_del_juego() -> void:
	assert_eq(JugadasMus.valor(_m(["oros_12", "copas_11", "espadas_10", "bastos_1"]), L.JUEGO), 3, "la de 31")
	assert_eq(JugadasMus.valor(_m(["oros_12", "copas_11", "espadas_10", "bastos_3"]), L.JUEGO), 2)
	assert_eq(JugadasMus.valor(_m(["oros_12", "copas_11", "espadas_5", "bastos_5"]), L.JUEGO), 0)


func test_tiene_jugada_por_lance() -> void:
	var sin_nada := _m(["oros_1", "copas_4", "espadas_5", "bastos_6"])
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.GRANDE))
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.CHICA))
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.PUNTO))
	assert_false(JugadasMus.tiene_jugada(sin_nada, L.PARES))
	assert_false(JugadasMus.tiene_jugada(sin_nada, L.JUEGO))
