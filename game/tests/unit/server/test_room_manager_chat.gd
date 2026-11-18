extends GutTest
## Chat de la partida y denuncias (PBI-08) en RoomManager: canal aislado por
## sala, identidad puesta por el servidor, historial al reconectar, chat tras la
## partida y borrado al irse todos (HU-035), y denuncias que pausan la partida,
## congelan los relojes y terminan por renuncio si se admiten (HU-036). El reloj
## es falso y solo avanza a mano, como en test_tiempo_limite.gd.

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")
const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const OTRA_SALA := "8d0f7780-8536-41ef-a55c-f18ed2a01bf8"
const USUARIOS := [
	"00000000-0000-4000-8000-000000000000",
	"11111111-1111-4111-8111-111111111111",
	"22222222-2222-4222-8222-222222222222",
	"33333333-3333-4333-8333-333333333333",
]
const NOMBRES := ["Ana", "Luis", "Marta", "Pablo"]
const OTROS := ["44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555"]
const LIMITE_MS := int(RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO * 1000.0)
const PLAZO_MS := int(ChatSala.SEGUNDOS_PARA_ADMITIR * 1000.0)


## Como MotorFalso, pero con 5 cartas por jugador: da para jugar unas cuantas
## bazas antes de denunciar sin que la partida termine.
class MotorLargo:
	extends "res://tests/unit/server/game_engine/motor_falso.gd"

	func _iniciar(num_jugadores: int) -> EstadoPartida:
		var cartas := Baraja.crear()
		Baraja.barajar(cartas, rng)
		var estado := Estado.new()
		for i in num_jugadores:
			estado.manos.append(cartas.slice(i * 5, (i + 1) * 5))
		return estado


var backend: Node
var rm: RoomManager
var ahora := 0
var enviados: Array[Dictionary] = []  # { peer, tipo, payload }


func _preparar(capacidad := 4, motor: GDScript = MotorLargo, segundos := RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO) -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in capacidad:
		participantes.append({"usuario_id": USUARIOS[posicion], "posicion": posicion,
			"equipo": posicion % 2, "nombre_visible": NOMBRES[posicion]})
	backend.salas[SALA] = {"id": SALA, "juego": "falso", "estado": "esperando",
		"capacidad": capacidad, "participantes": participantes}
	backend.salas[OTRA_SALA] = {"id": OTRA_SALA, "juego": "falso", "estado": "esperando", "capacidad": 2,
		"participantes": [
			{"usuario_id": OTROS[0], "posicion": 0, "equipo": 0, "nombre_visible": "Eva"},
			{"usuario_id": OTROS[1], "posicion": 1, "equipo": 1, "nombre_visible": "Iker"},
		]}
	rm = RoomManager.new(backend, SECRETO, {"falso": motor}, segundos)
	rm.reloj = func() -> int: return ahora
	rm.reloj_fecha = func() -> String: return "2026-11-18T10:00:00Z"
	rm.espera_entre_intentos_s = 0.0
	add_child_autofree(rm)
	# Las comprobaciones de tiempos y denuncias se hacen a mano.
	rm.set_process(false)
	ahora = 0
	enviados.clear()
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))


# --- Ayudas ---

func _unirse(peer: int, usuario: String, sala := SALA) -> void:
	rm.conectar(peer)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA,
		{"usuario_id": usuario, "token": JwtDePrueba.firmar({"id": usuario}, SECRETO), "sala_id": sala}))


## Sienta a todos en SALA: el peer de cada asiento es 10 + asiento.
func _empezar(capacidad := 4) -> void:
	for posicion in capacidad:
		_unirse(10 + posicion, USUARIOS[posicion])


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


func _ultimo(peer: int, tipo: String) -> Dictionary:
	var lista := _de(peer, tipo)
	return lista.back()["payload"] if not lista.is_empty() else {}


func _ultimo_error(peer: int) -> String:
	return _ultimo(peer, MensajesRed.ERROR).get("mensaje", "")


