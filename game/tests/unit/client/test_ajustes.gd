extends GutTest
## Ajustes del cliente (PBI-21 y PBI-22): valores por defecto, se guardan al cambiarlos
## y otra instancia con el mismo fichero los lee (lo mismo que volver a abrir
## la aplicación). Cada test usa su propio fichero temporal y lo borra: nunca
## se toca el user://ajustes.cfg de quien ejecuta los tests.

const AjustesScript := preload("res://client/autoload/ajustes.gd")
const RUTA := "user://test_ajustes_unitario.cfg"


func before_each() -> void:
	_borrar_fichero()


func after_each() -> void:
	_borrar_fichero()


func _borrar_fichero() -> void:
	if FileAccess.file_exists(RUTA):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA))


## Una instancia nueva, como la que se crea al abrir la aplicación.
func _abrir() -> Node:
	var ajustes: Node = AjustesScript.new()
	ajustes.ruta = RUTA
	add_child_autofree(ajustes)
	return ajustes


func test_la_ruta_de_verdad_es_la_de_los_datos_del_usuario() -> void:
	assert_eq(AjustesScript.RUTA_POR_DEFECTO, "user://ajustes.cfg")


func test_sin_fichero_el_sonido_esta_activado() -> void:
	var ajustes := _abrir()
	assert_true(ajustes.sonido)
	assert_false(FileAccess.file_exists(RUTA), "solo leer no crea el fichero")


func test_poner_sonido_lo_guarda_y_se_recuerda_al_volver_a_abrir() -> void:
	var ajustes := _abrir()
	ajustes.poner_sonido(false)
	assert_false(ajustes.sonido)
	assert_true(FileAccess.file_exists(RUTA), "se guarda en cuanto se cambia")
	assert_false(_abrir().sonido, "otra instancia con el mismo fichero lo lee")
	ajustes.poner_sonido(true)
	assert_true(_abrir().sonido)


func test_avisa_cuando_cambia_y_solo_entonces() -> void:
	var ajustes := _abrir()
	watch_signals(ajustes)
	ajustes.poner_sonido(false)
	assert_signal_emitted_with_parameters(ajustes, "cambiado", ["sonido", false])
	ajustes.poner_sonido(false)
	assert_signal_emit_count(ajustes, "cambiado", 1, "si no cambia, no avisa")


func test_un_fichero_corrupto_da_los_valores_por_defecto() -> void:
	var archivo := FileAccess.open(RUTA, FileAccess.WRITE)
	archivo.store_string("esto no es [un fichero de ajustes\n=== sonido\n")
	archivo.close()
	var ajustes := _abrir()
	assert_true(ajustes.sonido)
	# ConfigFile avisa del error de lectura por su cuenta; no es un fallo del juego.
	assert_engine_error("ConfigFile parse error")


func test_un_valor_de_otro_tipo_da_el_de_por_defecto() -> void:
	var archivo := ConfigFile.new()
	archivo.set_value(AjustesScript.SECCION, "sonido", "no")
	archivo.save(RUTA)
	assert_true(_abrir().sonido)


# --- Animaciones (PBI-22) ---

func test_sin_fichero_las_animaciones_estan_activadas() -> void:
	assert_true(_abrir().animaciones)


func test_poner_animaciones_lo_guarda_y_se_recuerda_al_volver_a_abrir() -> void:
	var ajustes := _abrir()
	ajustes.poner_animaciones(false)
	assert_false(ajustes.animaciones)
	assert_true(FileAccess.file_exists(RUTA), "se guarda en cuanto se cambia")
	var otra := _abrir()
	assert_false(otra.animaciones, "otra instancia con el mismo fichero lo lee")
	assert_true(otra.sonido, "sin tocar el otro ajuste")
	ajustes.poner_animaciones(true)
	assert_true(_abrir().animaciones)


func test_cada_ajuste_se_guarda_sin_pisar_el_otro() -> void:
	var ajustes := _abrir()
	ajustes.poner_sonido(false)
	ajustes.poner_animaciones(false)
	var otra := _abrir()
	assert_false(otra.sonido)
	assert_false(otra.animaciones)


func test_avisa_cuando_cambian_las_animaciones_y_solo_entonces() -> void:
	var ajustes := _abrir()
	watch_signals(ajustes)
	ajustes.poner_animaciones(false)
	assert_signal_emitted_with_parameters(ajustes, "cambiado", ["animaciones", false])
	ajustes.poner_animaciones(false)
	assert_signal_emit_count(ajustes, "cambiado", 1, "si no cambia, no avisa")


func test_unas_animaciones_de_otro_tipo_dan_el_valor_por_defecto() -> void:
	var archivo := ConfigFile.new()
	archivo.set_value(AjustesScript.SECCION, "animaciones", 0)
	archivo.save(RUTA)
	assert_true(_abrir().animaciones)
