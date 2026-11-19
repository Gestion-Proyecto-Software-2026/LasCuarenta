extends GutTest
## ChatSala (PBI-08): validación de los mensajes, ids, tope de mensajes y las
## reglas de las denuncias, sin red ni RoomManager.

const AHORA := 1000
const PLAZO_MS := int(ChatSala.SEGUNDOS_PARA_ADMITIR * 1000.0)

var chat: ChatSala


func before_each() -> void:
	chat = ChatSala.new()


# --- Validar y limpiar ---

func test_validar_acepta_hasta_500_caracteres() -> void:
	assert_eq(ChatSala.validar("hola"), "")
	assert_eq(ChatSala.validar("a".repeat(500)), "")
	assert_eq(ChatSala.validar("ñ".repeat(500)), "", "cuenta caracteres, no bytes")


func test_validar_rechaza_mas_de_500_caracteres() -> void:
	assert_eq(ChatSala.validar("a".repeat(501)), ChatSala.ERROR_LARGO)
	assert_eq(ChatSala.validar("a".repeat(100000)), ChatSala.ERROR_LARGO)


func test_los_espacios_de_los_extremos_no_cuentan() -> void:
	assert_eq(ChatSala.validar("  " + "a".repeat(500) + "  "), "")


func test_validar_rechaza_vacios_y_lo_que_no_es_texto() -> void:
	assert_eq(ChatSala.validar(""), ChatSala.ERROR_VACIO)
	assert_eq(ChatSala.validar("   \n\t "), ChatSala.ERROR_VACIO)
	assert_eq(ChatSala.validar(42), ChatSala.ERROR_NO_ES_TEXTO)
	assert_eq(ChatSala.validar(null), ChatSala.ERROR_NO_ES_TEXTO)
	assert_eq(ChatSala.validar(["hola"]), ChatSala.ERROR_NO_ES_TEXTO)


func test_limpiar_cambia_los_caracteres_de_control_por_espacios() -> void:
	# Sin el NUL: las cadenas de Godot no lo admiten, así que no llega por la red.
	assert_eq(ChatSala.limpiar("a\nb\tc\u0001d\u007fe"), "a b c d e")
	assert_eq(ChatSala.limpiar("\n  hola  \r\n"), "hola")


# --- Publicar ---

func test_publicar_da_ids_crecientes_y_la_identidad_del_remitente() -> void:
	var primero := chat.publicar(1, "u1", "Luis", "hola\n", true)
	var segundo := chat.publicar(2, "u2", "Marta", "qué tal", false)
	assert_eq(primero, {
		"id": 1, "usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis",
		"mensaje": "hola", "durante_partida": true,
	})
	assert_eq(segundo["id"], 2)
	assert_eq(segundo["equipo"], 0)
	assert_eq(chat.mensajes.size(), 2)


func test_se_guardan_como_mucho_500_mensajes() -> void:
	for i in ChatSala.MAX_MENSAJES + 3:
		chat.publicar(0, "u0", "Ana", "m%d" % i, true)
	assert_eq(chat.mensajes.size(), ChatSala.MAX_MENSAJES)
	assert_eq(chat.mensajes[0]["id"], 4, "se descartan los más antiguos")
	assert_eq(chat.mensajes.back()["id"], ChatSala.MAX_MENSAJES + 3)


# --- Denuncias ---

func _mensaje_de(posicion: int, durante_partida := true) -> int:
	return chat.publicar(posicion, "u%d" % posicion, "J%d" % posicion, "tengo el as", durante_partida)["id"]


func test_un_rival_denuncia_y_queda_pendiente() -> void:
	var id := _mensaje_de(1)
	assert_eq(chat.denunciar(id, 0, AHORA, true), "")
	assert_true(chat.hay_denuncia())
	assert_eq(chat.denuncia, {
		"mensaje_id": id, "mensaje": "tengo el as", "denunciante": 0, "denunciado": 1,
		"equipo_denunciado": 1, "limite_ms": AHORA + PLAZO_MS,
	})


