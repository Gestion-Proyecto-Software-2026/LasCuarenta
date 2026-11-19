extends Node
## Cliente HTTP del backend REST (/api/*) para la app de escritorio (Godot nativo).
##
## Autoload único: aquí se guarda el JWT tras iniciar sesión, para que el resto
## de pantallas (lobby, historial...) lo reutilicen sin pedirlo otra vez.
## Contrato completo en docs/analisis_funcional_app.md §5.

const URL_BASE_POR_DEFECTO := "http://localhost:3000/api"
## Fichero junto al ejecutable con la dirección del servidor, para quien juega
## con el cliente descargable (PBI-13) y no puede definir variables de entorno.
const ARCHIVO_CONFIG := "servidor.cfg"
const TIEMPO_MAXIMO_S := 10.0

var url_base: String
var token: String = ""
var usuario: Dictionary = {}


## Dirección del backend, por este orden: la variable de entorno BACKEND_URL, el
## fichero servidor.cfg junto al ejecutable y, si no hay ninguno, localhost.
func _ready() -> void:
	url_base = OS.get_environment("BACKEND_URL")
	if url_base.is_empty():
		url_base = url_desde_config(OS.get_executable_path().get_base_dir().path_join(ARCHIVO_CONFIG))
	if url_base.is_empty():
		url_base = URL_BASE_POR_DEFECTO
	# Para saber a qué servidor intenta conectarse (útil al dar soporte).
	print("Backend: ", url_base)


## Lee [code]backend_url[/code] de la sección [code][servidor][/code] de un
## fichero de configuración. Devuelve "" si el fichero no existe o la dirección
## no es válida (debe empezar por http:// o https://).
static func url_desde_config(ruta: String) -> String:
	var config := ConfigFile.new()
	if config.load(ruta) != OK:
		return ""
	var url := str(config.get_value("servidor", "backend_url", "")).strip_edges()
	if url.is_empty():
		return ""
	if not (url.begins_with("http://") or url.begins_with("https://")):
		push_warning("%s: backend_url debe empezar por http:// o https:// (era '%s'); se ignora" % [ruta, url])
		return ""
	return url.rstrip("/")


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


func listar_salas(juego: String = "guinote") -> Dictionary:
	return await _pedir(HTTPClient.METHOD_GET, "/salas?juego=" + juego.uri_encode())


## [param nombre] vacío usa el nombre por defecto del backend; [param password]
## vacía crea la sala sin contraseña (ver docs/analisis_funcional_app.md §5).
func crear_sala(juego: String = "guinote", capacidad: int = 4, nombre: String = "", password: String = "") -> Dictionary:
	var cuerpo := {"juego": juego, "capacidad": capacidad}
	if not nombre.is_empty():
		cuerpo["nombre"] = nombre
	if not password.is_empty():
		cuerpo["password_hash"] = _hash_password(password)
	return await _pedir(HTTPClient.METHOD_POST, "/salas", cuerpo)


## [param password] solo hace falta si la sala tiene contraseña.
func unirse_sala(sala_id: String, password: String = "") -> Dictionary:
	var cuerpo: Variant = null
	if not password.is_empty():
		cuerpo = {"password_hash": _hash_password(password)}
	return await _pedir(HTTPClient.METHOD_POST, "/salas/%s/unirse" % sala_id.uri_encode(), cuerpo)


func salir_sala(sala_id: String) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_DELETE, "/salas/%s/unirse" % sala_id.uri_encode())


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
	return _decodificar_respuesta(respuesta[0], respuesta[1], respuesta[3])


static func _decodificar_respuesta(resultado: int, codigo_http: int, cuerpo: PackedByteArray) -> Dictionary:
	var codigo := codigo_http if resultado == HTTPRequest.RESULT_SUCCESS else 0
	var datos: Variant = null
	var json := JSON.new()
	if json.parse(cuerpo.get_string_from_utf8()) == OK:
		datos = json.data
	return {"ok": codigo >= 200 and codigo < 300, "codigo": codigo, "datos": datos}