func _chatear(peer: int, texto: Variant, extra := {}) -> void:
	var payload := {"mensaje": texto}
	payload.merge(extra)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.CHAT_ENVIAR, payload))


func _denunciar(peer: int, mensaje_id: Variant) -> void:
	rm.recibir(peer, MensajesRed.crear(MensajesRed.DENUNCIAR_CHAT, {"mensaje_id": mensaje_id}))


func _responder(peer: int, admite: bool) -> void:
	rm.recibir(peer, MensajesRed.crear(
		MensajesRed.ADMITIR_DENUNCIA if admite else MensajesRed.NO_ADMITIR_DENUNCIA, {}))


func _a_quien_le_toca() -> int:
	return int(_ultimo(10, MensajesRed.ESTADO_PARTIDA)["turno"])


## Juega la primera carta de quien tenga el turno (peer 10 + asiento).
func _jugar_carta() -> void:
	var peer := 10 + _a_quien_le_toca()
	var estado := _ultimo(peer, MensajesRed.ESTADO_PARTIDA)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": estado["mi_mano"][0]}))


# --- Chat: difusión, identidad y aislamiento (Jira CA1, CA4; HU-035 CA-129) ---

func test_el_mensaje_llega_a_todos_los_de_la_sala_con_su_identidad() -> void:
	_preparar()
	_empezar()
	_chatear(11, "¡Buena suerte!")
	for peer in [10, 11, 12, 13]:
		assert_eq(_de(peer, MensajesRed.CHAT_MENSAJE).size(), 1, "peer %d" % peer)
		assert_eq(_ultimo(peer, MensajesRed.CHAT_MENSAJE), {
			"id": 1, "usuario_id": USUARIOS[1], "posicion": 1, "equipo": 1, "nombre": "Luis",
			"mensaje": "¡Buena suerte!", "durante_partida": true,
		})


func test_el_chat_de_una_sala_no_llega_a_otra() -> void:
	_preparar()
	_empezar()
	_unirse(20, OTROS[0], OTRA_SALA)
	_unirse(21, OTROS[1], OTRA_SALA)
	_chatear(11, "solo para mi mesa")
	_chatear(20, "y esto solo para la mía")
	for peer in [10, 11, 12, 13]:
		var textos := _de(peer, MensajesRed.CHAT_MENSAJE).map(func(e: Dictionary) -> String: return e["payload"]["mensaje"])
		assert_eq(textos, ["solo para mi mesa"], "peer %d" % peer)
	for peer in [20, 21]:
		var textos := _de(peer, MensajesRed.CHAT_MENSAJE).map(func(e: Dictionary) -> String: return e["payload"]["mensaje"])
		assert_eq(textos, ["y esto solo para la mía"], "peer %d" % peer)
	assert_eq(_ultimo(20, MensajesRed.CHAT_MENSAJE)["id"], 1, "cada sala numera sus mensajes")


func test_la_identidad_la_pone_el_servidor_no_el_payload() -> void:
	_preparar()
	_empezar()
	_chatear(11, "soy Ana", {"usuario_id": USUARIOS[0], "nombre": "Ana", "posicion": 0, "equipo": 0, "id": 99})
	var mensaje := _ultimo(10, MensajesRed.CHAT_MENSAJE)
	assert_eq(mensaje["usuario_id"], USUARIOS[1])
	assert_eq(mensaje["nombre"], "Luis")
	assert_eq(mensaje["posicion"], 1)
	assert_eq(mensaje["id"], 1)


func test_hasta_500_caracteres_y_mensajes_no_validos() -> void:
	_preparar()
	_empezar()
	_chatear(10, "a".repeat(500))
	assert_eq(_ultimo(11, MensajesRed.CHAT_MENSAJE)["mensaje"].length(), 500)
	_chatear(10, "a".repeat(501))
	assert_eq(_ultimo_error(10), ChatSala.ERROR_LARGO)
	_chatear(10, "   ")
	assert_eq(_ultimo_error(10), ChatSala.ERROR_VACIO)
	_chatear(10, 42)
	assert_eq(_ultimo_error(10), ChatSala.ERROR_NO_ES_TEXTO)
	rm.recibir(10, MensajesRed.crear(MensajesRed.CHAT_ENVIAR, {}))
	assert_eq(_ultimo_error(10), ChatSala.ERROR_NO_ES_TEXTO)
	assert_eq(_de(11, MensajesRed.CHAT_MENSAJE).size(), 1, "los no válidos no se reenvían")
	_chatear(10, "una\nlínea")
	assert_eq(_ultimo(11, MensajesRed.CHAT_MENSAJE)["mensaje"], "una línea")


