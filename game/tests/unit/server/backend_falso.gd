extends Node
## Doble de ClienteBackend para los tests: mismas funciones, sin HTTP.

## sala_id -> respuesta de GET /interno/salas/:id
var salas: Dictionary = {}
## Si es true, las consultas tardan un frame (como una petición real).
var asincrono := false
var consultas_de_sala := 0
var partidas_registradas: Array[Dictionary] = []


func obtener_sala(sala_id: String) -> Dictionary:
	consultas_de_sala += 1
	if asincrono:
		await get_tree().process_frame
	if not salas.has(sala_id):
		return {"ok": false, "codigo": 404, "datos": {"error": "sala no encontrada"}}
	return {"ok": true, "codigo": 200, "datos": salas[sala_id]}


func registrar_partida(datos: Dictionary) -> Dictionary:
	partidas_registradas.append(datos)
	return {"ok": true, "codigo": 201, "datos": null}
