extends GutTest

const MainServer := preload("res://server/main_server.gd")


func test_puerto_por_defecto_sin_argumentos() -> void:
	assert_eq(MainServer.leer_puerto(PackedStringArray()), MainServer.PUERTO_POR_DEFECTO)


func test_puerto_desde_argumento() -> void:
	assert_eq(MainServer.leer_puerto(PackedStringArray(["--puerto=9001"])), 9001)


func test_puerto_no_valido_usa_el_por_defecto() -> void:
	for arg in ["--puerto=abc", "--puerto=0", "--puerto=70000"]:
		assert_eq(MainServer.leer_puerto(PackedStringArray([arg])), MainServer.PUERTO_POR_DEFECTO, arg)
