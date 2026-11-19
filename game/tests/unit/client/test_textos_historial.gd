extends GutTest
## Los textos que la pantalla de historial (PBI-06) saca de lo que manda el
## backend: cada partida de la lista y el resumen de estadísticas.

const Textos := preload("res://client/ui/historial/textos_historial.gd")

## Una partida de Guiñote por parejas, como la devuelve GET /usuarios/me/historial.
const PARTIDA := {
	"partida_id": "p1",
	"juego": "guinote",
	"num_jugadores": 4,
	"fecha_inicio": "2026-11-18T10:00:00.000Z",
	"fecha_fin": "2026-11-18T10:24:13.000Z",
	"resultado": "victoria",
	"gano": true,
	"causa": "completa",
	"motivo": "tantos",
	"equipo": 0,
	"puntos_equipo": 105.0,
	"puntos_rival": 52.0,
	"companeros": [{"usuario_id": "u3", "nombre_visible": "Marta", "posicion": 2.0}],
	"rivales": [
		{"usuario_id": "u2", "nombre_visible": "Luis", "posicion": 1.0},
		{"usuario_id": "u4", "nombre_visible": "Pedro", "posicion": 3.0},
	],
}
## Hora peninsular en invierno: UTC + 1.
const INVIERNO := 60


func _con(cambios: Dictionary) -> Dictionary:
	var partida := PARTIDA.duplicate(true)
	partida.merge(cambios, true)
	return partida


# --- Cada partida ---

func test_juego_y_modo() -> void:
	assert_eq(Textos.juego_y_modo(PARTIDA), "Guiñote · por parejas")
	assert_eq(Textos.juego_y_modo(_con({"juego": "mus", "num_jugadores": 2.0})), "Mus · 1 contra 1")
	assert_eq(Textos.juego_y_modo(_con({"juego": "tute"})), "Tute · por parejas")


func test_victoria_y_derrota() -> void:
	assert_eq(Textos.resultado(PARTIDA), "VICTORIA")
	assert_eq(Textos.color_resultado(PARTIDA), Textos.COLOR_VICTORIA)
	var derrota := _con({"gano": false, "resultado": "derrota"})
	assert_eq(Textos.resultado(derrota), "DERROTA")
	assert_eq(Textos.color_resultado(derrota), Textos.COLOR_DERROTA)


func test_como_termino() -> void:
	assert_eq(Textos.causa(PARTIDA), "Por tantos")
	assert_eq(Textos.causa(_con({"motivo": "tute"})), "Cantó Tute")
	assert_eq(Textos.causa(_con({"motivo": "vuelta"})), "En la vuelta")
	assert_eq(Textos.causa(_con({"motivo": "capote"})), "Capote")
	assert_eq(Textos.causa(_con({"juego": "mus", "motivo": null})), "Partida completa", "el Mus no tiene motivo")
	assert_eq(Textos.causa(_con({"causa": "renuncio"})), "Renuncio admitido en el chat",
		"la causa manda sobre el motivo")


func test_marcador() -> void:
	assert_eq(Textos.marcador(PARTIDA), "105 – 52")
	assert_eq(Textos.marcador(_con({"juego": "mus", "puntos_equipo": 2.0, "puntos_rival": 1.0})), "2 – 1 juegos")
	assert_eq(Textos.marcador(_con({"puntos_rival": null})), "105 – 0")


func test_la_fecha_se_ensena_en_hora_local() -> void:
	assert_eq(Textos.fecha_local("2026-11-18T10:24:13.000Z", INVIERNO), "18/11/2026 11:24")
	assert_eq(Textos.fecha_local("2026-11-18T10:24:13.000Z", 0), "18/11/2026 10:24")
	assert_eq(Textos.fecha_local("2026-11-18T10:24:13Z", 120), "18/11/2026 12:24", "sin milisegundos y en verano")


func test_el_desfase_puede_cambiar_el_dia() -> void:
	assert_eq(Textos.fecha_local("2026-12-31T23:30:00.000Z", INVIERNO), "01/01/2027 00:30")
	assert_eq(Textos.fecha_local("2026-11-18T03:10:00.000Z", -300), "17/11/2026 22:10", "al oeste de UTC")
	assert_eq(Textos.fecha_local("2026-03-05T12:00:00.000Z", 330), "05/03/2026 17:30", "desfases de media hora")


func test_lo_que_no_es_una_fecha_no_se_ensena() -> void:
	assert_eq(Textos.fecha_local(null, INVIERNO), "")
	assert_eq(Textos.fecha_local("", INVIERNO), "")
	assert_eq(Textos.fecha_local("ayer por la tarde", INVIERNO), "")
	assert_eq(Textos.fecha_local("2026-02-30T10:00:00Z", INVIERNO), "", "un día que no existe")
	assert_eq(Textos.fecha_local("2026-11-18T25:00:00Z", INVIERNO), "")


func test_el_desfase_del_sistema_es_razonable() -> void:
	var desfase := Textos.desfase_del_sistema()
	assert_between(desfase, -12 * 60, 14 * 60, "ningún huso horario se sale de UTC-12 a UTC+14")


func test_duracion() -> void:
	assert_eq(Textos.duracion("2026-11-18T10:00:00.000Z", "2026-11-18T10:24:13.000Z"), "24 min")
	assert_eq(Textos.duracion("2026-11-18T23:50:00.000Z", "2026-11-19T00:35:40.000Z"), "46 min", "pasando la medianoche")
	assert_eq(Textos.duracion("2026-11-18T10:00:00.000Z", "2026-11-18T10:00:30.000Z"), "menos de 1 min")


