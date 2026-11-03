extends GutTest
## Valoración de Grande, Chica, Pares, Juego y Punto (analisis_funcional_app.md §9).
## Copia de game/tests/unit/server/game_engine/mus/ (Carlos) con las cartas como ids de texto.

const L := EstadoMus.Lance


func _m(ids: Array) -> Array[String]:
	var cartas: Array[String] = []
	for id: String in ids:
		cartas.append(id)
	return cartas


func _gana(lance: EstadoMus.Lance, a: Array, b: Array) -> bool:
	return JugadasMus.comparar(lance, _m(a), _m(b)) > 0


# --- Grande y Chica ---

func test_el_tres_es_rey_y_el_dos_es_as() -> void:
	assert_eq(JugadasMus.comparar(L.GRANDE, _m(["Rey_oros", "As_copas", "Cuatro_oros", "Cinco_oros"]),
		_m(["Tres_copas", "Dos_oros", "Cuatro_copas", "Cinco_copas"])), 0, "R A 4 5 empata con 3 2 4 5")


func test_grande_gana_la_carta_mas_alta_y_luego_la_siguiente() -> void:
	assert_true(_gana(L.GRANDE, ["Rey_oros", "As_copas", "Dos_oros", "Cuatro_oros"], ["Caballo_oros", "Caballo_copas", "Caballo_espadas", "Caballo_bastos"]))
	assert_true(_gana(L.GRANDE, ["Rey_oros", "Caballo_copas", "As_oros", "Dos_oros"], ["Rey_copas", "Sota_oros", "Siete_espadas", "Siete_bastos"]))
	assert_true(_gana(L.GRANDE, ["Rey_oros", "Sota_copas", "Cinco_oros", "As_oros"], ["Rey_copas", "Sota_espadas", "Cuatro_bastos", "Siete_copas"]) == false)


func test_chica_gana_la_carta_mas_baja_y_luego_la_siguiente() -> void:
	assert_true(_gana(L.CHICA, ["As_oros", "Rey_copas", "Rey_espadas", "Rey_bastos"], ["Cuatro_oros", "Cuatro_copas", "Cuatro_espadas", "Cuatro_bastos"]))
	assert_true(_gana(L.CHICA, ["As_copas", "As_espadas", "Cinco_bastos", "Cuatro_copas"], ["As_oros", "Dos_copas", "Cuatro_oros", "Rey_oros"]),
		"a iguales las tres más bajas, decide la cuarta")
	assert_false(_gana(L.CHICA, ["As_oros", "Dos_copas", "Cinco_oros", "Rey_oros"], ["As_copas", "Dos_espadas", "Cuatro_bastos", "Rey_copas"]))


# --- Pares ---

func test_tipos_de_pares() -> void:
	assert_eq(JugadasMus.pares(_m(["As_oros", "Cuatro_copas", "Cinco_oros", "Siete_oros"]))["tipo"], JugadasMus.Pares.NINGUNO)
	assert_eq(JugadasMus.pares(_m(["As_oros", "Dos_copas", "Cinco_oros", "Siete_oros"]))["tipo"], JugadasMus.Pares.PAR, "As y Dos son pareja")
	assert_eq(JugadasMus.pares(_m(["Rey_oros", "Tres_copas", "Rey_oros", "Siete_oros"]))["tipo"], JugadasMus.Pares.MEDIAS)
	assert_eq(JugadasMus.pares(_m(["Rey_oros", "Tres_copas", "Cinco_oros", "Cinco_copas"]))["tipo"], JugadasMus.Pares.DUPLES)
	assert_eq(JugadasMus.pares(_m(["Caballo_oros", "Caballo_copas", "Caballo_espadas", "Caballo_bastos"]))["tipo"], JugadasMus.Pares.DUPLES,
		"cuatro iguales son duples")


func test_pares_gana_el_tipo_y_luego_las_cartas() -> void:
	assert_true(_gana(L.PARES, ["Cuatro_oros", "Cuatro_copas", "Cuatro_espadas", "As_bastos"], ["Rey_oros", "Rey_copas", "Caballo_espadas", "Sota_bastos"]),
		"medias de cuatros a par de reyes")
	assert_true(_gana(L.PARES, ["Cuatro_oros", "Cuatro_copas", "Cinco_espadas", "Cinco_bastos"], ["Rey_oros", "Rey_copas", "Rey_espadas", "Sota_bastos"]),
		"duples a medias")
	assert_true(_gana(L.PARES, ["Rey_oros", "Rey_copas", "As_espadas", "Cuatro_bastos"], ["Caballo_oros", "Caballo_copas", "As_espadas", "Cuatro_bastos"]))
	assert_true(_gana(L.PARES, ["Rey_oros", "Rey_copas", "Cuatro_espadas", "Cuatro_bastos"], ["Rey_oros", "Tres_copas", "As_espadas", "As_bastos"]),
		"en duples, a igual par mayor decide el menor")
	assert_true(_gana(L.PARES, ["Rey_oros", "Rey_copas", "Tres_espadas", "Tres_bastos"], ["Rey_oros", "Rey_copas", "Caballo_espadas", "Caballo_bastos"]),
		"duples de reyes (cuatro) a reyes y caballos")
	assert_eq(JugadasMus.comparar(L.PARES, _m(["Rey_oros", "Rey_copas", "As_espadas", "Cuatro_bastos"]),
		_m(["Tres_oros", "Tres_copas", "Cinco_espadas", "Seis_bastos"])), 0, "mismo par: empate")