func test_sin_limite_de_frecuencia() -> void:
	_preparar()
	_empezar()
	for i in 50:
		_chatear(12, "mensaje %d" % i)
	var ids := _de(13, MensajesRed.CHAT_MENSAJE).map(func(e: Dictionary) -> int: return e["payload"]["id"])
	assert_eq(ids, range(1, 51))


func test_fuera_de_una_sala_no_hay_chat() -> void:
	_preparar()
	rm.conectar(30)
	_chatear(30, "hola")
	assert_eq(_ultimo_error(30), "Primero tienes que unirte a una partida")


func test_el_chat_no_toca_la_partida() -> void:
	_preparar()
	_empezar()
	var estados := _de(10, MensajesRed.ESTADO_PARTIDA).size()
	var turno := _a_quien_le_toca()
	_chatear(10 + turno, "pienso...")
	assert_eq(_de(10, MensajesRed.ESTADO_PARTIDA).size(), estados, "no se manda estado nuevo")
	assert_eq(rm.salas_activas[SALA].limite_de.get(turno), LIMITE_MS, "ni cambia su tiempo")
	_jugar_carta()
	assert_eq(_a_quien_le_toca(), (turno + 1) % 4, "y se sigue jugando igual")


# --- Historial del chat (HU-035 CA-130) ---

func test_antes_de_empezar_tambien_hay_chat_y_el_que_llega_lo_recibe() -> void:
	_preparar()
	_unirse(10, USUARIOS[0])
	assert_eq(_ultimo(10, MensajesRed.CHAT_HISTORIAL), {"mensajes": []})
	_chatear(10, "¿quién falta?")
	assert_false(_ultimo(10, MensajesRed.CHAT_MENSAJE)["durante_partida"])
	_unirse(11, USUARIOS[1])
	var historial: Array = _ultimo(11, MensajesRed.CHAT_HISTORIAL)["mensajes"]
	assert_eq(historial.map(func(m: Dictionary) -> String: return m["mensaje"]), ["¿quién falta?"])


func test_al_reconectarse_siguen_los_mensajes_de_la_partida() -> void:
	_preparar()
	_empezar()
	_chatear(10, "uno")
	_chatear(11, "dos")
	rm.desconectar(12)
	_chatear(13, "tres, sin Marta")
	_unirse(32, USUARIOS[2])
	assert_eq(_de(32, MensajesRed.PARTIDA_INICIADA).size(), 1)
	var historial: Array = _ultimo(32, MensajesRed.CHAT_HISTORIAL)["mensajes"]
	assert_eq(historial.map(func(m: Dictionary) -> String: return m["mensaje"]), ["uno", "dos", "tres, sin Marta"])
	assert_eq(historial[1]["nombre"], "Luis")
	_chatear(10, "¡hola de nuevo!")
	assert_eq(_ultimo(32, MensajesRed.CHAT_MENSAJE)["mensaje"], "¡hola de nuevo!")
	assert_eq(_de(12, MensajesRed.CHAT_MENSAJE).size(), 2, "la conexión vieja ya no recibe nada")


# --- Tras la partida (HU-035 CA-131) ---

