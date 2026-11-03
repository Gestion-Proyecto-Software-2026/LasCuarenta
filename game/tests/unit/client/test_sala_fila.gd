extends GutTest
## Fila de una sala en el lobby: nombre, candado si tiene contraseña y quién
## ya está sentado (docs/analisis_funcional_app.md §5).

const SALA_FILA := preload("res://client/ui/lobby/sala_fila.tscn")

var fila


func before_each() -> void:
	fila = SALA_FILA.instantiate()
	add_child_autofree(fila)


func _etiqueta() -> Label:
	return fila.find_child("Etiqueta", true, false)


func test_muestra_el_nombre_de_la_sala_y_los_jugadores_sentados() -> void:
	fila.configurar({
		"id": "s1",
		"nombre": "Partida rápida",
		"jugadores_actuales": 2,
		"capacidad": 4,
		"jugadores": [
			{"usuario_id": "u1", "nombre_visible": "Ana", "posicion": 0},
			{"usuario_id": "u2", "nombre_visible": "Luis", "posicion": 1},
		],
	})

	assert_eq(_etiqueta().text, "Partida rápida · 2/4 jugadores (Ana, Luis)")


func test_sin_nombre_usa_el_nombre_por_defecto() -> void:
	fila.configurar({"id": "s1", "jugadores_actuales": 1, "capacidad": 4})

	assert_eq(_etiqueta().text, "Sala de Guiñote · 1/4 jugadores")


func test_lista_de_jugadores_vacia_no_añade_paréntesis() -> void:
	fila.configurar({"id": "s1", "nombre": "X", "jugadores_actuales": 0, "capacidad": 4, "jugadores": []})

	assert_eq(_etiqueta().text, "X · 0/4 jugadores")


func test_muestra_candado_si_tiene_contrasena() -> void:
	fila.configurar({"id": "s1", "nombre": "Secreta", "jugadores_actuales": 1, "capacidad": 4, "tiene_contrasena": true})

	assert_eq(_etiqueta().text, "Secreta 🔒 · 1/4 jugadores")


func test_sin_contrasena_no_muestra_candado() -> void:
	fila.configurar({"id": "s1", "nombre": "Abierta", "jugadores_actuales": 1, "capacidad": 4, "tiene_contrasena": false})

	assert_eq(_etiqueta().text, "Abierta · 1/4 jugadores")


func test_unirse_sin_contrasena_emite_la_senal_directamente() -> void:
	fila.configurar({"id": "s1", "jugadores_actuales": 1, "capacidad": 4})
	var recibido := []
	fila.unirse_pulsado.connect(func(sala_id: String, password: String) -> void:
		recibido.append([sala_id, password]))

	fila.find_child("BotonUnirse", true, false).pressed.emit()

	assert_eq(recibido, [["s1", ""]])
