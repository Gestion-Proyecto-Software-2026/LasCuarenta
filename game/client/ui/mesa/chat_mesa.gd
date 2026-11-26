extends Control
## Chat de la mesa (PBI-08): el historial desplazable de la partida y un campo
## para escribir, que se envía con Enter o con el botón. Cada mensaje sale con
## la etiqueta del jugador ("J2 · Luis") y el color de su pareja, los mismos de
## su etiqueta en la mesa (tapete_mesa.gd). La crea partida_mesa.gd.
##
## Revelar cartas o hacer señas por el chat es renuncio (HU-036): junto a los
## mensajes de los rivales hay un enlace para denunciarlos. Mientras la denuncia
## está pendiente se enseña aquí, con su cuenta atrás y, si eres de la parte
## denunciada, los botones para admitirla o no. Lo decide todo el servidor; aquí
## solo se pinta lo que manda (chat_mensaje, chat_historial, denuncia_chat).
##
## En la cabecera (y junto a "Chat" con el chat minimizado) está también el
## botón de los ajustes del cliente (PBI-21), para no llenar la mesa de botones
## sueltos: este chat solo avisa con [signal ajustes_pulsado] y el panel lo
## abre partida_mesa.gd.

## El jugador quiere abrir los ajustes (sonido...).
signal ajustes_pulsado

const Tapete := preload("res://client/ui/mesa/tapete_mesa.gd")
const Textos := preload("res://client/ui/mesa/textos_mesa.gd")

## Abajo a la izquierda, sin tapar la etiqueta del jugador de la izquierda (que
## en la ventana base de 1152×648 acaba hacia y = 414) ni casi la mano.
const TAMANO := Vector2(270, 220)
const MARGEN := 10.0
const MAX_CARACTERES := 500
const AVISO_POLITICA := "No reveles tus cartas ni hagas señas: es renuncio y los rivales pueden denunciarlo."
const COLOR_SISTEMA := Color(0.95, 0.82, 0.45)
const COLOR_ENLACE := Color(0.78, 0.78, 0.78)
const PREFIJO_DENUNCIAR := "denunciar:"

## Inyectable en tests (doble), igual que en el resto de pantallas.
var red

var historial: RichTextLabel
var campo: LineEdit
var boton_enviar: Button
var boton_minimizar: Button
## Lo único que se ve con el chat minimizado: "Chat (3)" con los no leídos.
var boton_abrir: Button
## "Ajustes" en la cabecera del chat y, con el chat minimizado, junto a "Chat".
var boton_ajustes: Button
var boton_ajustes_minimizado: Button
var panel_denuncia: PanelContainer
var texto_denuncia: Label
var cuenta_denuncia: Label
var boton_admitir: Button
var boton_no_admitir: Button
var dialogo_denuncia: ConfirmationDialog
var no_leidos := 0

var _panel: PanelContainer
## Lo que se pinta en el historial, en orden: { "mensaje": {...} } o { "sistema": "..." }.
var _entradas: Array[Dictionary] = []
var _nombres: Array = []  # nombre de cada asiento ("" si no se sabe)
var _mi_asiento := -1
var _terminada := false
var _denunciados: Dictionary = {}  # mensaje_id -> true
var _id_a_denunciar := -1
## Time.get_ticks_msec() en que se acaba el plazo de la denuncia pendiente; -1 si no hay.
var _fin_denuncia_ms := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 110
	_construir()
	get_viewport().size_changed.connect(_colocar)
	_colocar()


## Llamar después de add_child. [param jugadores] es el de `partida_iniciada`
## ([code][{ usuario_id, posicion, equipo, nombre }][/code]).
func configurar(jugadores: Array, mi_asiento: int) -> void:
	_mi_asiento = mi_asiento
	_nombres = []
	for jugador: Variant in jugadores:
		if jugador is Dictionary:
			_nombres.append(str(jugador.get("nombre", "")))
	if not red.chat_recibido.is_connected(_on_chat_recibido):
		red.chat_recibido.connect(_on_chat_recibido)
		red.chat_reiniciado.connect(_on_chat_reiniciado)
		red.denuncia_actualizada.connect(_on_denuncia_actualizada)
	_on_chat_reiniciado(red.chat)
	if not red.denuncia.is_empty():
		_on_denuncia_actualizada(red.denuncia)


