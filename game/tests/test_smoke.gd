extends GutTest
## Comprueba que el proyecto carga y que GUT se ejecuta en CI.
## Se puede borrar cuando existan tests reales de la lógica de juego.


func test_escena_principal_carga() -> void:
	var escena: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	assert_not_null(escena, "La escena principal configurada en project.godot debe cargar")
