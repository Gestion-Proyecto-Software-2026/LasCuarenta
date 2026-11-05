class_name MesaMus
extends RefCounted
## Lo que la mesa (tapete.gd) solo hace en el Mus: el texto del lance en el
## centro, el marcador de piedras, los botones (mus, descartes, envites), elegir
## cartas para descartarse y el panel con las cartas de todos al acabar la mano.
## La mesa lo crea en configurar_mesa() cuando el juego es el Mus.

## Envites que se ofrecen como botón: el de 2 ("Envido"), el de 5 y el órdago.
## El motor admite de 2 a 10; para más, se sube varias veces.
const ENVITES_CON_BOTON := [2, 5]
const COLOR_ELEGIDA := Color(1.0, 0.85, 0.6)

## La mesa (tapete.gd). Sin tipo: se usan sus funciones propias.
var mesa
## Cartas de la mano (CartaEscene) elegidas para descartarse.
var seleccion: Array = []
var boton_descartar: Button

var _texto_centro: Label
var _panel_fin_mano: PanelContainer


func _init(p_mesa) -> void:
	mesa = p_mesa


## Con cada vista: botones, texto del centro y marcador.
func actualizar(vista: Dictionary, acciones: Array) -> void:
	if _panel_fin_mano:
		_panel_fin_mano.hide()
	if vista["fase"] != "descarte" or vista["turno"] != mesa._mi_asiento():
		elegir_para_descarte([])
	else:
		elegir_para_descarte(seleccion.filter(func(c): return mesa.cartas_en_mano.has(c)))
	var botones: Array = []
	var descarte_puesto := false
	for jugada: Dictionary in acciones:
		match jugada["tipo"]:
			MotorDeJuego.DESCARTAR:
				# Un solo botón: se descarta de las cartas elegidas en la mano.
				if not descarte_puesto:
					botones.append({"tipo": MotorDeJuego.DESCARTAR})
					descarte_puesto = true
			MotorDeJuego.ENVIDAR:
				if jugada["cantidad"] in ENVITES_CON_BOTON:
					botones.append(jugada)
			_:
				botones.append(jugada)
	mesa._mostrar_acciones(botones, acciones)

	if _texto_centro == null:
		_texto_centro = mesa._crear_texto(22)
		_texto_centro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mesa.add_child(_texto_centro)
	_texto_centro.text = "\n".join(_lineas_del_centro(vista))
	mesa._poner_marcador("Piedras: %s %d · %s %d\nJuegos: %d - %d (a %d piedras)\nEs mano %s" % [
		mesa._nombre_equipo(0), vista["piedras"][0], mesa._nombre_equipo(1), vista["piedras"][1],
		vista["juegos"][0], vista["juegos"][1], vista["piedras_por_juego"],
		mesa._abreviatura(mesa.asientos[vista["mano"]])])


## Qué se está jugando: la fase o el lance, el envite, quién tiene pares o
## juego y cuántas cartas pidió cada uno.
func _lineas_del_centro(vista: Dictionary) -> PackedStringArray:
	var lineas := PackedStringArray()
	match vista["fase"]:
		"mus":
			lineas.append("¿Mus?")
		"descarte":
			var mio: bool = vista["turno"] == mesa._mi_asiento()
			lineas.append("Descarte: elige las cartas que quieres cambiar" if mio else "Descartes")
		_:
			lineas.append("Lance: %s" % str(vista["lance"]).capitalize())
	var envite: Dictionary = vista.get("envite", {})
	if not envite.is_empty():
		var quien: String = mesa._nombre_equipo(envite["equipo"])
		lineas.append("¡Órdago de %s!" % quien if envite["ordago"] else "Envite de %s: %d piedras" % [quien, envite["apuesta"]])
	for clave in ["tienen_pares", "tienen_juego"]:
		if vista.get(clave) != null:
			var quienes := PackedStringArray()
			for asiento in mesa.asientos.size():
				quienes.append("%s %s" % [mesa._abreviatura(mesa.asientos[asiento]), "sí" if vista[clave][asiento] else "no"])
			lineas.append("%s: %s" % ["Pares" if clave == "tienen_pares" else "Juego", " · ".join(quienes)])
	if vista["rondas_de_descarte"] > 0 and vista["fase"] == "mus":
		var pedidas := PackedStringArray()
		for asiento in mesa.asientos.size():
			pedidas.append("%s %d" % [mesa._abreviatura(mesa.asientos[asiento]), vista["cartas_pedidas"][asiento]])
		lineas.append("Pidieron: " + " · ".join(pedidas))
	return lineas


func colocar() -> void:
	if _texto_centro:
		_texto_centro.reset_size()
		_texto_centro.position = mesa._centro_baza() - _texto_centro.size / 2.0


## Texto de los botones del Mus; "" si la jugada no es del Mus.
func texto_jugada(jugada: Dictionary) -> String:
	match jugada["tipo"]:
		MotorDeJuego.MUS:
			return "Mus"
		MotorDeJuego.NO_MUS:
			return "No hay mus"
		MotorDeJuego.DESCARTAR:
			return "Descartar"
		MotorDeJuego.PASAR:
			return "Paso"
		MotorDeJuego.ENVIDAR:
			var hay_envite := not (mesa._vista.get("envite", {}) as Dictionary).is_empty()
			return ("Subo %d" if hay_envite else "Envido %d") % jugada["cantidad"]
		MotorDeJuego.ORDAGO:
			return "¡Órdago!"
		MotorDeJuego.QUIERO:
			return "Quiero"
		MotorDeJuego.NO_QUIERO:
			return "No quiero"
	return ""


