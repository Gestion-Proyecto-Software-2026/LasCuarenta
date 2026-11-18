extends GutTest
## Chat de la mesa (PBI-08): pinta los mensajes con el nombre y el color de la
## pareja de cada jugador, envía con Enter o con el botón, no deja colar BBCode,
## ofrece denunciar solo los mensajes de los rivales y enseña la denuncia
## pendiente con los botones para responder solo a la parte denunciada.

const ChatMesa := preload("res://client/ui/mesa/chat_mesa.gd")
const Tapete := preload("res://client/ui/mesa/tapete_mesa.gd")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")

const JUGADORES_4 := [
	{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
	{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis"},
	{"usuario_id": "u2", "posicion": 2, "equipo": 0, "nombre": "Marta"},
	{"usuario_id": "u3", "posicion": 3, "equipo": 1, "nombre": "Pablo"},
]
const JUGADORES_2 := [
	{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
	{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis"},
]

var red
var chat: Control


func _abrir(mi_asiento := 0, jugadores: Array = JUGADORES_4, mensajes: Array = []) -> void:
	red = ClienteRedFalso.new()
	red.chat = mensajes
	add_child_autofree(red)
	chat = ChatMesa.new()
	chat.red = red
	add_child_autofree(chat)
	chat.configurar(jugadores, mi_asiento)
	await wait_frames(1)


static func _mensaje(id: int, posicion: int, texto: String, durante_partida := true) -> Dictionary:
	return {"id": id, "usuario_id": "u%d" % posicion, "posicion": posicion, "equipo": posicion % 2,
		"nombre": JUGADORES_4[posicion]["nombre"], "mensaje": texto, "durante_partida": durante_partida}


func _llega(mensaje: Dictionary) -> void:
	red.chat.append(mensaje)
	red.chat_recibido.emit(mensaje)


func _denuncia(estado: String, cambios := {}) -> Dictionary:
	var denuncia := {"estado": estado, "mensaje_id": 1, "mensaje": "tengo el as", "denunciante": 0,
		"denunciado": 1, "equipo_denunciado": 1, "segundos": 60.0, "respondido_por": -1}
	denuncia.merge(cambios, true)
	red.denuncia = denuncia if estado == "pendiente" else {}
	red.denuncia_actualizada.emit(denuncia)
	return denuncia


func _enviados(tipo: String) -> Array:
	return red.llamadas.filter(func(l: Array) -> bool: return l[0] == "enviar" and l[1] == tipo)


# --- Mensajes ---

func test_pinta_el_historial_que_ya_habia_al_abrir_la_mesa() -> void:
	await _abrir(0, JUGADORES_4, [_mensaje(1, 1, "hola"), _mensaje(2, 2, "qué tal")])
	assert_eq(chat.texto_visible().split("\n").size(), 2)
	assert_string_contains(chat.texto_visible(), "J2 · Luis: hola")
	assert_string_contains(chat.texto_visible(), "J3 · Marta: qué tal")


func test_cada_mensaje_lleva_el_nombre_y_el_color_de_su_pareja() -> void:
	await _abrir()
	_llega(_mensaje(1, 1, "de Luis"))
	_llega(_mensaje(2, 0, "mío"))
	var bbcode: String = chat.historial.text
	assert_string_contains(bbcode, "[color=#%s][b]J2 · Luis[/b][/color]: de Luis" % Tapete.COLOR_PAREJA[1].to_html(false))
	assert_string_contains(bbcode, "[color=#%s][b]J1 · Ana (tú)[/b][/color]: mío" % Tapete.COLOR_PAREJA[0].to_html(false))


func test_sin_nombre_sale_el_asiento() -> void:
	await _abrir()
	var mensaje := _mensaje(1, 3, "anónimo")
	mensaje["nombre"] = ""
	_llega(mensaje)
	assert_string_contains(chat.texto_visible(), "J4: anónimo")


func test_no_se_puede_colar_bbcode() -> void:
	await _abrir()
	var mensaje := _mensaje(1, 1, "[url=denunciar:1]pincha[/url] [color=red]rojo[/color] [img]x.png[/img]")
	mensaje["nombre"] = "[b]Luis"
	_llega(mensaje)
	assert_string_contains(chat.texto_visible(), "[url=denunciar:1]pincha[/url] [color=red]rojo[/color] [img]x.png[/img]")
	assert_string_contains(chat.texto_visible(), "J2 · [b]Luis")
	assert_eq(ChatMesa.escapar("a[b]c"), "a[lb]b]c")


func test_chat_historial_sustituye_lo_que_habia() -> void:
	await _abrir(0, JUGADORES_4, [_mensaje(1, 1, "viejo")])
	red.chat = [_mensaje(1, 1, "uno"), _mensaje(2, 3, "dos")]
	red.chat_reiniciado.emit(red.chat)
	assert_false(chat.texto_visible().contains("viejo"))
	assert_eq(chat.texto_visible().split("\n").size(), 2)


# --- Enviar ---

func test_envia_con_enter_y_vacia_el_campo() -> void:
	await _abrir()
	chat.campo.text = "  ¡vamos!  "
	chat.campo.text_submitted.emit(chat.campo.text)
	assert_eq(_enviados(MensajesRed.CHAT_ENVIAR), [["enviar", MensajesRed.CHAT_ENVIAR, {"mensaje": "¡vamos!"}]])
	assert_eq(chat.campo.text, "")


func test_envia_con_el_boton() -> void:
	await _abrir()
	chat.campo.text = "con el botón"
	chat.boton_enviar.pressed.emit()
	assert_eq(_enviados(MensajesRed.CHAT_ENVIAR).size(), 1)
	assert_eq(_enviados(MensajesRed.CHAT_ENVIAR)[0][2]["mensaje"], "con el botón")


func test_no_envia_mensajes_vacios_y_limita_a_500() -> void:
	await _abrir()
	chat.campo.text = "    "
	chat.boton_enviar.pressed.emit()
	assert_eq(_enviados(MensajesRed.CHAT_ENVIAR).size(), 0)
	assert_eq(chat.campo.max_length, 500)


# --- Minimizar ---

func test_minimizado_cuenta_los_no_leidos() -> void:
	await _abrir()
	chat.boton_minimizar.pressed.emit()
	assert_true(chat.esta_minimizado())
	assert_true(chat.boton_abrir.visible)
	_llega(_mensaje(1, 1, "uno"))
	_llega(_mensaje(2, 2, "dos"))
	assert_eq(chat.boton_abrir.text, "Chat (2)")
	chat.boton_abrir.pressed.emit()
	assert_false(chat.esta_minimizado())
	assert_eq(chat.no_leidos, 0)
	assert_string_contains(chat.texto_visible(), "dos", "los mensajes siguen ahí")


# --- Denunciar ---

func test_solo_se_ofrece_denunciar_mensajes_de_rivales_escritos_durante_la_partida() -> void:
	await _abrir(0)
	_llega(_mensaje(1, 1, "rival"))
	_llega(_mensaje(2, 2, "compañera"))
	_llega(_mensaje(3, 0, "mío"))
	_llega(_mensaje(4, 3, "rival antes de empezar", false))
	var bbcode: String = chat.historial.text
	assert_string_contains(bbcode, "[url=denunciar:1]")
	for id in [2, 3, 4]:
		assert_false(bbcode.contains("[url=denunciar:%d]" % id), "mensaje %d" % id)


func test_denunciar_pide_confirmacion_y_manda_la_denuncia() -> void:
	await _abrir(0)
	_llega(_mensaje(1, 1, "tengo el as"))
	chat.historial.meta_clicked.emit("denunciar:1")
	assert_true(chat.dialogo_denuncia.visible, "pide confirmación")
	assert_eq(_enviados(MensajesRed.DENUNCIAR_CHAT).size(), 0)
	chat.dialogo_denuncia.confirmed.emit()
	assert_eq(_enviados(MensajesRed.DENUNCIAR_CHAT), [["enviar", MensajesRed.DENUNCIAR_CHAT, {"mensaje_id": 1}]])
	chat.dialogo_denuncia.hide()


func test_con_una_denuncia_pendiente_la_parte_denunciada_puede_responder() -> void:
	await _abrir(3)  # Pablo, compañero de Luis
	_llega(_mensaje(1, 1, "tengo el as"))
	chat.minimizar()
	_denuncia("pendiente")
	assert_false(chat.esta_minimizado(), "se abre el chat para verla")
	assert_true(chat.panel_denuncia.visible)
	assert_string_contains(chat.texto_denuncia.text, "Ana ha denunciado este mensaje de Luis")
	assert_string_contains(chat.texto_denuncia.text, "tengo el as")
	assert_string_contains(chat.cuenta_denuncia.text, "60 s")
	assert_true(chat.boton_admitir.visible)
	assert_true(chat.boton_no_admitir.visible)
	assert_false(chat.historial.text.contains("[url="), "en pausa no se ofrece denunciar")
	chat.boton_admitir.pressed.emit()
	assert_eq(_enviados(MensajesRed.ADMITIR_DENUNCIA).size(), 1)
	assert_true(chat.boton_admitir.disabled, "una sola respuesta")
	assert_true(chat.boton_no_admitir.disabled)


func test_la_parte_perjudicada_solo_espera() -> void:
	await _abrir(2)  # Marta, compañera de quien denuncia
	_denuncia("pendiente")
	assert_true(chat.panel_denuncia.visible)
	assert_false(chat.boton_admitir.visible)
	assert_false(chat.boton_no_admitir.visible)
	assert_string_contains(chat.texto_denuncia.text, "Esperando la respuesta de la pareja B (Luis y Pablo)")


func test_no_admitir_desde_el_panel() -> void:
	await _abrir(1)
	_denuncia("pendiente")
	chat.boton_no_admitir.pressed.emit()
	assert_eq(_enviados(MensajesRed.NO_ADMITIR_DENUNCIA).size(), 1)


func test_al_resolverse_se_oculta_y_queda_escrito() -> void:
	await _abrir(0)
	_llega(_mensaje(1, 1, "tengo el as"))
	_denuncia("pendiente")
	_denuncia("no_admitida", {"respondido_por": 3})
	assert_false(chat.panel_denuncia.visible)
	assert_string_contains(chat.texto_visible(), "Pablo no admite la denuncia: sigue la partida.")
	assert_false(chat.historial.text.contains("[url=denunciar:1]"), "ya denunciado: no se ofrece otra vez")
	_llega(_mensaje(2, 3, "otro"))
	assert_string_contains(chat.historial.text, "[url=denunciar:2]", "los demás sí")
	_denuncia("caducada", {"mensaje_id": 2})
	assert_string_contains(chat.texto_visible(), "Nadie ha admitido la denuncia en un minuto")
	_denuncia("admitida", {"mensaje_id": 3, "respondido_por": 1})
	assert_string_contains(chat.texto_visible(), "Denuncia admitida: gana la pareja A (Ana y Marta) por renuncio.")


func test_mus_a_dos() -> void:
	await _abrir(1, JUGADORES_2)
	_denuncia("pendiente")
	assert_true(chat.boton_admitir.visible, "el autor responde solo")
	assert_string_contains(chat.texto_denuncia.text, "¿Lo admites? Si lo admites, gana tu rival.")


func test_tras_la_partida_se_sigue_chateando_sin_denuncias() -> void:
	await _abrir(0)
	_llega(_mensaje(1, 1, "durante"))
	chat.marcar_terminada()
	assert_false(chat.historial.text.contains("[url="))
	chat.campo.text = "¡buena partida!"
	chat.boton_enviar.pressed.emit()
	assert_eq(_enviados(MensajesRed.CHAT_ENVIAR).size(), 1)


func test_abajo_a_la_izquierda() -> void:
	await _abrir()
	var alto := chat.get_viewport_rect().size.y
	assert_eq(chat.position.x, ChatMesa.MARGEN)
	assert_almost_eq(chat.position.y + chat.size.y, alto - ChatMesa.MARGEN, 0.5)
	assert_eq(chat.size, ChatMesa.TAMANO)
