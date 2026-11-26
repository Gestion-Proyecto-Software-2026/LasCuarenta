extends GutTest
## PBI-21, criterio 6 (verificación automática): se juega una partida entera
## con sonido y otra sin él. Como en test_mesa_seis_modos.gd, cada jugador es
## una pantalla partida_mesa.tscn de verdad que juega sola contra un RoomManager
## de verdad; cada una tiene su autoload Sonidos de verdad (sonidos.gd), con
## unos ajustes de prueba en vez de los del usuario. En headless no se oye
## nada, así que se cuenta lo que suena con la señal reproducido.

const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")
const RedEnBucle := preload("res://tests/integration/red_en_bucle.gd")
const SonidosScript := preload("res://client/autoload/sonidos.gd")
const AjustesScript := preload("res://client/autoload/ajustes.gd")
const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const NOMBRES := ["Ana", "Luis"]
const SEGUNDOS_MAXIMOS := 60
const RUTA_AJUSTES := "user://test_ajustes_partida.cfg"

var mesas: Array = []
## Por jugador: { nombre del sonido: veces que ha sonado }.
var sonados: Array[Dictionary] = []


func after_each() -> void:
	if FileAccess.file_exists(RUTA_AJUSTES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_AJUSTES))


static func _usuario(posicion: int) -> String:
	return "%d0000000-0000-4000-8000-000000000000" % posicion


## Guiñote a 2 de principio a fin. [param segundos_por_turno] = 0 es el
## servidor sin tiempo límite (no manda tiempos_para_decidir).
func _jugar(sonido: bool, segundos_por_turno := RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO) -> void:
	var backend: Node = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in 2:
		participantes.append({"usuario_id": _usuario(posicion), "posicion": posicion,
			"equipo": posicion, "nombre_visible": NOMBRES[posicion]})
	backend.salas[SALA] = {
		"id": SALA, "juego": "guinote", "estado": "esperando", "capacidad": 2, "creador_id": _usuario(0),
		"participantes": participantes,
	}
	var servidor := RoomManager.new(backend, SECRETO, MainServer.MOTORES, segundos_por_turno)
	add_child_autofree(servidor)

	var ajustes: Node = AjustesScript.new()
	ajustes.ruta = RUTA_AJUSTES
	add_child_autofree(ajustes)
	ajustes.sonido = sonido

	var redes := []
	for posicion in 2:
		var red: Node = RedEnBucle.new(servidor, 10 + posicion)
		red.sala_id = SALA
		add_child_autofree(red)
		redes.append(red)
		red.unirse_partida(_usuario(posicion), JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO))
	redes[0].enviar(MensajesRed.EMPEZAR_PARTIDA)

	mesas.clear()
	sonados.clear()
	for posicion in 2:
		var sonidos: Node = SonidosScript.new()
		sonidos.ajustes = ajustes
		add_child_autofree(sonidos)
		var cuenta := {}
		sonados.append(cuenta)
		sonidos.reproducido.connect(func(nombre: String) -> void: cuenta[nombre] = cuenta.get(nombre, 0) + 1)
		var mesa: Control = PARTIDA_MESA.instantiate()
		mesa.red = redes[posicion]
		mesa.sonidos = sonidos
		mesa.autojugar = true
		mesa.pausa_baza = 0.0
		add_child_autofree(mesa)
		mesa.tapete.espera_autojugar_carta = 0.0
		mesa.tapete.espera_autojugar_accion = 0.0
		mesas.append(mesa)

	# wait_until no hace fallar el test al agotar el tiempo: se comprueba aquí
	# que se ha jugado la partida entera, con sonido o sin él.
	var terminada: bool = await wait_until(
		func() -> bool: return mesas.all(func(m: Control) -> bool: return m._terminada),
		SEGUNDOS_MAXIMOS, "la partida termina en las dos mesas")
	assert_true(terminada, "la partida termina en las dos mesas")
	for posicion in 2:
		assert_eq(redes[posicion].errores, [] as Array[String], "al jugador %d no se le rechaza nada" % posicion)


func _comprobar_que_suena_todo() -> void:
	for posicion in 2:
		var cuenta: Dictionary = sonados[posicion]
		assert_gt(cuenta.get(SonidosScript.REPARTIR, 0), 0, "J%d oye repartir" % (posicion + 1))
		assert_gt(cuenta.get(SonidosScript.ROBAR, 0), 0, "J%d oye robar" % (posicion + 1))
		# 40 cartas en las idas como mínimo: se oyen todas, las tuyas y las del rival.
		assert_gte(cuenta.get(SonidosScript.CARTA, 0), 40, "J%d oye cada carta jugada" % (posicion + 1))
		assert_gt(cuenta.get(SonidosScript.TURNO, 0), 0, "J%d oye que le toca" % (posicion + 1))


func test_con_sonido_suenan_el_reparto_las_cartas_y_el_turno() -> void:
	await _jugar(true)
	_comprobar_que_suena_todo()


func test_con_sonido_y_sin_tiempo_limite_tambien_avisa_del_turno() -> void:
	await _jugar(true, 0.0)
	_comprobar_que_suena_todo()


func test_sin_sonido_no_suena_nada() -> void:
	await _jugar(false)
	for posicion in 2:
		assert_eq(sonados[posicion], {}, "J%d no oye nada" % (posicion + 1))
		assert_true(mesas[posicion]._terminada, "y la partida se juega igual")
