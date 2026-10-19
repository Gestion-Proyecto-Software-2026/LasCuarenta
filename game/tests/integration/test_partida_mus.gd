extends GutTest
## Partidas completas de Mus a través de RoomManager, como las juega el servidor:
## por mensajes del protocolo (§6), con el motor registrado en main_server.gd y
## cada jugador eligiendo al azar entre sus jugadas_validas.

const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const MAX_MENSAJES := 20000

var backend: Node
var rm: RoomManager
## peer -> último estado_partida recibido
var estados: Dictionary = {}
var terminadas: Dictionary = {}  # peer -> resultado
var errores: Array[String] = []


func _preparar(capacidad: int) -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in capacidad:
		participantes.append({"usuario_id": _usuario(posicion), "posicion": posicion, "equipo": posicion % 2})
	backend.salas[SALA] = {
		"id": SALA, "juego": "mus", "estado": "esperando", "capacidad": capacidad,
		"participantes": participantes,
	}
	rm = RoomManager.new(backend, SECRETO, MainServer.MOTORES)
	add_child_autofree(rm)
	estados.clear()
	terminadas.clear()
	errores.clear()
	rm.mensaje_para.connect(_on_mensaje_para)


func _on_mensaje_para(peer: int, m: Dictionary) -> void:
	match m["tipo"]:
		MensajesRed.ESTADO_PARTIDA:
			estados[peer] = m["payload"]
		MensajesRed.PARTIDA_TERMINADA:
			terminadas[peer] = m["payload"]["resultado"]
		MensajesRed.ERROR:
			errores.append(m["payload"]["mensaje"])


static func _usuario(posicion: int) -> String:
	return "%d0000000-0000-4000-8000-000000000000" % posicion


## Une a todos y juega hasta el final; devuelve cuántos mensajes se enviaron.
func _jugar_partida(capacidad: int, semilla: int) -> int:
	_preparar(capacidad)
	for posicion in capacidad:
		var peer := 10 + posicion
		rm.conectar(peer)
		rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {
			"usuario_id": _usuario(posicion),
			"token": JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO),
			"sala_id": SALA,
		}))
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var enviados := 0
	while terminadas.is_empty() and enviados < MAX_MENSAJES:
		var quien := -1
		for peer: int in estados:
			if not estados[peer]["jugadas_validas"].is_empty():
				quien = peer
		if quien == -1:
			break
		var validas: Array = estados[quien]["jugadas_validas"]
		var jugada: Dictionary = validas[rng.randi_range(0, validas.size() - 1)].duplicate()
		var tipo: String = jugada["tipo"]
		jugada.erase("tipo")
		rm.recibir(quien, MensajesRed.crear(tipo, jugada))
		enviados += 1
	return enviados


func _comprobar_final(capacidad: int, enviados: int) -> void:
	assert_lt(enviados, MAX_MENSAJES, "la partida termina")
	assert_eq(errores, [] as Array[String], "ninguna jugada válida se rechaza")
	assert_eq(terminadas.size(), capacidad, "todos reciben partida_terminada")
	var resultado: Dictionary = terminadas.values()[0]
	var ganador: int = resultado["equipo_ganador"]
	assert_true(ganador in [0, 1])
	assert_eq(resultado["puntos_por_equipo"][ganador], MotorMus.JUEGOS_PARA_GANAR)
	assert_eq(backend.partidas_registradas.size(), 1, "el resultado se registra en el backend")
	assert_eq(backend.partidas_registradas[0]["resultado"], resultado)
	assert_false(rm.salas_activas.has(SALA))


func test_partidas_completas_a_cuatro() -> void:
	for semilla in 3:
		var enviados := _jugar_partida(4, semilla)
		_comprobar_final(4, enviados)


func test_partidas_completas_a_dos() -> void:
	for semilla in 3:
		var enviados := _jugar_partida(2, 100 + semilla)
		_comprobar_final(2, enviados)
