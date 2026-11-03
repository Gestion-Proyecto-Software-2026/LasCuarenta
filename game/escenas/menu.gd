extends Control
## Menú de inicio: eliges uno de los 6 modos y pasas a la partida, donde se
## decide si esta ventana es el servidor o un jugador.
##
## Con el argumento modo=<id> (p. ej. "-- modo=tute_2v2") se salta el menú.

const ESCENA_PARTIDA := "res://escenas/partida.tscn"
const RUTA_FONDO := "res://data/Misc/tapete.png"
const JUEGOS := ["Guiñote", "Tute", "Mus"]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("modo="):
			var modo := Modos.buscar(arg.trim_prefix("modo="))
			if not modo.is_empty():
				_elegir.call_deferred(modo)
				return
	_construir()


func _construir() -> void:
	var fondo := TextureRect.new()
	fondo.texture = load(RUTA_FONDO)
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var columna := VBoxContainer.new()
	columna.alignment = BoxContainer.ALIGNMENT_CENTER
	columna.add_theme_constant_override("separation", 18)
	add_child(columna)
	columna.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	columna.add_child(_texto("LAS CUARENTA", 52))
	columna.add_child(_texto("Elige a qué jugar", 24))

	var rejilla := GridContainer.new()
	rejilla.columns = 3
	rejilla.add_theme_constant_override("h_separation", 18)
	rejilla.add_theme_constant_override("v_separation", 14)
	rejilla.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	columna.add_child(rejilla)

	rejilla.add_child(Control.new())
	rejilla.add_child(_texto("1 contra 1", 22))
	rejilla.add_child(_texto("Por parejas", 22))
	for nombre in JUEGOS:
		var etiqueta := _texto(nombre, 28)
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rejilla.add_child(etiqueta)
		for modo in Modos.LISTA:
			if modo["nombre"] == nombre:
				rejilla.add_child(_boton(modo))


func _boton(modo: Dictionary) -> Button:
	var boton := Button.new()
	boton.custom_minimum_size = Vector2(240, 64)
	boton.add_theme_font_size_override("font_size", 20)
	if Modos.disponible(modo):
		boton.text = "%d jugadores" % modo["jugadores"]
		boton.pressed.connect(_elegir.bind(modo))
	else:
		boton.text = "Próximamente"
		boton.disabled = true
	return boton


func _texto(texto: String, tam: int) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ajustes := LabelSettings.new()
	ajustes.font_size = tam
	ajustes.outline_size = 8
	ajustes.outline_color = Color.BLACK
	etiqueta.label_settings = ajustes
	return etiqueta


func _elegir(modo: Dictionary) -> void:
	Modos.elegido = modo
	get_tree().change_scene_to_file(ESCENA_PARTIDA)