func test_sin_inicio_real_no_hay_duracion() -> void:
	assert_eq(Textos.duracion(PARTIDA["fecha_fin"], PARTIDA["fecha_fin"]), "", "el backend puso la de fin")
	assert_eq(Textos.duracion(null, PARTIDA["fecha_fin"]), "")
	assert_eq(Textos.duracion(PARTIDA["fecha_fin"], PARTIDA["fecha_inicio"]), "", "al revés no tiene sentido")


func test_detalle_de_la_partida() -> void:
	assert_eq(Textos.detalle(PARTIDA, INVIERNO), "18/11/2026 11:24 · 24 min · Por tantos")
	assert_eq(Textos.detalle(_con({"fecha_inicio": PARTIDA["fecha_fin"]}), INVIERNO), "18/11/2026 11:24 · Por tantos",
		"sin duración no queda un hueco")


func test_companeros_y_rivales() -> void:
	assert_eq(Textos.jugadores(PARTIDA), "Con Marta · Contra Luis y Pedro")
	assert_eq(Textos.jugadores(_con({"companeros": [], "rivales": [PARTIDA["rivales"][0]]})), "Contra Luis")
	assert_eq(Textos.jugadores(_con({"companeros": [], "rivales": [
		{"nombre_visible": "Ana", "posicion": 0.0},
		{"nombre_visible": "Luis", "posicion": 1.0},
		{"nombre_visible": "Pedro", "posicion": 3.0},
	]})), "Contra Ana, Luis y Pedro")


func test_un_jugador_sin_nombre_sale_por_su_asiento() -> void:
	assert_eq(Textos.jugadores(_con({"companeros": [{"nombre_visible": "", "posicion": 2.0}]})),
		"Con Jugador 3 · Contra Luis y Pedro")
	assert_eq(Textos.jugadores(_con({"companeros": null, "rivales": null})), "")


# --- Estadísticas ---

func test_resumen() -> void:
	var totales := {"jugadas": 12.0, "victorias": 7.0, "derrotas": 5.0, "porcentaje_victorias": 58.3}
	assert_eq(Textos.resumen(totales), "12 partidas · 7 victorias · 5 derrotas · 58,3 % de victorias")


func test_resumen_en_singular_y_sin_partidas() -> void:
	var una := {"jugadas": 1.0, "victorias": 1.0, "derrotas": 0.0, "porcentaje_victorias": 100.0}
	assert_eq(Textos.resumen(una), "1 partida · 1 victoria · 0 derrotas · 100 % de victorias")
	assert_eq(Textos.resumen({}), "0 partidas · 0 victorias · 0 derrotas · 0 % de victorias")
	assert_eq(Textos.resumen(null), "0 partidas · 0 victorias · 0 derrotas · 0 % de victorias")


func test_porcentaje() -> void:
	assert_eq(Textos.porcentaje(58.3), "58,3 %")
	assert_eq(Textos.porcentaje(50), "50 %")
	assert_eq(Textos.porcentaje(50.0), "50 %")
	assert_eq(Textos.porcentaje(66.66), "66,7 %")
	assert_eq(Textos.porcentaje(null), "0 %")


func test_una_linea_por_juego_con_partidas() -> void:
	var por_juego := [
		{"juego": "guinote", "jugadas": 8.0, "victorias": 5.0, "derrotas": 3.0, "porcentaje_victorias": 62.5},
		{"juego": "mus", "jugadas": 4.0, "victorias": 2.0, "derrotas": 2.0, "porcentaje_victorias": 50.0},
		{"juego": "tute", "jugadas": 0.0, "victorias": 0.0, "derrotas": 0.0, "porcentaje_victorias": 0.0},
	]
	assert_eq(Textos.lineas_por_juego(por_juego), PackedStringArray([
		"Guiñote: 8 partidas · 5 victorias · 3 derrotas · 62,5 %",
		"Mus: 4 partidas · 2 victorias · 2 derrotas · 50 %",
	]))
	assert_eq(Textos.lineas_por_juego(null), PackedStringArray())


func test_rachas() -> void:
	assert_eq(Textos.rachas({"tipo": "victoria", "partidas": 3.0}, 4.0),
		"Racha: 3 victorias seguidas · Mejor racha: 4 victorias seguidas")
	assert_eq(Textos.rachas({"tipo": "derrota", "partidas": 2.0}, 1.0), "Racha: 2 derrotas seguidas · Mejor racha: 1 victoria")
	assert_eq(Textos.rachas({"tipo": "victoria", "partidas": 1.0}, 1.0), "Racha: 1 victoria · Mejor racha: 1 victoria")
	assert_eq(Textos.rachas({"tipo": "derrota", "partidas": 5.0}, 0.0), "Racha: 5 derrotas seguidas",
		"sin victorias no hay mejor racha")
	assert_eq(Textos.rachas({"tipo": null, "partidas": 0.0}, 0.0), "", "sin partidas no hay nada que decir")


func test_ultimos_resultados_como_letras_de_colores() -> void:
	var verde := Textos.COLOR_VICTORIA.to_html(false)
	var rojo := Textos.COLOR_DERROTA.to_html(false)
	assert_eq(Textos.ultimos_resultados(["victoria", "derrota", "victoria"]),
		"[color=#%s]V[/color] [color=#%s]D[/color] [color=#%s]V[/color]" % [verde, rojo, verde])
	assert_eq(Textos.ultimos_resultados([]), "")
	assert_eq(Textos.ultimos_resultados(null), "")
	assert_eq(Textos.ultimos_resultados(["victoria", 3, "empate"]), "[color=#%s]V[/color]" % verde,
		"lo que no es un resultado se ignora")