## Si [param jugada] es la de descartarse, le pone al botón su comportamiento
## (descartar lo elegido) y devuelve true.
func preparar_boton(boton: Button, jugada: Dictionary) -> bool:
	if jugada["tipo"] != MotorDeJuego.DESCARTAR:
		return false
	boton_descartar = boton
	boton.pressed.connect(_on_descartar_pulsado)
	_actualizar_boton_descartar()
	return true


# --- Descarte ---

func puedo_descartar() -> bool:
	return mesa._vista.get("fase") == "descarte" and mesa._vista.get("turno") == mesa._mi_asiento()


## Pulsar una carta durante tu descarte la marca o desmarca (sube un poco).
func alternar_descarte(carta) -> void:
	var elegidas := seleccion.duplicate()
	if elegidas.has(carta):
		elegidas.erase(carta)
	else:
		elegidas.append(carta)
	elegir_para_descarte(elegidas)


func elegir_para_descarte(cartas: Array) -> void:
	seleccion = cartas
	for carta in mesa.cartas_en_mano:
		carta.self_modulate = COLOR_ELEGIDA if cartas.has(carta) else Color.WHITE
	_actualizar_boton_descartar()
	mesa.reorganizar_mano()


func _actualizar_boton_descartar() -> void:
	if is_instance_valid(boton_descartar):
		boton_descartar.disabled = seleccion.is_empty()
		boton_descartar.text = "Elige cartas para descartar" if seleccion.is_empty() \
			else "Descartar %d" % seleccion.size()


func _on_descartar_pulsado() -> void:
	var ids: Array = seleccion.map(func(c): return c.id)
	elegir_para_descarte([])
	mesa._on_accion_pulsada({"tipo": MotorDeJuego.DESCARTAR, "cartas": ids})


# --- Autojugar ---

## Pide mus una vez, se descarta de lo que no son reyes ni ases, envida en
## Pares y Juego, y quiere los envites (o no, con no_cantar).
func jugada_automatica(acciones: Array) -> Dictionary:
	var vista: Dictionary = mesa._vista
	var tipos := acciones.map(func(j: Dictionary) -> String: return j["tipo"])
	if MotorDeJuego.MUS in tipos:
		return {"tipo": MotorDeJuego.MUS if vista["rondas_de_descarte"] == 0 else MotorDeJuego.NO_MUS}
	if MotorDeJuego.DESCARTAR in tipos:
		var mano: Array = vista["mi_mano"]
		var malas := mano.filter(func(id: String) -> bool:
			return Cartas.valor(id) not in [Cartas.REY, Cartas.TRES, Cartas.AS, Cartas.DOS])
		return {"tipo": MotorDeJuego.DESCARTAR, "cartas": malas if not malas.is_empty() else [mano[0]]}
	var con_jugada: bool = vista.get("lance") in ["pares", "juego"]
	var envite: Dictionary = vista.get("envite", {})
	if envite.is_empty():
		return {"tipo": MotorDeJuego.ENVIDAR, "cantidad": 2} if con_jugada else {"tipo": MotorDeJuego.PASAR}
	if con_jugada and not envite["ordago"] and envite["apuesta"] < 6:
		return {"tipo": MotorDeJuego.ENVIDAR, "cantidad": 2}
	return {"tipo": MotorDeJuego.QUIERO if mesa.autocantar else MotorDeJuego.NO_QUIERO}


# --- Fin de la mano ---

## Las cartas de todos, ya enseñadas, y lo que cobra cada pareja.
func mostrar_fin_de_mano(ultima: Dictionary) -> void:
	mesa._mostrar_acciones([])
	if _panel_fin_mano == null:
		_panel_fin_mano = PanelContainer.new()
		_panel_fin_mano.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.8)
		estilo.border_color = mesa.COLOR_TURNO
		estilo.set_border_width_all(2)
		estilo.set_corner_radius_all(12)
		estilo.set_content_margin_all(14)
		_panel_fin_mano.add_theme_stylebox_override("panel", estilo)
		_panel_fin_mano.z_index = 140
		mesa.add_child(_panel_fin_mano)
	for hijo in _panel_fin_mano.get_children():
		hijo.queue_free()
	var columna := VBoxContainer.new()
	_panel_fin_mano.add_child(columna)
	var titulo: Label = mesa._crear_texto(20)
	titulo.text = "Fin de la mano: se enseñan las cartas"
	columna.add_child(titulo)
	for asiento in ultima["manos"].size():
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 6)
		var nombre: Label = mesa._crear_texto(18)
		nombre.text = mesa._abreviatura(mesa.asientos[asiento])
		nombre.custom_minimum_size = Vector2(44, 0)
		nombre.label_settings.font_color = mesa.COLOR_PAREJA[asiento % 2]
		fila.add_child(nombre)
		for id: String in ultima["manos"][asiento]:
			var imagen := TextureRect.new()
			imagen.texture = (load("res://data/Cartas/%s.tres" % id) as Carta).imagen
			imagen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			imagen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			imagen.custom_minimum_size = Vector2(46, 70)
			fila.add_child(imagen)
		columna.add_child(fila)
	var cobros := PackedStringArray()
	for cobro: Dictionary in ultima["cobros"]:
		cobros.append("%s: %s +%d" % [str(cobro["lance"]).capitalize(), mesa._nombre_equipo(cobro["equipo"]), cobro["piedras"]])
	var texto: Label = mesa._crear_texto(16)
	texto.text = "\n".join(cobros) if not cobros.is_empty() else "Nadie cobra nada más."
	if ultima["juego_para"] != -1:
		texto.text += "\n¡Juego para %s!" % mesa._nombre_equipo(ultima["juego_para"])
	columna.add_child(texto)
	_panel_fin_mano.reset_size()
	_panel_fin_mano.position = mesa._centro_baza() - _panel_fin_mano.get_combined_minimum_size() / 2.0
	_panel_fin_mano.show()
