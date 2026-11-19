extends GutTest
## Registro del resultado en el backend al terminar la partida (PBI-06): qué se
## manda a POST /interno/partidas (fechas y causa) y cuándo se reintenta. La
## fecha de RoomManager se sustituye por una falsa, como el reloj en
## test_tiempo_limite.gd, y la espera entre intentos se pone a 0.

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")
const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const U0 := "00000000-0000-4000-8000-000000000000"
const U1 := "11111111-1111-4111-8111-111111111111"
const INICIO := "2026-11-18T10:00:00Z"
const FIN := "2026-11-18T10:24:13Z"

const ACEPTADA := {"ok": true, "codigo": 201, "datos": {"id": "p1"}}
const SIN_RESPUESTA := {"ok": false, "codigo": 0, "datos": null}
const FALLO_DEL_BACKEND := {"ok": false, "codigo": 500, "datos": {"error": "error interno"}}
const YA_REGISTRADA := {"ok": false, "codigo": 409, "datos": {"error": "la partida de esta sala ya está registrada"}}
const MAL_FORMADA := {"ok": false, "codigo": 400, "datos": {"error": "jugadores no válido"}}

var backend: Node
var rm: RoomManager
var fecha := INICIO
var enviados: Array[Dictionary] = []  # { peer, tipo, payload }


func before_each() -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	backend.salas[SALA] = {
		"id": SALA, "juego": "falso", "estado": "esperando", "capacidad": 2, "creador_id": U0,
		"participantes": [
			{"usuario_id": U0, "posicion": 0, "equipo": 0},
			{"usuario_id": U1, "posicion": 1, "equipo": 1},
		],
	}
	rm = RoomManager.new(backend, SECRETO, {"falso": MotorFalso})
	rm.espera_entre_intentos_s = 0.0
	fecha = INICIO
	rm.reloj_fecha = func() -> String: return fecha
	add_child_autofree(rm)
	enviados.clear()
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))


# --- Ayudas ---

## Lo que contestará el backend a cada intento de registro, en orden.
func _responder(respuestas: Array) -> void:
	backend.respuestas_registro.assign(respuestas)


func _unirse(peer: int, usuario: String) -> void:
	rm.conectar(peer)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {
		"usuario_id": usuario,
		"token": JwtDePrueba.firmar({"id": usuario}, SECRETO),
		"sala_id": SALA,
	}))


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


## Empieza la partida (con la fecha [constant INICIO]) y la juega entera: con
## MotorFalso a 2 son 2 cartas por jugador. Termina con la fecha [constant FIN].
func _jugar_partida_entera() -> void:
	_unirse(10, U0)
	_unirse(11, U1)
	# PBI-09: la partida no empieza sola, la arranca el creador.
	rm.recibir(10, MensajesRed.crear(MensajesRed.EMPEZAR_PARTIDA))
	fecha = FIN
	for turno in 4:
		var peer := 10 if turno % 2 == 0 else 11
		var estado: Dictionary = _de(peer, MensajesRed.ESTADO_PARTIDA).back()["payload"]
		rm.recibir(peer, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": estado["mi_mano"][0]}))


## Una sala ya empezada, para cerrarla a mano con _terminar.
func _sala_empezada() -> SalaActiva:
	_unirse(10, U0)
	_unirse(11, U1)
	# PBI-09: la partida no empieza sola, la arranca el creador.
	rm.recibir(10, MensajesRed.crear(MensajesRed.EMPEZAR_PARTIDA))
	fecha = FIN
	return rm.salas_activas[SALA]


# --- Lo que se manda ---

func test_registra_la_partida_con_sus_fechas_y_la_causa() -> void:
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 1)
	var registro: Dictionary = backend.partidas_registradas[0]
	assert_eq(registro["sala_id"], SALA)
	assert_eq(registro["fecha_inicio"], INICIO, "la fecha en que empezó, no la de ahora")
	assert_eq(registro["fecha_fin"], FIN)
	assert_eq(registro["resultado"]["causa"], "completa")
	assert_has(registro["resultado"], "equipo_ganador")
	assert_eq(registro["jugadores"], [
		{"usuario_id": U0, "posicion": 0, "equipo": 0},
		{"usuario_id": U1, "posicion": 1, "equipo": 1},
	])