## La partida ha acabado: el chat sigue (HU-035, CA-131), pero ya no se denuncia.
func marcar_terminada() -> void:
	_terminada = true
	_ocultar_denuncia()
	_pintar()


func minimizar() -> void:
	_panel.hide()
	boton_abrir.show()
	boton_ajustes_minimizado.show()
	_actualizar_boton_abrir()


func abrir() -> void:
	no_leidos = 0
	boton_abrir.hide()
	boton_ajustes_minimizado.hide()
	_panel.show()


func esta_minimizado() -> bool:
	return not _panel.visible


## El historial sin BBCode, tal como se lee en pantalla.
func texto_visible() -> String:
	return historial.get_parsed_text()


## Pide confirmación para denunciar el mensaje [param mensaje_id]; si se
## confirma, se manda la denuncia al servidor.
func denunciar(mensaje_id: int) -> void:
	var mensaje := _mensaje(mensaje_id)
	if mensaje.is_empty() or not _se_puede_denunciar(mensaje):
		return
	_id_a_denunciar = mensaje_id
	dialogo_denuncia.dialog_text = ("¿Denunciar este mensaje de %s por revelar cartas o hacer señas?\n«%s»\n\n"
		+ "La partida se pausará hasta un minuto para que su parte lo admita.") % [
			Textos.nombre_jugador(int(mensaje.get("posicion", -1)), _nombres), mensaje.get("mensaje", "")]
	dialogo_denuncia.popup_centered()


func _process(_delta: float) -> void:
	if _fin_denuncia_ms >= 0:
		_refrescar_cuenta_denuncia()


# --- Lo que manda el servidor ---

func _on_chat_recibido(mensaje: Dictionary) -> void:
	_entradas.append({"mensaje": mensaje})
	if esta_minimizado():
		no_leidos += 1
		_actualizar_boton_abrir()
	_pintar()


func _on_chat_reiniciado(mensajes: Array) -> void:
	_entradas.clear()
	for mensaje: Variant in mensajes:
		if mensaje is Dictionary:
			_entradas.append({"mensaje": mensaje})
	_pintar()


func _on_denuncia_actualizada(denuncia: Dictionary) -> void:
	var estado: String = str(denuncia.get("estado", ""))
	var id: Variant = denuncia.get("mensaje_id")
	if id is int or id is float:
		_denunciados[int(id)] = true
	if estado == "pendiente":
		_mostrar_denuncia(denuncia)
	else:
		_ocultar_denuncia()
		var linea := _texto_resolucion(denuncia)
		if not linea.is_empty():
			_entradas.append({"sistema": linea})
	_pintar()


# --- Lo que hace el jugador ---

func _enviar() -> void:
	var texto := campo.text.strip_edges()
	if texto.is_empty():
		return
	red.enviar(MensajesRed.CHAT_ENVIAR, {"mensaje": texto.left(MAX_CARACTERES)})
	campo.clear()
	campo.grab_focus()


func _on_texto_enviado(_texto: String) -> void:
	_enviar()


func _on_meta_pulsada(meta: Variant) -> void:
	var texto := str(meta)
	if texto.begins_with(PREFIJO_DENUNCIAR) and texto.trim_prefix(PREFIJO_DENUNCIAR).is_valid_int():
		denunciar(texto.trim_prefix(PREFIJO_DENUNCIAR).to_int())


func _on_denuncia_confirmada() -> void:
	if _id_a_denunciar >= 0:
		red.enviar(MensajesRed.DENUNCIAR_CHAT, {"mensaje_id": _id_a_denunciar})
	_id_a_denunciar = -1