func test_valor_de_pares() -> void:
	assert_eq(JugadasMus.valor(_m(["As_oros", "Cuatro_copas", "Cinco_oros", "Siete_oros"]), L.PARES), 0)
	assert_eq(JugadasMus.valor(_m(["As_oros", "As_copas", "Cinco_oros", "Siete_oros"]), L.PARES), 1)
	assert_eq(JugadasMus.valor(_m(["As_oros", "As_copas", "As_espadas", "Siete_oros"]), L.PARES), 2)
	assert_eq(JugadasMus.valor(_m(["As_oros", "As_copas", "Siete_espadas", "Siete_oros"]), L.PARES), 3)


# --- Juego y Punto ---

func test_puntos_de_las_cartas() -> void:
	assert_eq(JugadasMus.puntos(_m(["Rey_oros", "Caballo_copas", "Sota_espadas", "Tres_bastos"])), 40)
	assert_eq(JugadasMus.puntos(_m(["As_oros", "Dos_copas", "Siete_espadas", "Cuatro_bastos"])), 13)


func test_tiene_juego_desde_31() -> void:
	assert_true(JugadasMus.tiene_juego(_m(["Rey_oros", "Caballo_copas", "Siete_espadas", "Cuatro_bastos"])), "31")
	assert_false(JugadasMus.tiene_juego(_m(["Rey_oros", "Caballo_copas", "Cinco_espadas", "Cinco_bastos"])), "30")


func test_orden_del_juego_31_32_40_37_y_baja() -> void:
	var j31 := ["Rey_oros", "Caballo_copas", "Sota_espadas", "As_bastos"]
	var j32 := ["Rey_oros", "Caballo_copas", "Seis_espadas", "Seis_bastos"]
	var j40 := ["Rey_oros", "Caballo_copas", "Sota_espadas", "Tres_bastos"]
	var j37 := ["Rey_oros", "Caballo_copas", "Sota_espadas", "Siete_bastos"]
	var j33 := ["Rey_oros", "Caballo_copas", "Siete_espadas", "Seis_bastos"]
	assert_eq(JugadasMus.puntos(_m(j31)), 31)
	assert_eq(JugadasMus.puntos(_m(j32)), 32)
	assert_eq(JugadasMus.puntos(_m(j33)), 33)
	assert_true(_gana(L.JUEGO, j31, j32))
	assert_true(_gana(L.JUEGO, j32, j40))
	assert_true(_gana(L.JUEGO, j40, j37))
	assert_true(_gana(L.JUEGO, j37, j33))
	assert_true(_gana(L.JUEGO, j33, ["Rey_oros", "Caballo_copas", "Cinco_espadas", "Cinco_bastos"]), "con juego a sin juego")


func test_punto_gana_el_que_mas_suma() -> void:
	assert_true(_gana(L.PUNTO, ["Rey_oros", "Caballo_copas", "Cinco_espadas", "Cinco_bastos"], ["Rey_oros", "Caballo_copas", "Cinco_espadas", "Cuatro_bastos"]))
	assert_eq(JugadasMus.comparar(L.PUNTO, _m(["Rey_oros", "Cuatro_copas"]), _m(["Tres_oros", "Cuatro_copas"])), 0)


func test_valor_del_juego() -> void:
	assert_eq(JugadasMus.valor(_m(["Rey_oros", "Caballo_copas", "Sota_espadas", "As_bastos"]), L.JUEGO), 3, "la de 31")
	assert_eq(JugadasMus.valor(_m(["Rey_oros", "Caballo_copas", "Sota_espadas", "Tres_bastos"]), L.JUEGO), 2)
	assert_eq(JugadasMus.valor(_m(["Rey_oros", "Caballo_copas", "Cinco_espadas", "Cinco_bastos"]), L.JUEGO), 0)


func test_tiene_jugada_por_lance() -> void:
	var sin_nada := _m(["As_oros", "Cuatro_copas", "Cinco_espadas", "Seis_bastos"])
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.GRANDE))
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.CHICA))
	assert_true(JugadasMus.tiene_jugada(sin_nada, L.PUNTO))
	assert_false(JugadasMus.tiene_jugada(sin_nada, L.PARES))
	assert_false(JugadasMus.tiene_jugada(sin_nada, L.JUEGO))
