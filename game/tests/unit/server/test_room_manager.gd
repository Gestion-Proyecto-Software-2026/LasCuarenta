extends GutTest

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")
const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const U0 := "00000000-0000-4000-8000-000000000000"
const U1 := "11111111-1111-4111-8111-111111111111"
const INTRUSO := "99999999-9999-4999-8999-999999999999"

var backend: Node
var rm: RoomManager
var enviados: Array[Dictionary] = []  # { peer, tipo, payload }
var expulsados: Array[int] = []


func before_each() -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	backend.salas[SALA] = {
		"id": SALA, "juego": "falso", "estado": "esperando", "capacidad": 2,
		"participantes": [
			{"usuario_id": U0, "posicion": 0, "equipo": 0},
			{"usuario_id": U1, "posicion": 1, "equipo": 1},
		],
	}
	rm = RoomManager.new(backend, SECRETO, {"falso": MotorFalso})
	add_child_autofree(rm)
	enviados.clear()
	expulsados.clear()
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))
	rm.expulsar.connect(func(peer: int) -> void: expulsados.append(peer))


# --- Ayudas ---

func _unirse(peer: int, usuario: String, sala := SALA, token := "") -> void:
	rm.conectar(peer)
	if token.is_empty():
		token = JwtDePrueba.firmar({"id": usuario}, SECRETO)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA,
		{"usuario_id": usuario, "token": token, "sala_id": sala}))


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


func _ultimo_error(peer: int) -> String:
	var errores := _de(peer, MensajesRed.ERROR)
	return errores.back()["payload"]["mensaje"] if not errores.is_empty() else ""


func _jugar_primera_carta(peer: int) -> void:
	var estado: Dictionary = _de(peer, MensajesRed.ESTADO_PARTIDA).back()["payload"]
	rm.recibir(peer, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": estado["mi_mano"][0]}))


# --- unirse_partida: rechazos ---

func test_token_no_valido_expulsa() -> void:
	_unirse(10, U0, SALA, "no-es-un-token")
	assert_eq(_ultimo_error(10), "Token no válido o caducado")
	assert_eq(expulsados, [10])


func test_token_de_otro_usuario_expulsa() -> void:
	_unirse(10, U0, SALA, JwtDePrueba.firmar({"id": U1}, SECRETO))
	assert_eq(_ultimo_error(10), "Token no válido o caducado")
	assert_eq(expulsados, [10])


func test_payload_incompleto_expulsa_sin_consultar_al_backend() -> void:
	rm.conectar(10)
	rm.recibir(10, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {"usuario_id": U0}))
	rm.recibir(10, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA,
		{"usuario_id": U0, "token": "x", "sala_id": "../../admin"}))
	assert_eq(expulsados, [10, 10])
	assert_eq(backend.consultas_de_sala, 0)


func test_sala_inexistente_expulsa() -> void:
	_unirse(10, U0, "00000000-0000-4000-8000-00000000abcd")
	assert_eq(_ultimo_error(10), "La sala no existe")
	assert_eq(expulsados, [10])


func test_usuario_que_no_es_participante_expulsa() -> void:
	_unirse(10, INTRUSO)
	assert_eq(_ultimo_error(10), "No eres participante de esta sala")
	assert_eq(expulsados, [10])


func test_juego_no_disponible_y_sala_terminada() -> void:
	backend.salas[SALA]["juego"] = "mus"
	_unirse(10, U0)
	assert_eq(_ultimo_error(10), "Este juego todavía no está disponible")
	backend.salas[SALA]["juego"] = "falso"
	backend.salas[SALA]["estado"] = "finalizada"
	_unirse(11, U0)
	assert_eq(_ultimo_error(11), "La sala ya ha terminado")


func test_capacidad_no_admitida_por_el_juego() -> void:
	backend.salas[SALA]["capacidad"] = 3
	_unirse(10, U0)
	assert_eq(_ultimo_error(10), "La sala no tiene un número de jugadores válido para este juego")


# --- unirse_partida: flujo normal ---

func test_la_partida_empieza_cuando_estan_todos() -> void:
	_unirse(10, U0)
	assert_eq(_de(10, MensajesRed.PARTIDA_INICIADA).size(), 0, "falta un jugador")
	_unirse(11, U1)
	assert_eq(expulsados, [])
	for peer_y_posicion in [[10, 0], [11, 1]]:
		var inicio := _de(peer_y_posicion[0], MensajesRed.PARTIDA_INICIADA)
		assert_eq(inicio.size(), 1)
		var config: Dictionary = inicio[0]["payload"]["config"]
		assert_eq(config["tu_posicion"], peer_y_posicion[1])
		assert_eq(config["juego"], "falso")
		assert_eq(config["jugadores"].size(), 2)
		assert_eq(_de(peer_y_posicion[0], MensajesRed.ESTADO_PARTIDA).size(), 1)


func test_el_estado_incluye_las_jugadas_validas_de_cada_jugador() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	var estado_0: Dictionary = _de(10, MensajesRed.ESTADO_PARTIDA)[0]["payload"]
	var estado_1: Dictionary = _de(11, MensajesRed.ESTADO_PARTIDA)[0]["payload"]
	assert_eq(estado_0["jugadas_validas"].size(), 2, "le toca: puede jugar sus 2 cartas")
	assert_eq(estado_0["jugadas_validas"][0]["carta_id"], estado_0["mi_mano"][0])
	assert_eq(estado_1["jugadas_validas"], [] as Array[Dictionary], "no le toca")


