extends GutTest
## Lo que la mesa común del cliente (PBI-12) necesita del servidor además de la
## vista: el nombre de cada jugador, quién ha hecho la última jugada y el motivo
## cuando se rechaza una.

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")
const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"

var backend: Node
var rm: RoomManager
var enviados: Array[Dictionary] = []  # { peer, tipo, payload }


func _preparar(juego: String, motores: Dictionary, nombres: Array) -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in nombres.size():
		var participante := {"usuario_id": _usuario(posicion), "posicion": posicion, "equipo": posicion % 2}
		if nombres[posicion] != null:
			participante["nombre_visible"] = nombres[posicion]
		participantes.append(participante)
	backend.salas[SALA] = {
		"id": SALA, "juego": juego, "estado": "esperando", "capacidad": nombres.size(), "creador_id": _usuario(0),
		"participantes": participantes,
	}
	rm = RoomManager.new(backend, SECRETO, motores)
	add_child_autofree(rm)
	enviados.clear()
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))
	for posicion in nombres.size():
		rm.conectar(10 + posicion)
		rm.recibir(10 + posicion, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {
			"usuario_id": _usuario(posicion),
			"token": JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO),
			"sala_id": SALA,
		}))
	rm.recibir(10, MensajesRed.crear(MensajesRed.EMPEZAR_PARTIDA))


static func _usuario(posicion: int) -> String:
	return "%d0000000-0000-4000-8000-000000000000" % posicion


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


func _estado(peer: int) -> Dictionary:
	return _de(peer, MensajesRed.ESTADO_PARTIDA).back()["payload"]


func _ultimo_error(peer: int) -> String:
	return _de(peer, MensajesRed.ERROR).back()["payload"]["mensaje"]


func test_partida_iniciada_lleva_el_nombre_de_cada_jugador() -> void:
	_preparar("falso", {"falso": MotorFalso}, ["Ana", null])
	var jugadores: Array = _de(10, MensajesRed.PARTIDA_INICIADA)[0]["payload"]["config"]["jugadores"]
	assert_eq(jugadores[0]["nombre"], "Ana")
	assert_eq(jugadores[1]["nombre"], "", "si el backend no da el nombre, vacío")
	assert_eq(jugadores[1]["posicion"], 1)


func test_el_resultado_que_va_al_backend_no_cambia_de_formato() -> void:
	_preparar("falso", {"falso": MotorFalso}, ["Ana", "Luis"])
	for i in 4:
		var peer := 10 + i % 2
		rm.recibir(peer, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": _estado(peer)["mi_mano"][0]}))
	assert_eq(backend.partidas_registradas.size(), 1)
	assert_eq(backend.partidas_registradas[0]["jugadores"][0].keys(), ["usuario_id", "posicion", "equipo"])


func test_antes_de_jugar_nadie_no_hay_ultima_jugada() -> void:
	_preparar("falso", {"falso": MotorFalso}, ["Ana", "Luis"])
	assert_eq(_estado(10)["ultima_jugada"], {})


func test_tras_cada_jugada_todos_saben_quien_ha_hecho_que() -> void:
	_preparar("falso", {"falso": MotorFalso}, ["Ana", "Luis"])
	var carta: String = _estado(10)["mi_mano"][0]
	rm.recibir(10, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": carta}))
	var esperada := {"numero": 1, "jugador_id": 0, "tipo": MensajesRed.JUGAR_CARTA, "carta_id": carta}
	assert_eq(_estado(10)["ultima_jugada"], esperada)
	assert_eq(_estado(11)["ultima_jugada"], esperada)
	rm.recibir(11, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": _estado(11)["mi_mano"][0]}))
	assert_eq(_estado(10)["ultima_jugada"]["numero"], 2, "el número distingue una jugada de la siguiente")
	assert_eq(_estado(10)["ultima_jugada"]["jugador_id"], 1)


func test_una_jugada_rechazada_no_cuenta_como_ultima_jugada() -> void:
	_preparar("falso", {"falso": MotorFalso}, ["Ana", "Luis"])
	rm.recibir(11, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": _estado(11)["mi_mano"][0]}))
	assert_eq(_de(11, MensajesRed.ERROR).size(), 1, "no es su turno")
	assert_eq(_estado(10)["ultima_jugada"], {})


func test_de_un_descarte_solo_se_dice_cuantas_cartas() -> void:
	var publica := RoomManager._jugada_publica(
		{"tipo": MensajesRed.DESCARTAR, "cartas": ["oros_1", "copas_7"]}, 2, 7)
	assert_eq(publica, {"numero": 7, "jugador_id": 2, "tipo": MensajesRed.DESCARTAR, "num_cartas": 2})


func test_los_datos_publicos_de_cantes_y_envites_se_conservan() -> void:
	assert_eq(RoomManager._jugada_publica({"tipo": MensajesRed.CANTAR, "palo": "oros"}, 1, 3)["palo"], "oros")
	assert_eq(RoomManager._jugada_publica({"tipo": MensajesRed.ENVIDAR, "cantidad": 5}, 1, 3)["cantidad"], 5)
	assert_eq(RoomManager._jugada_publica({"tipo": MensajesRed.CANTAR_TUTE, "figura": "reyes"}, 1, 3)["figura"], "reyes")


# --- Mus: lo que necesita la mesa ---

func test_la_vista_del_mus_dice_las_cartas_de_cada_uno_y_del_mazo() -> void:
	_preparar("mus", MainServer.MOTORES, ["Ana", "Luis", "Marta", "Pablo"])
	var vista := _estado(10)
	assert_eq(vista["cartas_por_jugador"], [4, 4, 4, 4])
	assert_eq(vista["cartas_en_mazo"], 24)
	assert_false(vista.has("manos"), "nunca las manos de los demás")


func test_el_mus_explica_por_que_rechaza_una_jugada() -> void:
	_preparar("mus", MainServer.MOTORES, ["Ana", "Luis", "Marta", "Pablo"])
	var turno: int = _estado(10)["turno"]
	var otro := 10 + (turno + 1) % 4
	rm.recibir(otro, MensajesRed.crear(MensajesRed.MUS, {}))
	assert_eq(_ultimo_error(otro), "Espera tu turno.")
	rm.recibir(10 + turno, MensajesRed.crear(MensajesRed.ENVIDAR, {"cantidad": 2}))
	assert_eq(_ultimo_error(10 + turno), "Todavía no se puede envidar: primero hay que decidir el mus.")
	rm.recibir(10 + turno, MensajesRed.crear(MensajesRed.DESCARTAR, {"cartas": []}))
	assert_eq(_ultimo_error(10 + turno), "Ahora no toca descartarse.")


func test_el_mus_no_inventa_motivos_para_lo_que_no_conoce() -> void:
	var motor := MotorMus.new()
	var estado := motor.iniciar(4) as EstadoMus
	assert_eq(motor.explicar_rechazo(estado, estado.turno, {"tipo": "bailar"}), "")