func test_tras_terminar_se_sigue_chateando_y_se_borra_al_irse_todos() -> void:
	_preparar(2, MotorFalso)
	_empezar(2)
	for turno in 4:  # 2 jugadores x 2 cartas
		_jugar_carta()
	assert_eq(_de(10, MensajesRed.PARTIDA_TERMINADA).size(), 1)
	assert_false(rm.salas_activas.has(SALA))

	_chatear(10, "¡buena partida!")
	var mensaje := _ultimo(11, MensajesRed.CHAT_MENSAJE)
	assert_eq(mensaje["mensaje"], "¡buena partida!")
	assert_false(mensaje["durante_partida"])
	rm.recibir(11, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": "oros_1"}))
	assert_eq(_ultimo_error(11), MotorDeJuego.ERROR_PARTIDA_TERMINADA)
	_denunciar(11, 1)
	assert_eq(_ultimo_error(11), ChatSala.ERROR_SIN_PARTIDA)
	_unirse(40, USUARIOS[0])
	assert_eq(_ultimo_error(40), "La sala ya ha terminado", "no se puede volver a empezar")

	rm.desconectar(10)
	_chatear(11, "¿sigue alguien?")
	assert_eq(_ultimo(11, MensajesRed.CHAT_MENSAJE)["mensaje"], "¿sigue alguien?")
	assert_true(rm._salas_terminadas.has(SALA))
	rm.desconectar(11)
	assert_false(rm._salas_terminadas.has(SALA), "con todos en el lobby se borra el chat")


func test_si_nadie_sigue_conectado_al_terminar_no_se_guarda_nada() -> void:
	_preparar(2, MotorFalso)
	_empezar(2)
	for turno in 3:
		_jugar_carta()
	rm.desconectar(10)
	rm.desconectar(11)
	ahora += LIMITE_MS
	rm.comprobar_tiempos()  # el servidor juega la última carta: termina sin nadie
	assert_false(rm.salas_activas.has(SALA))
	assert_false(rm._salas_terminadas.has(SALA))


# --- Denuncias (HU-036) ---

## Partida a 4 con dos cartas ya jugadas y un mensaje de Luis (asiento 1).
func _con_mensaje_de_luis() -> void:
	_preparar()
	_empezar()
	_jugar_carta()
	_jugar_carta()
	_chatear(11, "tengo el as de oros")


func test_la_denuncia_pausa_la_partida_y_lo_avisa_a_todos() -> void:
	_con_mensaje_de_luis()
	ahora = 5000
	_denunciar(10, 1)
	for peer in [10, 11, 12, 13]:
		assert_eq(_ultimo(peer, MensajesRed.DENUNCIA_CHAT), {
			"estado": "pendiente", "mensaje_id": 1, "mensaje": "tengo el as de oros",
			"denunciante": 0, "denunciado": 1, "equipo_denunciado": 1, "segundos": 60.0,
			"respondido_por": -1,
		})
	var peer_turno := 10 + _a_quien_le_toca()
	var estados := _de(10, MensajesRed.ESTADO_PARTIDA).size()
	_jugar_carta()
	assert_eq(_ultimo_error(peer_turno), RoomManager.ERROR_EN_PAUSA)
	assert_eq(_de(10, MensajesRed.ESTADO_PARTIDA).size(), estados, "nadie juega en pausa")
	_chatear(12, "eso no vale")
	assert_eq(_ultimo(13, MensajesRed.CHAT_MENSAJE)["mensaje"], "eso no vale", "el chat sigue")


func test_admitida_gana_la_parte_perjudicada_con_el_marcador_que_llevaba() -> void:
	_con_mensaje_de_luis()
	var puntos: Array = rm.salas_activas[SALA].motor.calcular_resultado(rm.salas_activas[SALA].estado)["puntos_por_equipo"]
	_denunciar(12, 1)
	_responder(13, true)  # Pablo, compañero de Luis
	for peer in [10, 11, 12, 13]:
		var denuncia := _ultimo(peer, MensajesRed.DENUNCIA_CHAT)
		assert_eq(denuncia["estado"], "admitida")
		assert_eq(denuncia["respondido_por"], 3)
		var resultado: Dictionary = _ultimo(peer, MensajesRed.PARTIDA_TERMINADA)["resultado"]
		assert_eq(resultado["causa"], "renuncio")
		assert_eq(resultado["equipo_ganador"], 0)
		assert_eq(resultado["puntos_por_equipo"], puntos, "el marcador del momento")
		var tipos := enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer) \
			.map(func(e: Dictionary) -> String: return e["tipo"])
		assert_true(tipos.rfind(MensajesRed.DENUNCIA_CHAT) < tipos.rfind(MensajesRed.PARTIDA_TERMINADA),
			"primero la denuncia admitida y después el fin")
	await wait_process_frames(1)
	assert_eq(backend.partidas_registradas.size(), 1, "se registra una sola vez")
	var registrada: Dictionary = backend.partidas_registradas[0]
	assert_eq(registrada["resultado"]["causa"], "renuncio")
	assert_eq(registrada["resultado"]["equipo_ganador"], 0)
	assert_eq(registrada["fecha_inicio"], "2026-11-18T10:00:00Z")


