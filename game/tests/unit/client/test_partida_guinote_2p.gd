extends GutTest
## Mesa de Guiñote a 2 jugadores (interfaz portada de game_javivi). No se
## prueba el arrastre real (eso es interacción de ratón de bajo nivel, fuera
## de alcance de GUT, igual que en el resto del cliente); sí que `actualizar`
## pinta bien la mano/mesa/mazo y que las acciones especiales y el resultado
## funcionan igual que en partida.gd (comparten AccionesGuinote).

const PARTIDA_2P := preload("res://client/ui/partida_guinote_2p/partida_guinote_2p.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")

var red
var partida

const ESTADO_EJEMPLO := {
	"fase": "robo",
	"turno": 1,
	"palo_triunfo": "oros",
	"pinta": "oros_5",
	"cartas_en_mazo": 10,
	"mi_mano": ["oros_1", "copas_12", "bastos_10"],
	"baza_actual": [{"jugador_id": 0, "carta_id": "espadas_3"}],
	"ultima_baza": {},
	"bazas_por_equipo": [1, 0],
	"bazas_jugadas": 1,
	"cantes": [],
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

	partida = PARTIDA_2P.instantiate()
	partida.red = red
	add_child_autofree(partida)
	await wait_frames(1)


func _tapete() -> Control:
	return partida.find_child("TapeteGuinote", true, false)


func _acciones() -> HBoxContainer:
	return partida.find_child("AccionesEspeciales", true, false)


func test_pinta_una_carta_por_cada_carta_de_la_mano() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_eq(_tapete().cartas_en_mano.size(), 3)


func test_solo_las_cartas_jugables_quedan_sin_bloquear() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	var cartas: Array = _tapete().cartas_en_mano
	# mi_mano = [oros_1, copas_12, bastos_10]; solo oros_1 está en jugadas_validas.
	assert_false(cartas[0].bloqueada, "oros_1 es jugable")
	assert_true(cartas[1].bloqueada, "copas_12 no es jugable")
	assert_true(cartas[2].bloqueada, "bastos_10 no es jugable")


func test_jugar_carta_solicitada_por_el_tapete_envia_jugar_carta() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	_tapete().jugar_carta_solicitada.emit("oros_1")

	assert_true(red.llamadas.has(["enviar", MensajesRed.JUGAR_CARTA, {"carta_id": "oros_1"}]))


func test_pinta_un_boton_por_cada_jugada_especial_distinta() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_eq(_acciones().get_child_count(), 1)
	assert_eq((_acciones().get_child(0) as Button).text, "Cantar copas")


func test_pulsar_una_accion_especial_envia_el_payload_sin_el_tipo() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	(_acciones().get_child(0) as Button).pressed.emit()

	assert_true(red.llamadas.has(["enviar", MensajesRed.CANTAR, {"palo": "copas"}]))


## tu_posicion = 1: la carta de la baza (jugador_id 0) es del rival.
func test_pinta_la_carta_de_la_baza_del_lado_del_rival() -> void:
	partida._renderizar_estado(ESTADO_EJEMPLO)

	assert_not_null(_tapete()._carta_oponente_en_mesa)
	assert_null(_tapete()._carta_en_mesa)


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
	var partida2 = PARTIDA_2P.instantiate()
	partida2.red = red2
	add_child_autofree(partida2)
	await wait_frames(1)

	assert_eq(partida2.find_child("TapeteGuinote", true, false).cartas_en_mano.size(), 3)
