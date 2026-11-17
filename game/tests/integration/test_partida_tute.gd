extends GutTest
## Partidas completas de Tute a través de RoomManager, como las juega el servidor:
## por mensajes del protocolo (§6), con el motor registrado en main_server.gd y
## cada jugador eligiendo al azar entre sus jugadas_validas. Mismo patrón que
## test_partida_guinote.gd.

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
		"id": SALA, "juego": "tute", "estado": "esperando", "capacidad": capacidad, "creador_id": _usuario(0),
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


func _unir_a_todos(capacidad: int) -> void:
	_preparar(capacidad)
	for posicion in capacidad:
		var peer := 10 + posicion
		rm.conectar(peer)
		rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {
			"usuario_id": _usuario(posicion),
			"token": JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO),
			"sala_id": SALA,
		}))
	rm.recibir(10, MensajesRed.crear(MensajesRed.EMPEZAR_PARTIDA))


## Une a todos y juega hasta el final; devuelve cuántos mensajes se enviaron.
func _jugar_partida(capacidad: int, semilla: int) -> int:
	_unir_a_todos(capacidad)
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


func _comprobar_final(capacidad: int, enviados: int) -> Dictionary:
	assert_lt(enviados, MAX_MENSAJES, "la partida termina")
	assert_eq(errores, [] as Array[String], "ninguna jugada válida se rechaza")
	assert_eq(terminadas.size(), capacidad, "todos reciben partida_terminada")
	var resultado: Dictionary = terminadas.values()[0]
	assert_true(resultado["equipo_ganador"] in [0, 1])
	assert_eq(backend.partidas_registradas.size(), 1, "el resultado se registra en el backend")
	assert_false(rm.salas_activas.has(SALA))
	return resultado


func test_partidas_completas_a_dos() -> void:
	var motivos := {}
	for semilla in 8:
		var resultado := _comprobar_final(2, _jugar_partida(2, semilla))
		motivos[resultado["motivo"]] = true
		assert_true(resultado["motivo"] in ["tantos", "vuelta", "capote"], "en el Tute de 2 no hay jugada de Tute")
		if resultado["motivo"] != "capote":
			var idas: Dictionary = resultado["manos"][0]
			assert_eq(idas["cartas"][0] + idas["cartas"][1], 120, "las cartas de las idas suman 120")


func test_partidas_completas_por_parejas() -> void:
	for semilla in 8:
		var resultado := _comprobar_final(4, _jugar_partida(4, 50 + semilla))
		assert_true(resultado["motivo"] in ["tantos", "tute"], "una sola mano: por tantos o por Tute")
		assert_eq(resultado["manos"].size(), 1, "el Tute por parejas no tiene vuelta")
		if resultado["motivo"] == "tantos":
			var mano: Dictionary = resultado["manos"][0]
			assert_eq(mano["cartas"][0] + mano["cartas"][1], 120, "las cartas suman 120")


func test_al_rechazar_una_carta_explica_por_que() -> void:
	_unir_a_todos(4)
	# Quien no tiene el turno intenta echar una carta suya.
	var turno: int = estados.values()[0]["turno"]
	var otro := 10 + (turno + 1) % 4
	var carta: String = estados[otro]["mi_mano"][0]
	rm.recibir(otro, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": carta}))
	assert_eq(errores.back(), "Espera tu turno.", "el jugador recibe el motivo, no solo «Jugada no válida»")