func test_no_admitida_se_reanuda_y_llega_un_estado_nuevo() -> void:
	_con_mensaje_de_luis()
	_denunciar(10, 1)
	var estados := _de(12, MensajesRed.ESTADO_PARTIDA).size()
	_responder(11, false)
	for peer in [10, 11, 12, 13]:
		assert_eq(_ultimo(peer, MensajesRed.DENUNCIA_CHAT)["estado"], "no_admitida")
	assert_eq(_de(12, MensajesRed.ESTADO_PARTIDA).size(), estados + 1)
	var turno := _a_quien_le_toca()
	_jugar_carta()
	assert_eq(_a_quien_le_toca(), (turno + 1) % 4, "se sigue jugando")
	assert_true(_de(10, MensajesRed.PARTIDA_TERMINADA).is_empty())


func test_sin_respuesta_en_un_minuto_caduca_y_se_reanuda() -> void:
	_con_mensaje_de_luis()
	ahora = 1000
	_denunciar(10, 1)
	ahora += PLAZO_MS - 1
	rm.comprobar_denuncias()
	assert_eq(_ultimo(10, MensajesRed.DENUNCIA_CHAT)["estado"], "pendiente")
	ahora += 1
	rm.comprobar_denuncias()
	assert_eq(_ultimo(10, MensajesRed.DENUNCIA_CHAT)["estado"], "caducada")
	assert_eq(_ultimo(10, MensajesRed.DENUNCIA_CHAT)["respondido_por"], -1)
	var turno := _a_quien_le_toca()
	_jugar_carta()
	assert_eq(_a_quien_le_toca(), (turno + 1) % 4, "se puede volver a jugar")


func test_caduca_aunque_el_tiempo_limite_este_desactivado() -> void:
	_preparar(4, MotorLargo, 0.0)
	_empezar()
	_chatear(11, "as de oros")
	_denunciar(10, 1)
	ahora += PLAZO_MS
	rm.comprobar_denuncias()
	assert_eq(_ultimo(10, MensajesRed.DENUNCIA_CHAT)["estado"], "caducada")


func test_la_pausa_congela_los_relojes_de_decision() -> void:
	_preparar()
	_empezar()
	_chatear(11, "as de oros")
	var turno := _a_quien_le_toca()
	ahora = 10000  # le quedan 35 s
	_denunciar(10, 1)
	ahora += 50000  # más de lo que le quedaba
	rm.comprobar_tiempos()
	assert_true(_de(10 + turno, MensajesRed.ERROR).is_empty(), "en pausa no se juega por nadie")
	_responder(11, false)
	var tiempos: Array = _ultimo(10, MensajesRed.ESTADO_PARTIDA)["tiempos_para_decidir"]
	assert_eq(tiempos, [{"posicion": turno, "segundos": 35.0, "ausente": false}])
	ahora += 35000 - 1
	rm.comprobar_tiempos()
	assert_eq(_a_quien_le_toca(), turno)
	ahora += 1
	rm.comprobar_tiempos()
	assert_eq(_a_quien_le_toca(), (turno + 1) % 4, "se le acaba justo lo que le quedaba")