func test_cada_jugador_recibe_solo_su_mano() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	var mano_0: Array = _de(10, MensajesRed.ESTADO_PARTIDA)[0]["payload"]["mi_mano"]
	var mano_1: Array = _de(11, MensajesRed.ESTADO_PARTIDA)[0]["payload"]["mi_mano"]
	assert_eq(mano_0.size(), 2)
	for carta in mano_0:
		assert_does_not_have(mano_1, carta)


func test_uniones_simultaneas_consultan_la_sala_una_sola_vez() -> void:
	backend.asincrono = true
	_unirse(10, U0)
	_unirse(11, U1)
	await wait_process_frames(3)
	assert_eq(backend.consultas_de_sala, 1)
	assert_eq(_de(10, MensajesRed.PARTIDA_INICIADA).size(), 1)
	assert_eq(_de(11, MensajesRed.PARTIDA_INICIADA).size(), 1)


func test_si_se_desconecta_mientras_se_consulta_no_se_le_sienta() -> void:
	backend.asincrono = true
	_unirse(10, U0)
	rm.desconectar(10)
	await wait_process_frames(3)
	assert_eq(enviados, [])
	assert_eq(rm.salas_activas[SALA].peer_en_posicion, {})


func test_unirse_dos_veces_con_la_misma_conexion() -> void:
	_unirse(10, U0)
	rm.recibir(10, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA,
		{"usuario_id": U0, "token": JwtDePrueba.firmar({"id": U0}, SECRETO), "sala_id": SALA}))
	assert_eq(_ultimo_error(10), "Ya estás en una partida")
	assert_eq(expulsados, [])


# --- Jugadas ---

func test_jugada_antes_de_unirse_o_de_empezar() -> void:
	rm.conectar(10)
	rm.recibir(10, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": "oros_1"}))
	assert_eq(_ultimo_error(10), "Primero tienes que unirte a una partida")
	_unirse(10, U0)
	rm.recibir(10, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": "oros_1"}))
	assert_eq(_ultimo_error(10), "La partida todavía no ha empezado")


func test_jugada_valida_actualiza_a_todos_e_invalida_solo_avisa_al_que_juega() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	_jugar_primera_carta(11)  # no es su turno
	assert_eq(_ultimo_error(11), MotorDeJuego.ERROR_SIN_JUGADAS)
	assert_eq(_de(10, MensajesRed.ESTADO_PARTIDA).size(), 1, "una jugada inválida no se difunde")

	_jugar_primera_carta(10)
	assert_eq(_de(10, MensajesRed.ESTADO_PARTIDA).size(), 2)
	assert_eq(_de(11, MensajesRed.ESTADO_PARTIDA).size(), 2)
	assert_eq(_de(11, MensajesRed.ESTADO_PARTIDA).back()["payload"]["turno"], 1)


func test_el_tipo_del_payload_no_sustituye_al_del_mensaje() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	var carta: String = _de(10, MensajesRed.ESTADO_PARTIDA)[0]["payload"]["mi_mano"][0]
	rm.recibir(10, MensajesRed.crear("apostar", {"tipo": "jugar_carta", "carta_id": carta}))
	assert_eq(_ultimo_error(10), MotorDeJuego.ERROR_JUGADA_NO_VALIDA)


func test_mensajes_mal_formados_y_chat() -> void:
	rm.conectar(10)
	rm.recibir(10, {"payload": {}})
	assert_eq(_ultimo_error(10), "Mensaje mal formado: se espera { tipo, payload }")
	rm.recibir(10, {"tipo": "jugar_carta", "payload": "texto"})
	assert_eq(_ultimo_error(10), "Mensaje mal formado: se espera { tipo, payload }")
	rm.recibir(10, MensajesRed.crear(MensajesRed.CHAT_ENVIAR, {"mensaje": "hola"}))
	assert_eq(_ultimo_error(10), "El chat todavía no está disponible")


func test_partida_completa_notifica_y_registra_en_el_backend() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	for turno in 4:  # 2 jugadores x 2 cartas
		_jugar_primera_carta(10 if turno % 2 == 0 else 11)
	await wait_process_frames(1)

	for peer in [10, 11]:
		var fin := _de(peer, MensajesRed.PARTIDA_TERMINADA)
		assert_eq(fin.size(), 1)
		assert_has(fin[0]["payload"]["resultado"], "equipo_ganador")
	assert_eq(backend.partidas_registradas.size(), 1)
	var registro: Dictionary = backend.partidas_registradas[0]
	assert_eq(registro["sala_id"], SALA)
	assert_eq(registro["jugadores"][1]["usuario_id"], U1)
	assert_false(rm.salas_activas.has(SALA), "la sala se libera al terminar")


# --- Reconexión ---

func test_reconexion_recupera_el_asiento_y_el_estado() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	_jugar_primera_carta(10)
	rm.desconectar(11)
	_unirse(21, U1)
	assert_eq(_de(21, MensajesRed.PARTIDA_INICIADA)[0]["payload"]["config"]["tu_posicion"], 1)
	assert_eq(_de(21, MensajesRed.ESTADO_PARTIDA)[0]["payload"]["turno"], 1)
	_jugar_primera_carta(21)
	assert_eq(_de(10, MensajesRed.ESTADO_PARTIDA).back()["payload"]["turno"], 0)


func test_una_segunda_sesion_del_mismo_usuario_expulsa_a_la_anterior() -> void:
	_unirse(10, U0)
	_unirse(20, U0)
	assert_eq(expulsados, [10])
	assert_eq(_ultimo_error(10), "Te has conectado a esta partida desde otra sesión")
	assert_eq(rm.salas_activas[SALA].peer_en_posicion[0], 20)