func test_los_jugadores_reciben_el_mismo_resultado_que_se_guarda() -> void:
	_jugar_partida_entera()

	for peer in [10, 11]:
		var fin := _de(peer, MensajesRed.PARTIDA_TERMINADA)
		assert_eq(fin.size(), 1)
		assert_eq(fin[0]["payload"]["resultado"]["causa"], "completa")
		assert_eq(fin[0]["payload"]["resultado"], backend.partidas_registradas[0]["resultado"])


func test_la_fecha_por_defecto_es_iso_8601_en_utc() -> void:
	var por_defecto := RoomManager.new(backend, SECRETO, {})
	var texto: String = por_defecto.reloj_fecha.call()
	por_defecto.free()
	assert_true(RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$").search(texto) != null,
		"'%s' tiene que ser AAAA-MM-DDThh:mm:ssZ" % texto)


func test_un_resultado_y_una_causa_de_fuera_del_motor_se_respetan() -> void:
	# Lo que hará el renuncio del chat (PBI-08): el marcador parcial y su causa.
	var sala := _sala_empezada()
	rm._terminar(sala, {"equipo_ganador": 1, "puntos_por_equipo": [30, 12]}, "renuncio")

	var registro: Dictionary = backend.partidas_registradas[0]
	assert_eq(registro["resultado"], {"equipo_ganador": 1, "puntos_por_equipo": [30, 12], "causa": "renuncio"})
	assert_eq(_de(10, MensajesRed.PARTIDA_TERMINADA)[0]["payload"]["resultado"]["causa"], "renuncio")
	assert_false(rm.salas_activas.has(SALA))


func test_sin_fecha_de_inicio_no_se_manda_una_vacia() -> void:
	var sala := _sala_empezada()
	sala.fecha_inicio = ""
	rm._terminar(sala)

	assert_false(backend.partidas_registradas[0].has("fecha_inicio"), "el backend usaría la de fin")


# --- Reintentos ---

func test_si_el_backend_acepta_a_la_primera_no_se_repite() -> void:
	_responder([ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 1)


func test_sin_respuesta_se_reintenta_hasta_que_llega() -> void:
	_responder([SIN_RESPUESTA, ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 2)
	assert_eq(backend.partidas_registradas[1], backend.partidas_registradas[0], "se repite la misma petición")


func test_un_fallo_del_backend_se_reintenta() -> void:
	_responder([FALLO_DEL_BACKEND, {"ok": false, "codigo": 503, "datos": null}, ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 3)


func test_si_ya_estaba_registrada_se_da_por_buena() -> void:
	# Un intento anterior llegó al backend aunque su respuesta se perdiera.
	_responder([SIN_RESPUESTA, YA_REGISTRADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 2, "tras el 409 no se insiste")
	assert_push_error_count(0, "un 409 no es un error")


func test_un_error_en_los_datos_no_se_reintenta() -> void:
	_responder([MAL_FORMADA, ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 1)
	assert_push_error("rechazó el resultado")


func test_tras_agotar_los_intentos_se_deja_constancia() -> void:
	_responder([SIN_RESPUESTA, FALLO_DEL_BACKEND, SIN_RESPUESTA, ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), RoomManager.INTENTOS_REGISTRO)
	assert_push_error("tras %d intentos" % RoomManager.INTENTOS_REGISTRO)


func test_entre_intentos_se_espera() -> void:
	rm.espera_entre_intentos_s = 0.05
	_responder([FALLO_DEL_BACKEND, ACEPTADA])
	_jugar_partida_entera()

	assert_eq(backend.partidas_registradas.size(), 1, "el segundo intento todavía no ha salido")
	await wait_seconds(0.3)
	assert_eq(backend.partidas_registradas.size(), 2)
