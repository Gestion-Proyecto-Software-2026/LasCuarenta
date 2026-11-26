extends GutTest

const LOBBY := preload("res://client/ui/lobby/lobby.tscn")
const ClienteApiFalso := preload("res://tests/unit/client/cliente_api_falso.gd")

const SALA_A := {"id": "11111111-1111-4111-8111-111111111111", "juego": "guinote", "jugadores_actuales": 2, "capacidad": 4}
const SALA_B := {"id": "22222222-2222-4222-8222-222222222222", "juego": "guinote", "jugadores_actuales": 1, "capacidad": 4}

var api
var lobby


func before_each() -> void:
	api = ClienteApiFalso.new()
	add_child_autofree(api)
	lobby = LOBBY.instantiate()
	lobby.api = api
	add_child_autofree(lobby)
	await wait_frames(2)


func _lista() -> VBoxContainer:
	return lobby.find_child("ListaSalas", true, false)


func _boton(nombre: String) -> Button:
	return lobby.find_child(nombre, true, false)


func _etiqueta(nombre: String) -> Label:
	return lobby.find_child(nombre, true, false)


func test_saluda_con_el_nombre_del_usuario() -> void:
	assert_eq(_etiqueta("EtiquetaUsuario").text, "Bienvenido/a, Ana")


func test_carga_las_salas_al_entrar() -> void:
	assert_eq(api.veces_llamado("listar_salas"), 1)
	assert_eq(api.llamadas[0], ["listar_salas", "guinote"])


func test_pinta_una_fila_por_sala() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": [SALA_A, SALA_B]}

	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	assert_eq(_lista().get_child_count(), 2)


func test_muestra_el_estado_vacio_cuando_no_hay_salas() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": []}

	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	assert_true(_etiqueta("EtiquetaVacia").visible)
	assert_eq(_lista().get_child_count(), 0)


func test_oculta_el_estado_vacio_cuando_hay_salas() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": [SALA_A]}

	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	assert_false(_etiqueta("EtiquetaVacia").visible)


## Abre el diálogo de crear sala y pulsa su botón de confirmar (valores por
## defecto: guinote, 4 jugadores, sin nombre ni contraseña).
func _confirmar_dialogo_crear_sala() -> void:
	_boton("BotonCrear").pressed.emit()
	await wait_frames(1)
	lobby.find_child("BotonConfirmarCrear", true, false).pressed.emit()


func test_crear_sala_llama_a_crear_y_refresca_la_lista() -> void:
	await _confirmar_dialogo_crear_sala()
	await wait_frames(3)

	assert_eq(api.llamadas[1], ["crear_sala", "guinote", 4, "", ""])
	assert_eq(api.veces_llamado("listar_salas"), 2, "tras crear se vuelve a pedir la lista")


func test_cancelar_el_dialogo_de_crear_sala_no_llama_a_la_api() -> void:
	_boton("BotonCrear").pressed.emit()
	await wait_frames(1)
	lobby.find_child("BotonCancelar", true, false).pressed.emit()
	await wait_frames(1)

	assert_eq(api.veces_llamado("crear_sala"), 0)


func test_unirse_envia_el_id_de_la_sala_de_esa_fila() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": [SALA_A, SALA_B]}
	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	var fila_b = _lista().get_child(1)
	fila_b.find_child("BotonUnirse", true, false).pressed.emit()
	await wait_frames(3)

	assert_true(api.llamadas.has(["unirse_sala", SALA_B.id, ""]))


func test_muestra_el_error_del_backend_si_no_se_puede_unir() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": [SALA_A]}
	api.respuesta_unirse = {"ok": false, "codigo": 409, "datos": {"error": "la sala está llena"}}
	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	_lista().get_child(0).find_child("BotonUnirse", true, false).pressed.emit()
	await wait_frames(3)

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_eq(_etiqueta("EtiquetaError").text, "la sala está llena")


func test_los_botones_se_bloquean_mientras_hay_una_peticion() -> void:
	await _confirmar_dialogo_crear_sala()
	assert_true(_boton("BotonCrear").disabled, "el botón crear debe bloquearse durante la petición")
	await wait_frames(3)
	assert_false(_boton("BotonCrear").disabled)


# --- Historial (PBI-06) ---

func test_el_boton_de_historial_va_entre_crear_sala_y_actualizar() -> void:
	var historial := _boton("BotonHistorial")
	assert_not_null(historial)
	assert_eq(historial.text, "Historial")
	assert_eq(historial.get_index(), _boton("BotonCrear").get_index() + 1)
	assert_eq(_boton("BotonActualizar").get_index(), historial.get_index() + 1)


## La navegación real no se prueba (ver test_espera.gd): basta con que el botón
## lleve al manejador que cambia de escena y que esa escena exista.
func test_el_boton_de_historial_abre_la_pantalla_de_historial() -> void:
	assert_true(_boton("BotonHistorial").pressed.is_connected(lobby._on_boton_historial_pressed))
	assert_true(ResourceLoader.exists(lobby.ESCENA_HISTORIAL))
	assert_true(load(lobby.ESCENA_HISTORIAL) is PackedScene)


# --- Ajustes (PBI-21) ---

func test_el_boton_de_ajustes_va_al_final_de_la_fila_despues_de_ranking() -> void:
	var ajustes := _boton("BotonAjustes")
	assert_not_null(ajustes)
	assert_eq(ajustes.text, "Ajustes")
	assert_true(ajustes.flat, "mismo estilo que Historial")
	assert_eq(ajustes.get_index(), _boton("BotonRanking").get_index() + 1)
	assert_eq(ajustes.get_index(), ajustes.get_parent().get_child_count() - 1)


func test_el_boton_de_ajustes_abre_el_panel() -> void:
	_boton("BotonAjustes").pressed.emit()
	var panel: AcceptDialog = lobby.find_child("PanelAjustes", true, false)
	assert_not_null(panel)
	assert_true(panel.visible)
	assert_eq(panel.title, "Ajustes")
	assert_not_null(panel.casilla_sonido)
	panel.hide()
	_boton("BotonAjustes").pressed.emit()
	assert_true(panel.visible, "se vuelve a abrir el mismo")
	assert_eq(lobby.find_children("PanelAjustes", "", true, false).size(), 1)
	panel.hide()


func test_con_el_boton_de_ajustes_el_lobby_sigue_cabiendo_en_la_ventana_base() -> void:
	var minimo: Vector2 = lobby.find_child("PanelCartulina", true, false).get_combined_minimum_size()
	assert_lt(minimo.x, 1152.0, "ancho mínimo del panel: %s" % minimo)
	assert_lt(minimo.y, 648.0, "alto mínimo del panel: %s" % minimo)
