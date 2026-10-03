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


func test_crear_sala_llama_a_crear_y_refresca_la_lista() -> void:
	_boton("BotonCrear").pressed.emit()
	await wait_frames(3)

	assert_eq(api.llamadas[1], ["crear_sala", "guinote"])
	assert_eq(api.veces_llamado("listar_salas"), 2, "tras crear se vuelve a pedir la lista")


func test_unirse_envia_el_id_de_la_sala_de_esa_fila() -> void:
	api.respuesta_listar = {"ok": true, "codigo": 200, "datos": [SALA_A, SALA_B]}
	_boton("BotonActualizar").pressed.emit()
	await wait_frames(2)

	var fila_b = _lista().get_child(1)
	fila_b.find_child("BotonUnirse", true, false).pressed.emit()
	await wait_frames(3)

	assert_true(api.llamadas.has(["unirse_sala", SALA_B.id]))


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
	_boton("BotonCrear").pressed.emit()
	assert_true(_boton("BotonCrear").disabled, "el botón crear debe bloquearse durante la petición")
	await wait_frames(3)
	assert_false(_boton("BotonCrear").disabled)
