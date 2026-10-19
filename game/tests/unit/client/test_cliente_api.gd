extends GutTest

const ScriptClienteApi := preload("res://client/autoload/cliente_api.gd")

## SHA-256("abc"), vector de prueba estándar.
const HASH_ABC := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

var api


func before_each() -> void:
	api = ScriptClienteApi.new()


func after_each() -> void:
	api.free()


func test_hash_de_la_contrasena_es_sha256_en_hex() -> void:
	assert_eq(api._hash_password("abc"), HASH_ABC)


func test_sin_token_no_esta_autenticado() -> void:
	assert_false(api.esta_autenticado())


func test_con_token_esta_autenticado() -> void:
	api.token = "eyJ.token.falso"
	assert_true(api.esta_autenticado())


func test_cerrar_sesion_borra_token_y_usuario() -> void:
	api.token = "eyJ.token.falso"
	api.usuario = {"nombre_visible": "Ana"}

	api.cerrar_sesion()

	assert_false(api.esta_autenticado())
	assert_eq(api.usuario, {})


func test_decodifica_una_respuesta_correcta() -> void:
	var cuerpo := '{"id": "u1"}'.to_utf8_buffer()

	var resultado: Dictionary = ScriptClienteApi._decodificar_respuesta(HTTPRequest.RESULT_SUCCESS, 200, cuerpo)

	assert_true(resultado.ok)
	assert_eq(resultado.codigo, 200)
	assert_eq(resultado.datos, {"id": "u1"})


func test_decodifica_un_error_del_backend_con_su_mensaje() -> void:
	var cuerpo := '{"error": "la sala está llena"}'.to_utf8_buffer()

	var resultado: Dictionary = ScriptClienteApi._decodificar_respuesta(HTTPRequest.RESULT_SUCCESS, 409, cuerpo)

	assert_false(resultado.ok)
	assert_eq(resultado.codigo, 409)
	assert_eq(resultado.datos.error, "la sala está llena")


func test_sin_conexion_devuelve_codigo_cero_y_sin_datos() -> void:
	var resultado: Dictionary = ScriptClienteApi._decodificar_respuesta(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())

	assert_false(resultado.ok)
	assert_eq(resultado.codigo, 0)
	assert_null(resultado.datos)


func test_un_cuerpo_que_no_es_json_deja_datos_vacios() -> void:
	var resultado: Dictionary = ScriptClienteApi._decodificar_respuesta(HTTPRequest.RESULT_SUCCESS, 200, "<html>".to_utf8_buffer())

	assert_true(resultado.ok)
	assert_null(resultado.datos)
