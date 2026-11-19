extends GutTest
## Dirección del backend para el cliente descargable (PBI-13): se lee de un
## servidor.cfg junto al ejecutable, para quien no puede definir BACKEND_URL.

const ClienteApiScript := preload("res://client/autoload/cliente_api.gd")
const RUTA := "user://servidor_de_prueba.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA))


func _escribir(contenido: String) -> void:
	var f := FileAccess.open(RUTA, FileAccess.WRITE)
	f.store_string(contenido)
	f.close()


func test_lee_la_direccion_del_fichero() -> void:
	_escribir('[servidor]\nbackend_url="https://cartas.ejemplo.es/api"\n')
	assert_eq(ClienteApiScript.url_desde_config(RUTA), "https://cartas.ejemplo.es/api")


func test_quita_espacios_y_la_barra_final() -> void:
	_escribir('[servidor]\nbackend_url="  http://192.168.1.20:3000/api/  "\n')
	assert_eq(ClienteApiScript.url_desde_config(RUTA), "http://192.168.1.20:3000/api")


func test_sin_fichero_no_hay_direccion() -> void:
	assert_eq(ClienteApiScript.url_desde_config("user://no_existe.cfg"), "")


func test_sin_la_clave_no_hay_direccion() -> void:
	_escribir('[servidor]\notra_cosa="x"\n')
	assert_eq(ClienteApiScript.url_desde_config(RUTA), "")


func test_una_direccion_sin_http_se_ignora() -> void:
	_escribir('[servidor]\nbackend_url="cartas.ejemplo.es"\n')
	assert_eq(ClienteApiScript.url_desde_config(RUTA), "")


func test_un_fichero_mal_formado_se_ignora() -> void:
	_escribir("esto no es un fichero de configuración [[[")
	assert_eq(ClienteApiScript.url_desde_config(RUTA), "")