func test_quien_se_reconecta_en_pausa_ve_la_denuncia_y_el_reloj_parado() -> void:
	_con_mensaje_de_luis()
	ahora = 2000
	_denunciar(10, 1)
	rm.desconectar(12)
	ahora += 20000
	_unirse(32, USUARIOS[2])
	var denuncia := _ultimo(32, MensajesRed.DENUNCIA_CHAT)
	assert_eq(denuncia["estado"], "pendiente")
	assert_eq(denuncia["segundos"], 40.0)
	var tiempos: Array = _ultimo(32, MensajesRed.ESTADO_PARTIDA)["tiempos_para_decidir"]
	# Jugó la última carta en el instante 0 y se denunció en el 2000: le quedan 43 s.
	assert_eq(tiempos[0]["segundos"], 43.0, "su reloj no ha corrido durante la pausa")


func test_reglas_de_quien_puede_denunciar() -> void:
	_preparar()
	_unirse(10, USUARIOS[0])
	_unirse(11, USUARIOS[1])
	_chatear(11, "antes de empezar")  # id 1
	_unirse(12, USUARIOS[2])
	_unirse(13, USUARIOS[3])
	_chatear(11, "durante")  # id 2
	_denunciar(13, 2)
	assert_eq(_ultimo_error(13), ChatSala.ERROR_NO_ES_RIVAL, "su compañero")
	_denunciar(11, 2)
	assert_eq(_ultimo_error(11), ChatSala.ERROR_NO_ES_RIVAL, "él mismo")
	_denunciar(10, 1)
	assert_eq(_ultimo_error(10), ChatSala.ERROR_ANTES_DE_EMPEZAR)
	_denunciar(10, 99)
	assert_eq(_ultimo_error(10), ChatSala.ERROR_NO_EXISTE)
	_denunciar(10, "2")
	assert_eq(_ultimo_error(10), ChatSala.ERROR_NO_EXISTE)
	assert_true(_de(10, MensajesRed.DENUNCIA_CHAT).is_empty(), "nada de eso pausa la partida")
	_denunciar(10, 2)
	_denunciar(12, 2)
	assert_eq(_ultimo_error(12), ChatSala.ERROR_YA_PENDIENTE)


func test_un_hecho_ya_denunciado_se_rechaza_sin_volver_a_pausar() -> void:
	_con_mensaje_de_luis()
	_denunciar(10, 1)
	_responder(11, false)
	var avisos := _de(10, MensajesRed.DENUNCIA_CHAT).size()
	_denunciar(12, 1)
	assert_eq(_ultimo_error(12), ChatSala.ERROR_YA_DENUNCIADO)
	assert_eq(_de(10, MensajesRed.DENUNCIA_CHAT).size(), avisos)
	var turno := _a_quien_le_toca()
	_jugar_carta()
	assert_eq(_a_quien_le_toca(), (turno + 1) % 4, "la partida no se ha pausado")


func test_solo_responde_la_parte_denunciada() -> void:
	_con_mensaje_de_luis()
	_responder(11, true)
	assert_eq(_ultimo_error(11), ChatSala.ERROR_SIN_DENUNCIA)
	_denunciar(10, 1)
	_responder(10, true)
	assert_eq(_ultimo_error(10), ChatSala.ERROR_NO_DENUNCIADO)
	_responder(12, false)
	assert_eq(_ultimo_error(12), ChatSala.ERROR_NO_DENUNCIADO)
	assert_eq(_ultimo(10, MensajesRed.DENUNCIA_CHAT)["estado"], "pendiente")
	rm.conectar(30)
	_denunciar(30, 1)
	assert_eq(_ultimo_error(30), "Primero tienes que unirte a una partida")


func test_mus_a_dos_el_rival_denuncia_y_el_autor_admite() -> void:
	_preparar(2)
	_empezar(2)
	_chatear(10, "llevo duples")
	_denunciar(11, 1)
	_responder(10, true)
	var resultado: Dictionary = _ultimo(11, MensajesRed.PARTIDA_TERMINADA)["resultado"]
	assert_eq(resultado["causa"], "renuncio")
	assert_eq(resultado["equipo_ganador"], 1, "gana el rival")