func _responder(admite: bool) -> void:
	# Una sola respuesta: hasta que el servidor la resuelva, no se puede repetir.
	boton_admitir.disabled = true
	boton_no_admitir.disabled = true
	red.enviar(MensajesRed.ADMITIR_DENUNCIA if admite else MensajesRed.NO_ADMITIR_DENUNCIA, {})


# --- Pintar ---

func _pintar() -> void:
	var lineas := PackedStringArray()
	for entrada: Dictionary in _entradas:
		if entrada.has("sistema"):
			lineas.append("[color=#%s][i]%s[/i][/color]" % [COLOR_SISTEMA.to_html(false), escapar(entrada["sistema"])])
		else:
			lineas.append(_linea_mensaje(entrada["mensaje"]))
	historial.text = "\n".join(lineas)


func _linea_mensaje(mensaje: Dictionary) -> String:
	var posicion := int(mensaje.get("posicion", -1))
	var etiqueta := etiqueta_de(posicion, str(mensaje.get("nombre", "")))
	if posicion == _mi_asiento:
		etiqueta += " (tú)"
	var color: Color = Tapete.COLOR_PAREJA[posicion % 2] if posicion >= 0 else COLOR_SISTEMA
	var linea := "[color=#%s][b]%s[/b][/color]: %s" % [color.to_html(false), escapar(etiqueta), escapar(str(mensaje.get("mensaje", "")))]
	if _se_puede_denunciar(mensaje):
		linea += " [url=%s%d][color=#%s][i]denunciar[/i][/color][/url]" % [
			PREFIJO_DENUNCIAR, int(mensaje.get("id", -1)), COLOR_ENLACE.to_html(false)]
	return linea


## "J2 · Luis" como la etiqueta de la mesa, o "J2" si no se sabe el nombre.
static func etiqueta_de(posicion: int, nombre: String) -> String:
	var abreviatura := "J%d" % (posicion + 1)
	return abreviatura if nombre.is_empty() else "%s · %s" % [abreviatura, nombre]


## El texto tal cual, sin que nadie pueda colar BBCode (enlaces, colores,
## imágenes...) en el chat de los demás.
static func escapar(texto: String) -> String:
	return texto.replace("[", "[lb]")


## Mensaje de un rival escrito durante la partida, sin denunciar todavía, con la
## partida en juego y sin otra denuncia pendiente: el servidor lo vuelve a
## comprobar todo, esto solo decide si se ofrece el enlace.
func _se_puede_denunciar(mensaje: Dictionary) -> bool:
	var posicion := int(mensaje.get("posicion", -1))
	return not _terminada and _mi_asiento >= 0 and posicion >= 0 \
		and red.denuncia.is_empty() and bool(mensaje.get("durante_partida", false)) \
		and posicion % 2 != _mi_asiento % 2 and not _denunciados.has(int(mensaje.get("id", -1)))


func _mensaje(mensaje_id: int) -> Dictionary:
	for entrada: Dictionary in _entradas:
		if entrada.has("mensaje") and int(entrada["mensaje"].get("id", -1)) == mensaje_id:
			return entrada["mensaje"]
	return {}


func _mostrar_denuncia(denuncia: Dictionary) -> void:
	abrir()
	var denunciante := Textos.nombre_jugador(int(denuncia.get("denunciante", -1)), _nombres)
	var denunciado := Textos.nombre_jugador(int(denuncia.get("denunciado", -1)), _nombres)
	var equipo_denunciado := int(denuncia.get("equipo_denunciado", -1))
	var texto := "Partida en pausa. %s ha denunciado este mensaje de %s:\n«%s»" % [
		denunciante, denunciado, denuncia.get("mensaje", "")]
	var me_toca := _mi_asiento >= 0 and _mi_asiento % 2 == equipo_denunciado
	if me_toca:
		texto += "\n¿Lo admitís? Si lo admitís, gana la parte rival." if _nombres.size() == 4 \
			else "\n¿Lo admites? Si lo admites, gana tu rival."
	else:
		texto += "\nEsperando la respuesta de %s." % Textos.nombre_equipo(equipo_denunciado, _nombres)
	texto_denuncia.text = texto
	boton_admitir.visible = me_toca
	boton_no_admitir.visible = me_toca
	boton_admitir.disabled = false
	boton_no_admitir.disabled = false
	_fin_denuncia_ms = Time.get_ticks_msec() + int(float(denuncia.get("segundos", 0.0)) * 1000.0)
	_refrescar_cuenta_denuncia()
	panel_denuncia.show()


