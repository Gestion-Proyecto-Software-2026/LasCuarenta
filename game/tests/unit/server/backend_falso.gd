extends Node
## Doble de ClienteBackend para los tests: mismas funciones, sin HTTP.

## sala_id -> respuesta de GET /interno/salas/:id
var salas: Dictionary = {}
## Si es true, las consultas tardan un frame (como una petición real).
var asincrono := false
var consultas_de_sala := 0
## Lo que se ha mandado a POST /interno/partidas, un elemento por intento.
var partidas_registradas: Array[Dictionary] = []
var salas_iniciadas: Array[String] = []
## Respuestas para los siguientes registros (PBI-06, reintentos): cada intento
## consume la primera. Vacía, el backend acepta: { ok: true, codigo: 201 }.
var respuestas_registro: Array[Dictionary] = []


func obtener_sala(sala_id: String) -> Dictionary:
	consultas_de_sala += 1
	if asincrono:
		await get_tree().process_frame
	if not salas.has(sala_id):
		return {"ok": false, "codigo": 404, "datos": {"error": "sala no encontrada"}}
	return {"ok": true, "codigo": 200, "datos": salas[sala_id]}


func iniciar_sala(sala_id: String) -> Dictionary:
	salas_iniciadas.append(sala_id)
	return {"ok": true, "codigo": 204, "datos": null}


func registrar_partida(datos: Dictionary) -> Dictionary:
	partidas_registradas.append(datos)
	if not respuestas_registro.is_empty():
		return respuestas_registro.pop_front()
	return {"ok": true, "codigo": 201, "datos": null}
