extends GutTest
## La navegación real (change_scene_to_file) no se prueba aquí, igual que el
## resto de pantallas del cliente (ver lobby.gd/test_lobby.gd): se comprueba a
## mano (ver el informe de pruebas manuales). Lo que sí probamos es que esta
## pantalla conecta, envía unirse_partida con los datos correctos, y reacciona
## a los errores del servidor.

const ESPERA := preload("res://client/ui/espera/espera.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")
const ClienteApiFalso := preload("res://tests/unit/client/cliente_api_falso.gd")

var red
var api
var espera


func before_each() -> void:
	red = ClienteRedFalso.new()
	red.sala_id = "sala-1"
	add_child_autofree(red)
	api = ClienteApiFalso.new()
	api.usuario = {"id": "u1", "nombre_visible": "Ana"}
	api.token = "tok-123"
	add_child_autofree(api)

	espera = ESPERA.instantiate()
	espera.red = red
	espera.api = api
	add_child_autofree(espera)
	await wait_frames(1)


func _etiqueta(nombre: String) -> Label:
	return espera.find_child(nombre, true, false)


func _boton(nombre: String) -> Button:
	return espera.find_child(nombre, true, false)


func test_al_entrar_se_conecta_al_servidor_de_partida() -> void:
	assert_eq(red.llamadas[0], ["conectar_al_servidor"])


func test_al_conectar_envia_unirse_partida_con_usuario_y_token() -> void:
	red.conectado.emit()

	assert_true(red.llamadas.has(["unirse_partida", "u1", "tok-123"]))


func test_fallo_de_conexion_muestra_error_y_boton_volver() -> void:
	red.fallo_conexion.emit()

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_true(_boton("BotonVolver").visible)


func test_error_del_servidor_muestra_el_mensaje_y_desconecta() -> void:
	red.error_recibido.emit("La sala no existe")

	assert_eq(_etiqueta("EtiquetaError").text, "La sala no existe")
	assert_true(red.llamadas.has(["desconectar"]))


func test_desconexion_del_servidor_muestra_error_y_desconecta() -> void:
	red.desconectado_del_servidor.emit()

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_true(red.llamadas.has(["desconectar"]))


func test_el_boton_salir_esta_visible_desde_el_principio() -> void:
	# No hace falta esperar a un error: se puede salir mientras se espera a los
	# demás jugadores (ver docs/analisis_funcional_app.md §5).
	assert_true(_boton("BotonVolver").visible)


func test_elige_la_pantalla_de_2_jugadores_si_la_sala_tiene_2() -> void:
	var escena: String = espera._escena_para({"jugadores": [{}, {}]})

	assert_eq(escena, "res://client/ui/partida_guinote_2p/partida_guinote_2p.tscn")


func test_elige_la_pantalla_de_4_jugadores_si_la_sala_tiene_4() -> void:
	var escena: String = espera._escena_para({"jugadores": [{}, {}, {}, {}]})

	assert_eq(escena, "res://client/ui/partida/partida.tscn")


func test_salir_abandona_la_sala_por_HTTP_y_desconecta_de_ENet() -> void:
	# Llama directamente a _abandonar_sala (y no al botón) para no disparar la
	# navegación real de get_tree().change_scene_to_file; ver el comentario de
	# esa función en espera.gd.
	await espera._abandonar_sala()

	assert_true(api.llamadas.has(["salir_sala", "sala-1"]))
	assert_true(red.llamadas.has(["desconectar"]))

# El botón "Salir de la sala" también cambia de escena (get_tree().change_scene_to_file);
# esa navegación no se prueba aquí por el mismo motivo que en lobby.gd (ver
# docs/mapa/tests-ci.md): se comprueba a mano.