func _ocultar_denuncia() -> void:
	_fin_denuncia_ms = -1
	panel_denuncia.hide()


func _refrescar_cuenta_denuncia() -> void:
	var segundos := ceili(maxf(0.0, (_fin_denuncia_ms - Time.get_ticks_msec()) / 1000.0))
	cuenta_denuncia.text = "Quedan %d s para responder" % segundos


func _texto_resolucion(denuncia: Dictionary) -> String:
	var equipo_denunciado := int(denuncia.get("equipo_denunciado", -1))
	match denuncia.get("estado"):
		"admitida":
			return "Denuncia admitida: gana %s por renuncio." % Textos.nombre_equipo(1 - equipo_denunciado, _nombres)
		"no_admitida":
			return "%s no admite la denuncia: sigue la partida." % Textos.nombre_jugador(
				int(denuncia.get("respondido_por", denuncia.get("denunciado", -1))), _nombres)
		"caducada":
			return "Nadie ha admitido la denuncia en un minuto: sigue la partida."
	return ""


func _actualizar_boton_abrir() -> void:
	boton_abrir.text = "Chat (%d)" % no_leidos if no_leidos > 0 else "Chat"


# --- Construcción y colocación ---

func _colocar() -> void:
	if not is_inside_tree():
		return
	size = TAMANO
	position = Vector2(MARGEN, get_viewport_rect().size.y - MARGEN - TAMANO.y)


