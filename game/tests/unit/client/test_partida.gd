extends GutTest
## Pinta el estado_partida y deja hacer las jugadas de jugadas_validas. No se
## prueba la navegación al pulsar "Volver al lobby" (ver test_espera.gd).

const PARTIDA := preload("res://client/ui/partida/partida.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")

var red
var partida

const ESTADO_EJEMPLO := {
	"fase": "robo",
	"dador": 0,
	"turno": 1,
	"palo_triunfo": "oros",
	"pinta": "oros_5",
	"cartas_en_mazo": 10,
	"mi_mano": ["oros_1", "copas_12", "bastos_10"],
	"cartas_por_jugador": [3, 3, 3, 3],
	"baza_actual": [{"jugador_id": 0, "carta_id": "espadas_3"}],
	"ultima_baza": {},
	"bazas_por_equipo": [1, 0],
	"bazas_jugadas": 1,
	"cantes": [],
	"tute": {},
	"esperando_cambio_siete": -1,
	"mano": "idas",
	"tanteo_idas": [],
	"jugadas_validas": [
		{"tipo": "jugar_carta", "carta_id": "oros_1"},
		{"tipo": "cantar", "palo": "copas"},
	],
}


func before_each() -> void:
	red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": "guinote", "tu_posicion": 1, "jugadores": []}
	add_child_autofree(red)

	partida = PARTIDA.instantiate()
	partida.red = red
	add_child_autofree(partida)
	await wait_frames(1)


func _mano() -> HBoxContainer:
	return partida.find_child("ManoJugador", true, false)


func _acciones() -> HBoxContainer:
	return partida.find_child("AccionesEspeciales", true, false)


func _baza() -> HBoxContainer:
	return partida.find_child("BazaActual", true, false)


func test_pinta_una_carta_por_cada_carta_de_la_mano() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_eq(_mano().get_child_count(), 3)


func test_solo_habilita_los_botones_de_cartas_jugables() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	var botones: Array = _mano().get_children().map(func(c): return c.get_child(0))
	# mi_mano = [oros_1, copas_12, bastos_10]; solo oros_1 está en jugadas_validas.
	assert_false(botones[0].disabled, "oros_1 es jugable")
	assert_true(botones[1].disabled, "copas_12 no es jugable")
	assert_true(botones[2].disabled, "bastos_10 no es jugable")


func test_pulsar_una_carta_jugable_envia_jugar_carta() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	var boton: TextureButton = _mano().get_child(0).get_child(0)
	boton.pressed.emit()

	assert_true(red.llamadas.has(["enviar", MensajesRed.JUGAR_CARTA, {"carta_id": "oros_1"}]))


func test_pinta_un_boton_por_cada_jugada_especial_distinta() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_eq(_acciones().get_child_count(), 1)
	assert_eq((_acciones().get_child(0) as Button).text, "Cantar copas")


func test_pulsar_una_accion_especial_envia_el_payload_sin_el_tipo() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	(_acciones().get_child(0) as Button).pressed.emit()

	assert_true(red.llamadas.has(["enviar", MensajesRed.CANTAR, {"palo": "copas"}]))


func test_pinta_las_cartas_de_la_baza_actual() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_eq(_baza().get_child_count(), 1)


func test_un_error_del_servidor_se_muestra() -> void:
	red.error_recibido.emit("Jugada no válida")

	assert_eq(partida.find_child("EtiquetaError", true, false).text, "Jugada no válida")


func test_partida_terminada_muestra_el_resultado() -> void:
	red.partida_terminada.emit({"equipo_ganador": 1, "puntos_por_equipo": [40, 101], "motivo": "tantos"})

	assert_true(partida.find_child("PanelResultado", true, false).visible)
	var texto: String = partida.find_child("EtiquetaResultado", true, false).text
	assert_string_contains(texto, "Has ganado")


func test_estado_ya_disponible_al_crear_la_pantalla_se_pinta_sin_esperar_senales() -> void:
	var red2 = ClienteRedFalso.new()
	red2.config = {"tu_posicion": 1}
	red2.ultimo_estado = ESTADO_EJEMPLO
	add_child_autofree(red2)
	var partida2 = PARTIDA.instantiate()
	partida2.red = red2
	add_child_autofree(partida2)
	await wait_frames(1)

	assert_eq(partida2.find_child("ManoJugador", true, false).get_child_count(), 3)
