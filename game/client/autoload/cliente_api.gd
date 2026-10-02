extends Node
## Cliente HTTP del backend REST (/api/*) para la app de escritorio (Godot nativo).
##
## Autoload único: aquí se guarda el JWT tras iniciar sesión, para que el resto
## de pantallas (lobby, historial...) lo reutilicen sin pedirlo otra vez.
## Contrato completo en docs/analisis_funcional_app.md §5.

const URL_BASE_POR_DEFECTO := "http://localhost:3000/api"
const TIEMPO_MAXIMO_S := 10.0

var url_base: String
var token: String = ""
var usuario: Dictionary = {}


func _ready() -> void:
	url_base = OS.get_environment("BACKEND_URL")
	if url_base.is_empty():
		url_base = URL_BASE_POR_DEFECTO


func esta_autenticado() -> bool:
	return not token.is_empty()


func cerrar_sesion() -> void:
	token = ""
	usuario = {}


func registrar(email: String, password: String, nombre_visible: String) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_POST, "/auth/registro", {
		"email": email,
		"password_hash": _hash_password(password),
		"nombre_visible": nombre_visible,
	})


func login(email: String, password: String) -> Dictionary:
	var resultado := await _pedir(HTTPClient.METHOD_POST, "/auth/login", {
		"email": email,
		"password_hash": _hash_password(password),
	})
	if resultado.ok:
		token = resultado.datos.get("token", "")
		usuario = resultado.datos.get("usuario", {})
	return resultado


func recuperar(email: String) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_POST, "/auth/recuperar", {"email": email})


func restablecer(email: String, codigo: String, password: String) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_POST, "/auth/restablecer", {
		"email": email,
		"codigo": codigo,
		"password_hash": _hash_password(password),
	})


func _hash_password(password: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(password.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Devuelve siempre { "ok": bool, "codigo": int, "datos": Variant }: "codigo" es
## el HTTP status (0 si no hubo respuesta: backend caído, timeout...) y "datos"
## el JSON ya decodificado.
func _pedir(metodo: HTTPClient.Method, ruta: String, cuerpo: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIEMPO_MAXIMO_S
	add_child(http)

	var cabeceras := PackedStringArray()
	if not token.is_empty():
		cabeceras.append("Authorization: Bearer " + token)

	var texto := ""
	if cuerpo != null:
		cabeceras.append("Content-Type: application/json")
		texto = JSON.stringify(cuerpo)

	if http.request(url_base + ruta, cabeceras, metodo, texto) != OK:
		http.queue_free()
		return {"ok": false, "codigo": 0, "datos": null}

	var respuesta: Array = await http.request_completed
	http.queue_free()
	var resultado: int = respuesta[0]
	var codigo: int = respuesta[1] if resultado == HTTPRequest.RESULT_SUCCESS else 0
	var datos: Variant = null
	var json := JSON.new()
	if json.parse((respuesta[3] as PackedByteArray).get_string_from_utf8()) == OK:
		datos = json.data
	return {"ok": codigo >= 200 and codigo < 300, "codigo": codigo, "datos": datos}
