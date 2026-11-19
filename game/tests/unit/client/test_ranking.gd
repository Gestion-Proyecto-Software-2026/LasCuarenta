extends GutTest

const RANKING := preload("res://client/ui/ranking/ranking.tscn")
const ClienteApiFalso := preload("res://tests/unit/client/cliente_api_falso.gd")

const ANA := {"usuario_id": "u-ana", "nombre_visible": "Ana", "puntos_totales": 320, "partidas_jugadas": 3, "partidas_ganadas": 2, "posicion": 1}
const BEA := {"usuario_id": "u-bea", "nombre_visible": "Bea", "puntos_totales": 150, "partidas_jugadas": 3, "partidas_ganadas": 1, "posicion": 2}

var api
var pantalla


func before_each() -> void:
	api = ClienteApiFalso.new()
	api.usuario = {"id": "u-bea", "nombre_visible": "Bea"}
	api.respuesta_ranking = {"ok": true, "codigo": 200, "datos": [ANA, BEA]}
	add_child_autofree(api)
	pantalla = RANKING.instantiate()
	pantalla.api = api
	add_child_autofree(pantalla)
	await wait_process_frames(3)


func _lista() -> VBoxContainer:
	return pantalla.find_child("ListaRanking", true, false)


func _textos_fila(i: int) -> Array:
	return _lista().get_child(i).get_children().map(func(e): return e.text)


func test_carga_el_ranking_de_guinote_al_entrar() -> void:
	assert_eq(api.llamadas[0], ["obtener_ranking", "guinote"])


func test_pinta_las_filas_en_el_orden_del_backend() -> void:
	assert_eq(_lista().get_child_count(), 2)
	assert_eq(_textos_fila(0), ["1", "Ana", "3", "2", "320"])
	assert_eq(_textos_fila(1), ["2", "Bea", "3", "1", "150"])


func test_resalta_la_fila_del_usuario_conectado() -> void:
	var color_ana: Color = _lista().get_child(0).get_child(1).get_theme_color("font_color")
	var color_bea: Color = _lista().get_child(1).get_child(1).get_theme_color("font_color")
	assert_ne(color_ana, color_bea)
	assert_eq(color_bea, pantalla.COLOR_PROPIO)


func test_cambiar_de_juego_filtra_el_ranking() -> void:
	var selector: OptionButton = pantalla.find_child("SelectorJuego", true, false)

	selector.select(1)
	selector.item_selected.emit(1)
	await wait_process_frames(3)

	assert_eq(api.llamadas[-1], ["obtener_ranking", "mus"])


func test_todos_los_juegos_no_manda_filtro() -> void:
	var selector: OptionButton = pantalla.find_child("SelectorJuego", true, false)

	selector.select(2)
	selector.item_selected.emit(2)
	await wait_process_frames(3)

	assert_eq(api.llamadas[-1], ["obtener_ranking", ""])


func test_muestra_estado_vacio_sin_partidas() -> void:
	api.respuesta_ranking = {"ok": true, "codigo": 200, "datos": []}

	pantalla.find_child("BotonActualizar", true, false).pressed.emit()
	await wait_process_frames(3)

	assert_eq(_lista().get_child_count(), 0)
	assert_true(pantalla.find_child("EtiquetaVacia", true, false).visible)


func test_muestra_el_error_del_backend() -> void:
	api.respuesta_ranking = {"ok": false, "codigo": 400, "datos": {"error": "juego no válido"}}

	pantalla.find_child("BotonActualizar", true, false).pressed.emit()
	await wait_process_frames(3)

	var error: Label = pantalla.find_child("EtiquetaError", true, false)
	assert_true(error.visible)
	assert_eq(error.text, "juego no válido")
	assert_false(pantalla.find_child("EtiquetaVacia", true, false).visible)
