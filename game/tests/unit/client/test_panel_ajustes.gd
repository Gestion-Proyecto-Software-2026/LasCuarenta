extends GutTest
## Panel de ajustes del cliente (PBI-21): la casilla del sonido refleja el
## ajuste y al pulsarla lo cambia (y se guarda). Con unos ajustes de prueba en
## un fichero temporal, nunca con los de verdad.

const PanelAjustes := preload("res://client/ui/ajustes/panel_ajustes.gd")
const AjustesScript := preload("res://client/autoload/ajustes.gd")
const RUTA := "user://test_ajustes_panel.cfg"

var ajustes: Node
var panel: AcceptDialog


func before_each() -> void:
	ajustes = AjustesScript.new()
	ajustes.ruta = RUTA
	add_child_autofree(ajustes)


func after_each() -> void:
	if is_instance_valid(panel):
		panel.hide()
	if FileAccess.file_exists(RUTA):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA))


func _abrir() -> void:
	panel = PanelAjustes.new()
	panel.ajustes = ajustes
	add_child_autofree(panel)
	panel.popup_centered()
	await wait_frames(1)


func test_es_un_dialogo_de_ajustes_que_se_abre() -> void:
	await _abrir()
	assert_true(panel.visible)
	assert_eq(panel.title, "Ajustes")
	assert_eq(panel.get_ok_button().text, "Cerrar")
	assert_eq(panel.casilla_sonido.text, "Sonido")


func test_la_casilla_refleja_el_ajuste() -> void:
	await _abrir()
	assert_true(panel.casilla_sonido.button_pressed)
	panel.hide()
	ajustes.sonido = false
	panel.popup_centered()
	assert_false(panel.casilla_sonido.button_pressed, "se vuelve a leer al abrirse")


func test_pulsar_la_casilla_cambia_y_guarda_el_ajuste() -> void:
	await _abrir()
	panel.casilla_sonido.button_pressed = false
	assert_false(ajustes.sonido)
	assert_true(FileAccess.file_exists(RUTA), "se guarda sin tener que confirmar")
	panel.casilla_sonido.button_pressed = true
	assert_true(ajustes.sonido)


func test_leer_los_ajustes_no_los_vuelve_a_guardar() -> void:
	ajustes.sonido = false
	await _abrir()
	assert_false(panel.casilla_sonido.button_pressed)
	assert_false(FileAccess.file_exists(RUTA))


func test_cerrar_lo_oculta() -> void:
	await _abrir()
	panel.get_ok_button().pressed.emit()
	assert_false(panel.visible)


## La ventana base del juego es de 1152×648 (en headless es mucho menor, así
## que se compara con esa). Un texto partido en líneas sin ancho fijo hacía que
## al abrirlo por segunda vez pidiera más de 1200 px de alto.
func test_cabe_en_la_ventana_base_al_abrirlo_otra_vez() -> void:
	var tamanos := []
	for vez in 2:
		await _abrir_o_reabrir()
		tamanos.append(panel.size)
		assert_lt(panel.size.x, 1152, "vez %d: ancho %s" % [vez + 1, panel.size])
		assert_lt(panel.size.y, 648, "vez %d: alto %s" % [vez + 1, panel.size])
		panel.hide()
	assert_eq(tamanos[1], tamanos[0], "abrirlo otra vez no lo agranda")


func _abrir_o_reabrir() -> void:
	if is_instance_valid(panel) and panel.is_inside_tree():
		panel.popup_centered()
		await wait_frames(1)
	else:
		await _abrir()