func _construir() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0, 0, 0, 0.62)
	estilo.set_corner_radius_all(10)
	estilo.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", estilo)
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 4)
	_panel.add_child(columna)

	var cabecera := HBoxContainer.new()
	columna.add_child(cabecera)
	var titulo := Label.new()
	titulo.text = "Chat de la mesa"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_font_size_override("font_size", 14)
	cabecera.add_child(titulo)
	boton_ajustes = _crear_boton_ajustes("BotonAjustes")
	boton_ajustes.add_theme_font_size_override("font_size", 12)
	cabecera.add_child(boton_ajustes)
	boton_minimizar = Button.new()
	boton_minimizar.name = "BotonMinimizar"
	boton_minimizar.text = "–"
	boton_minimizar.tooltip_text = "Minimizar el chat"
	boton_minimizar.focus_mode = Control.FOCUS_NONE
	boton_minimizar.pressed.connect(minimizar)
	cabecera.add_child(boton_minimizar)

	var politica := Label.new()
	politica.text = AVISO_POLITICA
	politica.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	politica.add_theme_font_size_override("font_size", 11)
	politica.modulate = Color(1, 1, 1, 0.7)
	columna.add_child(politica)

	panel_denuncia = PanelContainer.new()
	panel_denuncia.name = "PanelDenuncia"
	var estilo_denuncia := StyleBoxFlat.new()
	estilo_denuncia.bg_color = Color(0.35, 0.08, 0.06, 0.9)
	estilo_denuncia.border_color = COLOR_SISTEMA
	estilo_denuncia.set_border_width_all(2)
	estilo_denuncia.set_corner_radius_all(6)
	estilo_denuncia.set_content_margin_all(6)
	panel_denuncia.add_theme_stylebox_override("panel", estilo_denuncia)
	panel_denuncia.hide()
	columna.add_child(panel_denuncia)
	var caja_denuncia := VBoxContainer.new()
	panel_denuncia.add_child(caja_denuncia)
	texto_denuncia = Label.new()
	texto_denuncia.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texto_denuncia.add_theme_font_size_override("font_size", 12)
	caja_denuncia.add_child(texto_denuncia)
	cuenta_denuncia = Label.new()
	cuenta_denuncia.add_theme_font_size_override("font_size", 12)
	cuenta_denuncia.add_theme_color_override("font_color", COLOR_SISTEMA)
	caja_denuncia.add_child(cuenta_denuncia)
	var botones := HBoxContainer.new()
	caja_denuncia.add_child(botones)
	boton_admitir = Button.new()
	boton_admitir.name = "BotonAdmitir"
	boton_admitir.text = "Admitir renuncio"
	boton_admitir.pressed.connect(_responder.bind(true))
	botones.add_child(boton_admitir)
	boton_no_admitir = Button.new()
	boton_no_admitir.name = "BotonNoAdmitir"
	boton_no_admitir.text = "No admitir"
	boton_no_admitir.pressed.connect(_responder.bind(false))
	botones.add_child(boton_no_admitir)

	historial = RichTextLabel.new()
	historial.name = "Historial"
	historial.bbcode_enabled = true
	historial.scroll_following = true
	historial.selection_enabled = true
	historial.size_flags_vertical = Control.SIZE_EXPAND_FILL
	historial.add_theme_font_size_override("normal_font_size", 13)
	historial.add_theme_font_size_override("bold_font_size", 13)
	historial.add_theme_font_size_override("italics_font_size", 12)
	historial.meta_clicked.connect(_on_meta_pulsada)
	columna.add_child(historial)

	var fila := HBoxContainer.new()
	columna.add_child(fila)
	campo = LineEdit.new()
	campo.name = "Campo"
	campo.max_length = MAX_CARACTERES
	campo.placeholder_text = "Escribe un mensaje…"
	campo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tras enviar con Enter se sigue escribiendo sin volver a pulsar el campo.
	if "keep_editing_on_text_submit" in campo:
		campo.set("keep_editing_on_text_submit", true)
	campo.text_submitted.connect(_on_texto_enviado)
	fila.add_child(campo)
	boton_enviar = Button.new()
	boton_enviar.name = "BotonEnviar"
	boton_enviar.text = "Enviar"
	boton_enviar.focus_mode = Control.FOCUS_NONE
	boton_enviar.pressed.connect(_enviar)
	fila.add_child(boton_enviar)

	boton_abrir = Button.new()
	boton_abrir.name = "BotonAbrir"
	boton_abrir.text = "Chat"
	boton_abrir.focus_mode = Control.FOCUS_NONE
	boton_abrir.custom_minimum_size = Vector2(110, 34)
	boton_abrir.hide()
	boton_abrir.pressed.connect(abrir)
	add_child(boton_abrir)
	boton_abrir.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	boton_ajustes_minimizado = _crear_boton_ajustes("BotonAjustesMinimizado")
	boton_ajustes_minimizado.custom_minimum_size = Vector2(90, 34)
	boton_ajustes_minimizado.hide()
	add_child(boton_ajustes_minimizado)
	# A la derecha de "Chat", en la misma línea.
	boton_ajustes_minimizado.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	var hueco := boton_abrir.custom_minimum_size.x + 6.0
	boton_ajustes_minimizado.offset_left += hueco
	boton_ajustes_minimizado.offset_right += hueco

	dialogo_denuncia = ConfirmationDialog.new()
	dialogo_denuncia.name = "DialogoDenuncia"
	dialogo_denuncia.title = "Denunciar mensaje"
	dialogo_denuncia.ok_button_text = "Denunciar"
	dialogo_denuncia.cancel_button_text = "Cancelar"
	dialogo_denuncia.confirmed.connect(_on_denuncia_confirmada)
	add_child(dialogo_denuncia)


func _crear_boton_ajustes(nombre: String) -> Button:
	var boton := Button.new()
	boton.name = nombre
	boton.text = "Ajustes"
	boton.tooltip_text = "Ajustes del juego (sonido)"
	boton.focus_mode = Control.FOCUS_NONE
	boton.pressed.connect(ajustes_pulsado.emit)
	return boton
