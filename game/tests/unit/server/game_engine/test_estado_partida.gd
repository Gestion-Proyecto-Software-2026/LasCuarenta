extends GutTest


class EstadoDePrueba:
	extends EstadoPartida
	var manos: Array = [[1, 2], [3]]
	var tanteo := {"equipo_0": [10]}
	var turno: int = 0


func test_duplicar_mantiene_la_clase_y_los_valores() -> void:
	var original := EstadoDePrueba.new()
	original.num_jugadores = 2
	original.turno = 1
	var copia := original.duplicar() as EstadoDePrueba
	assert_not_null(copia, "la copia debe ser de la misma subclase")
	assert_eq(copia.num_jugadores, 2)
	assert_eq(copia.turno, 1)
	assert_eq(copia.manos, [[1, 2], [3]])


func test_duplicar_copia_arrays_y_diccionarios_en_profundidad() -> void:
	var original := EstadoDePrueba.new()
	var copia := original.duplicar() as EstadoDePrueba
	copia.manos[0].append(99)
	copia.tanteo["equipo_0"].append(5)
	assert_eq(original.manos[0], [1, 2])
	assert_eq(original.tanteo["equipo_0"], [10])
