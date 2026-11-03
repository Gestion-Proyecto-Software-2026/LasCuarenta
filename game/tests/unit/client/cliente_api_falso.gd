extends Node
## Doble de ClienteApi para los tests del lobby: mismas funciones, sin HTTP.
## Cada test configura la respuesta que quiere y puede revisar las llamadas hechas.

var autenticado := true
var usuario: Dictionary = {"nombre_visible": "Ana"}
var token := ""

var respuesta_listar: Dictionary = {"ok": true, "codigo": 200, "datos": []}
var respuesta_crear: Dictionary = {"ok": true, "codigo": 201, "datos": {}}
var respuesta_unirse: Dictionary = {"ok": true, "codigo": 200, "datos": {}}
var respuesta_salir: Dictionary = {"ok": true, "codigo": 204, "datos": null}

## Lista de [nombre_de_funcion, argumento] en el orden en que se llamaron.
var llamadas: Array = []
## Como una petición real: la respuesta llega un frame después.
var asincrono := true


func esta_autenticado() -> bool:
	return autenticado


func cerrar_sesion() -> void:
	autenticado = false
	usuario = {}


func listar_salas(juego: String = "guinote") -> Dictionary:
	llamadas.append(["listar_salas", juego])
	await _esperar()
	return respuesta_listar


func crear_sala(juego: String = "guinote", capacidad: int = 4, nombre: String = "", password: String = "") -> Dictionary:
	llamadas.append(["crear_sala", juego, capacidad, nombre, password])
	await _esperar()
	return respuesta_crear


func unirse_sala(sala_id: String, password: String = "") -> Dictionary:
	llamadas.append(["unirse_sala", sala_id, password])
	await _esperar()
	return respuesta_unirse


func salir_sala(sala_id: String) -> Dictionary:
	llamadas.append(["salir_sala", sala_id])
	await _esperar()
	return respuesta_salir


func _esperar() -> void:
	if asincrono:
		await get_tree().process_frame


func veces_llamado(nombre: String) -> int:
	return llamadas.filter(func(llamada): return llamada[0] == nombre).size()
