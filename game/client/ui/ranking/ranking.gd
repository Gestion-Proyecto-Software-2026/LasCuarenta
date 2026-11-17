extends Control
## Ranking público de jugadores (PBI-07): puntos acumulados por juego, tal como
## los devuelve GET /api/ranking (docs/analisis_funcional_app.md §5). El orden
## lo decide el backend; aquí solo se pinta.

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
const ESCENA_LOGIN := "res://client/ui/login/login.tscn"

## [texto visible, valor de ?juego=] — "" es "todos los juegos".
const FILTROS := [["Guiñote", "guinote"], ["Mus", "mus"], ["Todos los juegos", ""]]

const COLOR_TEXTO := Color(0.106, 0.086, 0.071, 1)
const COLOR_PROPIO := Color(0.643, 0.11, 0.122, 1)
const ANCHOS_COLUMNA := [48, 0, 80, 80, 80]

@onready var selector_juego: OptionButton = %SelectorJuego
@onready var etiqueta_error: Label = %EtiquetaError
@onready var etiqueta_vacia: Label = %EtiquetaVacia
@onready var lista_ranking: VBoxContainer = %ListaRanking
@onready var boton_actualizar: Button = %BotonActualizar
@onready var boton_volver: Button = %BotonVolver

## Por defecto el autoload; los tests de GUT lo sustituyen por un doble.
var api = ClienteApi


func _ready() -> void:
	for filtro in FILTROS:
		selector_juego.add_item(filtro[0])
	selector_juego.select(0)
	etiqueta_error.visible = false
	selector_juego.item_selected.connect(func(_i): refrescar())
	boton_actualizar.pressed.connect(refrescar)
	boton_volver.pressed.connect(_on_boton_volver_pressed)
	refrescar()


func juego_seleccionado() -> String:
	return FILTROS[selector_juego.selected][1]


func refrescar() -> void:
	etiqueta_error.visible = false
	_bloquear(true)
	var resultado: Dictionary = await api.obtener_ranking(juego_seleccionado())
	_bloquear(false)
	if resultado.ok and resultado.datos is Array:
		_pintar(resultado.datos)
	else:
		_pintar([])
		etiqueta_vacia.visible = false
		etiqueta_error.text = _mensaje_de(resultado)
		etiqueta_error.visible = true


func _pintar(entradas: Array) -> void:
	for fila in lista_ranking.get_children():
		lista_ranking.remove_child(fila)
		fila.queue_free()

	etiqueta_vacia.visible = entradas.is_empty()
	var mi_id: String = api.usuario.get("id", "") if api.usuario is Dictionary else ""
	for entrada in entradas:
		var propia: bool = not mi_id.is_empty() and entrada.get("usuario_id", "") == mi_id
		lista_ranking.add_child(_crear_fila([
			"%d" % int(entrada.get("posicion", 0)),
			str(entrada.get("nombre_visible", "")),
			"%d" % int(entrada.get("partidas_jugadas", 0)),
			"%d" % int(entrada.get("partidas_ganadas", 0)),
			"%d" % int(entrada.get("puntos_totales", 0)),
		], propia))


func _crear_fila(textos: Array, propia: bool) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	for i in textos.size():
		var etiqueta := Label.new()
		etiqueta.text = textos[i]
		etiqueta.add_theme_color_override("font_color", COLOR_PROPIO if propia else COLOR_TEXTO)
		etiqueta.add_theme_font_size_override("font_size", 16)
		if ANCHOS_COLUMNA[i] == 0:
			etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			etiqueta.clip_text = true
		else:
			etiqueta.custom_minimum_size.x = ANCHOS_COLUMNA[i]
			etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fila.add_child(etiqueta)
	return fila


func _on_boton_volver_pressed() -> void:
	var destino := ESCENA_LOBBY if api.esta_autenticado() else ESCENA_LOGIN
	get_tree().change_scene_to_file(destino)


func _mensaje_de(resultado: Dictionary) -> String:
	if resultado.datos is Dictionary:
		return resultado.datos.get("error", "No se pudo cargar el ranking")
	return "No se pudo conectar con el servidor"


func _bloquear(bloqueado: bool) -> void:
	selector_juego.disabled = bloqueado
	boton_actualizar.disabled = bloqueado