func test_no_puede_denunciar_quien_es_del_mismo_equipo_ni_el_autor() -> void:
	var id := _mensaje_de(1)
	assert_eq(chat.denunciar(id, 3, AHORA, true), ChatSala.ERROR_NO_ES_RIVAL, "su compañero")
	assert_eq(chat.denunciar(id, 1, AHORA, true), ChatSala.ERROR_NO_ES_RIVAL, "él mismo")
	assert_false(chat.hay_denuncia())


func test_solo_con_la_partida_en_curso_y_mensajes_de_la_partida() -> void:
	var antes := _mensaje_de(1, false)
	var durante := _mensaje_de(1)
	assert_eq(chat.denunciar(durante, 0, AHORA, false), ChatSala.ERROR_SIN_PARTIDA)
	assert_eq(chat.denunciar(antes, 0, AHORA, true), ChatSala.ERROR_ANTES_DE_EMPEZAR)


func test_ids_que_no_existen_o_no_son_enteros() -> void:
	_mensaje_de(1)
	for id: Variant in [99, 0, -1, "1", null, 1.5]:
		assert_eq(chat.denunciar(id, 0, AHORA, true), ChatSala.ERROR_NO_EXISTE, str(id))
	assert_eq(chat.denunciar(1.0, 0, AHORA, true), "", "1.0 es el mensaje 1")


func test_una_denuncia_cada_vez_y_un_mensaje_solo_una_vez() -> void:
	var primero := _mensaje_de(1)
	var segundo := _mensaje_de(3)
	assert_eq(chat.denunciar(primero, 0, AHORA, true), "")
	assert_eq(chat.denunciar(segundo, 2, AHORA, true), ChatSala.ERROR_YA_PENDIENTE)
	chat.cerrar_denuncia()
	assert_eq(chat.denunciar(primero, 2, AHORA, true), ChatSala.ERROR_YA_DENUNCIADO)
	assert_false(chat.hay_denuncia(), "un hecho ya denunciado no vuelve a pausar")
	assert_eq(chat.denunciar(segundo, 2, AHORA, true), "")


func test_responde_cualquiera_de_la_parte_denunciada() -> void:
	assert_eq(chat.puede_responder(1), ChatSala.ERROR_SIN_DENUNCIA)
	chat.denunciar(_mensaje_de(1), 0, AHORA, true)
	assert_eq(chat.puede_responder(1), "", "el autor")
	assert_eq(chat.puede_responder(3), "", "su compañero")
	assert_eq(chat.puede_responder(0), ChatSala.ERROR_NO_DENUNCIADO)
	assert_eq(chat.puede_responder(2), ChatSala.ERROR_NO_DENUNCIADO)


func test_cerrar_denuncia_la_devuelve_y_la_quita() -> void:
	chat.denunciar(_mensaje_de(1), 0, AHORA, true)
	var cerrada := chat.cerrar_denuncia()
	assert_eq(cerrada["mensaje_id"], 1)
	assert_false(chat.hay_denuncia())
	assert_eq(chat.cerrar_denuncia(), {})


func test_vista_denuncia() -> void:
	chat.denunciar(_mensaje_de(1), 0, AHORA, true)
	var pendiente := ChatSala.vista_denuncia(chat.denuncia, "pendiente", AHORA + 15000)
	assert_eq(pendiente, {
		"estado": "pendiente", "mensaje_id": 1, "mensaje": "tengo el as", "denunciante": 0,
		"denunciado": 1, "equipo_denunciado": 1, "segundos": 45.0, "respondido_por": -1,
	})
	var admitida := ChatSala.vista_denuncia(chat.cerrar_denuncia(), "admitida", AHORA, 3)
	assert_eq(admitida["estado"], "admitida")
	assert_eq(admitida["segundos"], 0.0)
	assert_eq(admitida["respondido_por"], 3)
	assert_eq(ChatSala.vista_denuncia({"limite_ms": 0}, "pendiente", 5000)["segundos"], 0.0, "nunca negativo")
