extends GutTest
## Los textos que la mesa común saca de lo que manda el servidor: lo que dice
## cada jugador al jugar y el panel del resultado final.

const Textos := preload("res://client/ui/mesa/textos_mesa.gd")

const DOS := ["Ana", "Luis"]
const CUATRO := ["Ana", "Luis", "Marta", ""]


func _anuncio(jugada: Dictionary, anterior := {}, vista := {}) -> String:
	return Textos.anuncio(jugada, anterior, vista)


func test_echar_una_carta_no_se_anuncia() -> void:
	assert_eq(_anuncio({"tipo": MensajesRed.JUGAR_CARTA, "carta_id": "oros_1"}), "")


func test_cantes() -> void:
	var vista := {"palo_triunfo": "oros"}
	assert_eq(_anuncio({"tipo": MensajesRed.CANTAR, "palo": "oros"}, {}, vista), "¡Las 40!")
	assert_eq(_anuncio({"tipo": MensajesRed.CANTAR, "palo": "copas"}, {}, vista), "Las 20 en copas")
	assert_eq(_anuncio({"tipo": MensajesRed.CANTAR_TUTE, "figura": "reyes"}), "¡Tute de reyes!")
	assert_eq(_anuncio({"tipo": MensajesRed.CAPOTE}), "¡Capote!")
	assert_eq(_anuncio({"tipo": MensajesRed.CAMBIAR_SIETE}), "Cambio la pinta")
	assert_eq(_anuncio({"tipo": MensajesRed.NO_CAMBIAR_SIETE}), "No cambio la pinta")


func test_mus() -> void:
	assert_eq(_anuncio({"tipo": MensajesRed.MUS}), "Mus")
	assert_eq(_anuncio({"tipo": MensajesRed.NO_MUS}), "No hay mus")
	assert_eq(_anuncio({"tipo": MensajesRed.DESCARTAR, "num_cartas": 1}), "Me descarto de una")
	assert_eq(_anuncio({"tipo": MensajesRed.DESCARTAR, "num_cartas": 3}), "Me descarto de 3")
	assert_eq(_anuncio({"tipo": MensajesRed.PASAR}), "Paso")
	assert_eq(_anuncio({"tipo": MensajesRed.ORDAGO}), "¡Órdago!")
	assert_eq(_anuncio({"tipo": MensajesRed.QUIERO}), "Quiero")
	assert_eq(_anuncio({"tipo": MensajesRed.NO_QUIERO}), "No quiero")


func test_envidar_es_subir_si_ya_habia_un_envite() -> void:
	var jugada := {"tipo": MensajesRed.ENVIDAR, "cantidad": 2}
	assert_eq(_anuncio(jugada, {"envite": {}}), "Envido 2")
	assert_eq(_anuncio(jugada, {"envite": {"equipo": 1, "apuesta": 2, "ordago": false}}), "Subo 2")


func test_vuelta() -> void:
	assert_eq(Textos.anuncio_vuelta({"tanteo_idas": [88, 72]}), "Nadie pasa de 100: ¡vuelta! Idas 88 - 72")
	assert_eq(Textos.marcador_idas({"tanteo_idas": [88, 72]}, DOS), "Idas: Ana 88 · Luis 72")


func test_nombres_de_equipo() -> void:
	assert_eq(Textos.nombre_equipo(1, DOS), "Luis")
	assert_eq(Textos.nombre_equipo(0, CUATRO), "la pareja A (Ana y Marta)")
	assert_eq(Textos.nombre_equipo(1, CUATRO), "la pareja B (Luis y Jugador 4)", "sin nombre, Jugador N")


func test_resultado_del_guinote_con_idas_y_vuelta() -> void:
	var texto := Textos.resultado("guinote", {
		"equipo_ganador": 1, "puntos_por_equipo": [90, 104], "motivo": "vuelta",
		"manos": [
			{"total": [70, 60], "cartas": [60, 60], "cantes": [0, 0], "diez_ultimas": [10, 0]},
			{"total": [20, 44], "cartas": [20, 24], "cantes": [0, 20], "diez_ultimas": [0, 0]},
		],
	}, DOS)
	assert_eq(texto, "\n".join([
		"FIN DE LA PARTIDA",
		"Gana Luis en la vuelta.",
		"Idas:",
		"  Ana: 70 = cartas 60 + cantes 0 + últimas 10",
		"  Luis: 60 = cartas 60 + cantes 0 + últimas 0",
		"Vuelta:",
		"  Ana: 20 = cartas 20 + cantes 0 + últimas 0",
		"  Luis: 44 = cartas 24 + cantes 20 + últimas 0",
		"Total: 90 - 104",
	]))


func test_resultado_del_tute_por_parejas() -> void:
	var texto := Textos.resultado("tute", {
		"equipo_ganador": 0, "puntos_por_equipo": [80, 50], "motivo": "tantos",
		"manos": [{"total": [80, 50], "cartas": [70, 50], "cantes": [0, 0], "diez_ultimas": [10, 0]}],
	}, CUATRO)
	assert_string_contains(texto, "Gana la pareja A (Ana y Marta) por tantos al acabar las idas.")
	assert_string_contains(texto, "Tanteo:")
	assert_false(texto.contains("Total:"), "con una sola mano no hace falta el total")


func test_resultado_del_mus() -> void:
	var texto := Textos.resultado("mus", {
		"equipo_ganador": 1, "puntos_por_equipo": [1, 2], "piedras_por_juego": 40,
		"juegos": [
			{"equipo": 0, "piedras": [40, 12], "motivo": "piedras"},
			{"equipo": 1, "piedras": [3, 5], "motivo": "ordago"},
			{"equipo": 1, "piedras": [20, 41], "motivo": "piedras"},
		],
	}, DOS)
	assert_eq(texto, "\n".join([
		"FIN DE LA PARTIDA",
		"Gana Luis, 2 juegos a 1.",
		"Juego 1: Ana (40 - 12 piedras)",
		"Juego 2: Luis (3 - 5 piedras, por órdago)",
		"Juego 3: Luis (20 - 41 piedras)",
	]))
