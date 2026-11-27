extends GutTest
## Sonidos del cliente (PBI-21): todos los ficheros existen y cargan, suenan
## solo con el ajuste activado, ocupan menos de 5 MB y cada uno tiene su fuente
## y su licencia en CREDITOS.md. En headless no se oye nada, pero la señal
## reproducido dice qué habría sonado.

const SonidosScript := preload("res://client/autoload/sonidos.gd")
const AjustesScript := preload("res://client/autoload/ajustes.gd")
const CARPETA := "res://client/assets/sonidos/"
const CREDITOS := CARPETA + "CREDITOS.md"
const LIMITE_BYTES := 5 * 1024 * 1024
const RUTA_AJUSTES := "user://test_ajustes_sonidos.cfg"

var ajustes: Node
var sonidos: Node


func before_each() -> void:
	ajustes = AjustesScript.new()
	ajustes.ruta = RUTA_AJUSTES
	add_child_autofree(ajustes)
	sonidos = SonidosScript.new()
	sonidos.ajustes = ajustes
	add_child_autofree(sonidos)


func after_each() -> void:
	if FileAccess.file_exists(RUTA_AJUSTES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_AJUSTES))


## Los .ogg de la carpeta (los de verdad, no sus .import).
static func _ficheros_ogg() -> PackedStringArray:
	var ogg := PackedStringArray()
	for fichero in DirAccess.get_files_at(CARPETA):
		if fichero.get_extension() == "ogg":
			ogg.append(fichero)
	return ogg


func test_todas_las_rutas_existen_y_cargan_como_audio() -> void:
	for nombre: String in SonidosScript.RUTAS:
		var rutas: Array = SonidosScript.RUTAS[nombre]
		assert_gt(rutas.size(), 0, "%s tiene al menos una variante" % nombre)
		for ruta: String in rutas:
			assert_true(ResourceLoader.exists(ruta), ruta)
			assert_true(load(ruta) is AudioStream, "%s carga como sonido" % ruta)


func test_hay_un_sonido_para_cada_momento_de_la_partida() -> void:
	assert_eq(SonidosScript.RUTAS.keys(), [SonidosScript.REPARTIR, SonidosScript.ROBAR,
		SonidosScript.CARTA, SonidosScript.TURNO])


func test_todos_los_ficheros_de_la_carpeta_se_usan() -> void:
	var usados := []
	for nombre: String in SonidosScript.RUTAS:
		for ruta: String in SonidosScript.RUTAS[nombre]:
			usados.append(ruta.get_file())
	for fichero in _ficheros_ogg():
		assert_has(usados, fichero, "%s está en RUTAS" % fichero)


func test_con_sonido_suena_y_lo_dice() -> void:
	watch_signals(sonidos)
	assert_true(sonidos.reproducir(SonidosScript.CARTA))
	assert_signal_emitted_with_parameters(sonidos, "reproducido", [SonidosScript.CARTA])
	assert_true(sonidos.sonando())


func test_sin_sonido_no_suena_nada() -> void:
	ajustes.sonido = false
	watch_signals(sonidos)
	for nombre: String in SonidosScript.RUTAS:
		assert_false(sonidos.reproducir(nombre), nombre)
	assert_signal_not_emitted(sonidos, "reproducido")
	assert_false(sonidos.sonando())


func test_un_nombre_desconocido_no_suena() -> void:
	watch_signals(sonidos)
	assert_false(sonidos.reproducir("aplausos"))
	assert_signal_not_emitted(sonidos, "reproducido")


func test_varias_cartas_seguidas_no_se_cortan() -> void:
	for i in SonidosScript.VOCES:
		sonidos.reproducir(SonidosScript.CARTA)
	var voces := sonidos.get_children().filter(func(hijo: Node) -> bool: return hijo is AudioStreamPlayer)
	assert_eq(voces.size(), SonidosScript.VOCES)
	assert_true(voces.all(func(voz: AudioStreamPlayer) -> bool: return voz.playing), "suenan todas a la vez")
	assert_true(sonidos.reproducir(SonidosScript.CARTA), "con todas ocupadas, se corta una y suena igual")


func test_al_desactivarlo_se_para_lo_que_suena() -> void:
	sonidos.reproducir(SonidosScript.REPARTIR)
	assert_true(sonidos.sonando())
	ajustes.poner_sonido(false)
	assert_false(sonidos.sonando())


func test_pesan_menos_de_5_mb_en_total() -> void:
	var total := 0
	for fichero in _ficheros_ogg():
		var archivo := FileAccess.open(CARPETA + fichero, FileAccess.READ)
		total += archivo.get_length()
		archivo.close()
	assert_gt(total, 0, "hay sonidos")
	assert_lt(total, LIMITE_BYTES, "los sonidos ocupan %d bytes" % total)


func test_creditos_cita_cada_fichero_y_su_licencia() -> void:
	assert_true(FileAccess.file_exists(CREDITOS), "hay CREDITOS.md junto a los sonidos")
	var texto := FileAccess.get_file_as_string(CREDITOS)
	for fichero in _ficheros_ogg():
		assert_string_contains(texto, "`%s`" % fichero, "%s tiene su fila en los créditos" % fichero)
	assert_string_contains(texto, "CC0")
	assert_string_contains(texto, "creativecommons.org/publicdomain/zero/1.0")
	assert_string_contains(texto, "kenney.nl")
