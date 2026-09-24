class_name ClienteBackend
extends Node
## Llamadas del servidor de partida a las rutas [code]/interno/*[/code] del
## backend, con la cabecera X-Internal-Secret (analisis_funcional_app.md §5).
##
## Todas devuelven [code]{ "ok": bool, "codigo": int, "datos": Variant }[/code]:
## [code]codigo[/code] es el HTTP status, o 0 si no hubo respuesta (backend caído,
## timeout...), y [code]datos[/code] el JSON de la respuesta ya decodificado.

const TIEMPO_MAXIMO_S := 10.0

var url_base: String
var secreto: String


## [param p_url_base] incluye el prefijo de la API, p. ej. [code]http://localhost:3000/api[/code].
func _init(p_url_base: String, p_secreto: String) -> void:
	url_base = p_url_base.trim_suffix("/")
	secreto = p_secreto


func obtener_sala(sala_id: String) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_GET, "/interno/salas/%s" % sala_id.uri_encode())


func registrar_partida(datos: Dictionary) -> Dictionary:
	return await _pedir(HTTPClient.METHOD_POST, "/interno/partidas", datos)


func _pedir(metodo: HTTPClient.Method, ruta: String, cuerpo: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIEMPO_MAXIMO_S
	add_child(http)
	var cabeceras := PackedStringArray(["X-Internal-Secret: " + secreto])
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
