extends GutTest
## Tiempo límite para decidir (PBI-12, issue #37): si a quien le toca no juega a
## tiempo, el servidor juega por él para que los demás no se queden atascados.
## El reloj de RoomManager se sustituye por uno falso que solo avanza a mano.

const MotorFalso := preload("res://tests/unit/server/game_engine/motor_falso.gd")
const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const LIMITE_S := RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO
const LIMITE_MS := int(LIMITE_S * 1000.0)
const AUSENTE_MS := int(RoomManager.SEGUNDOS_DE_AUSENTE * 1000.0)


## Como MotorFalso, pero quien no tiene el turno puede "cantar" cuando quiera:
## es una jugada opcional, así que no le pone cuenta atrás.
class MotorConCante:
	extends "res://tests/unit/server/game_engine/motor_falso.gd"

	func tipos_de_jugada_opcionales() -> Array[String]:
		return ["cantar"]

	func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
		var validas := super(estado, jugador_id)
		if not ha_terminado(estado) and jugador_id != estado.get("turno"):
			validas.append({"tipo": "cantar"})
		return validas

	func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
		if jugada["tipo"] != "cantar":  # cantar no cambia nada en este juego
			super(estado, jugador_id, jugada)


## Como MotorFalso, pero con 5 cartas por jugador: da para varias jugadas seguidas.
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


func _preparar(juego: String, motores: Dictionary, capacidad := 2, segundos := LIMITE_S) -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in capacidad:
		participantes.append({"usuario_id": _usuario(posicion), "posicion": posicion, "equipo": posicion % 2})
	backend.salas[SALA] = {
		"id": SALA, "juego": juego, "estado": "esperando", "capacidad": capacidad,
		"participantes": participantes,
	}
	rm = RoomManager.new(backend, SECRETO, motores, segundos)
	ahora = 1000
	rm.reloj = func() -> int: return ahora
	add_child_autofree(rm)
	enviados.clear()
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))
	for posicion in capacidad:
		var peer := 10 + posicion
		rm.conectar(peer)
		rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA, {
			"usuario_id": _usuario(posicion),
			"token": JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO),
			"sala_id": SALA,
		}))


static func _usuario(posicion: int) -> String:
	return "%d0000000-0000-4000-8000-000000000000" % posicion


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


func _estado(peer: int) -> Dictionary:
	return _de(peer, MensajesRed.ESTADO_PARTIDA).back()["payload"]


func _avanzar_reloj(ms: int) -> void:
	ahora += ms
	rm.comprobar_tiempos()


# --- RoomManager ---

func test_el_estado_dice_cuanto_tiempo_le_queda_a_quien_tiene_que_jugar() -> void:
	_preparar("falso", {"falso": MotorFalso})
	var tiempos: Array = _estado(11)["tiempos_para_decidir"]
	assert_eq(tiempos.size(), 1, "solo cuenta el tiempo de quien tiene el turno")
	assert_eq(tiempos[0]["posicion"], 0)
	assert_almost_eq(tiempos[0]["segundos"], LIMITE_S, 0.01)


func test_antes_de_agotar_el_tiempo_no_pasa_nada() -> void:
	_preparar("falso", {"falso": MotorFalso})
	_avanzar_reloj(LIMITE_MS - 1)
	assert_eq(_estado(10)["turno"], 0)
	assert_eq(_estado(10)["mi_mano"].size(), 2)


func test_al_agotar_el_tiempo_el_servidor_juega_por_el_y_se_lo_dice() -> void:
	_preparar("falso", {"falso": MotorFalso})
	_avanzar_reloj(LIMITE_MS)
	assert_eq(_estado(11)["turno"], 1, "la partida sigue: le toca al otro")
	assert_eq(_estado(10)["mi_mano"].size(), 1, "se ha echado una carta suya")
	assert_eq(_de(10, MensajesRed.ERROR).back()["payload"]["mensaje"], RoomManager.AVISO_TIEMPO_AGOTADO)
	assert_eq(_de(11, MensajesRed.ERROR), [] as Array[Dictionary], "al otro no se le avisa de nada")


func test_quien_pasa_a_tener_el_turno_estrena_su_tiempo() -> void:
	_preparar("falso", {"falso": MotorFalso})
	_avanzar_reloj(20000)
	rm.recibir(10, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": _estado(10)["mi_mano"][0]}))
	var tiempos: Array = _estado(10)["tiempos_para_decidir"]
	assert_eq(tiempos[0]["posicion"], 1)
	assert_almost_eq(tiempos[0]["segundos"], LIMITE_S, 0.01)
	_avanzar_reloj(LIMITE_MS - 1)
	assert_eq(_estado(10)["turno"], 1, "los 20 s que gastó el otro no cuentan para él")


func test_una_jugada_opcional_no_pone_cuenta_atras_ni_reinicia_la_del_otro() -> void:
	_preparar("falso", {"falso": MotorConCante})
	assert_eq(_estado(10)["tiempos_para_decidir"].map(func(t: Dictionary) -> int: return t["posicion"]), [0])
	_avanzar_reloj(20000)
	rm.recibir(11, MensajesRed.crear("cantar", {}))
	assert_almost_eq(_estado(10)["tiempos_para_decidir"][0]["segundos"], LIMITE_S - 20.0, 0.01,
		"el jugador 0 conserva lo que le quedaba")


func test_tambien_juega_por_quien_se_ha_desconectado() -> void:
	_preparar("falso", {"falso": MotorFalso})
	rm.desconectar(10)
	_avanzar_reloj(LIMITE_MS)
	assert_eq(_estado(11)["turno"], 1)


func test_si_nadie_juega_la_partida_termina_igualmente() -> void:
	_preparar("falso", {"falso": MotorFalso})
	for i in 10:
		_avanzar_reloj(LIMITE_MS)
	assert_eq(_de(10, MensajesRed.PARTIDA_TERMINADA).size(), 1)
	assert_false(rm.salas_activas.has(SALA))
	assert_eq(backend.partidas_registradas.size(), 1)


func test_con_cero_segundos_no_hay_tiempo_limite() -> void:
	_preparar("falso", {"falso": MotorFalso}, 2, 0.0)
	assert_eq(_estado(10)["tiempos_para_decidir"], [])
	_avanzar_reloj(LIMITE_MS * 100)
	assert_eq(_estado(10)["turno"], 0)


# --- Modo ausente ---

func _jugar_a_mano(peer: int) -> void:
	rm.recibir(peer, MensajesRed.crear(MensajesRed.JUGAR_CARTA, {"carta_id": _estado(peer)["mi_mano"][0]}))


func _errores(peer: int) -> Array:
	return _de(peer, MensajesRed.ERROR).map(func(e: Dictionary) -> String: return e["payload"]["mensaje"])


## Deja al jugador 0 ausente: se le acaba el tiempo dos veces seguidas mientras
## el 1 juega él. Al terminar le toca otra vez al 0.
func _dejar_ausente_al_0() -> void:
	_preparar("falso", {"falso": MotorLargo})
	_avanzar_reloj(LIMITE_MS)  # 1.ª vez del 0
	_jugar_a_mano(11)
	_avanzar_reloj(LIMITE_MS)  # 2.ª vez seguida del 0
	_jugar_a_mano(11)


func test_la_primera_vez_solo_se_avisa_de_que_se_ha_jugado_por_el() -> void:
	_preparar("falso", {"falso": MotorLargo})
	_avanzar_reloj(LIMITE_MS)
	assert_eq(_errores(10), [RoomManager.AVISO_TIEMPO_AGOTADO])
	assert_false(_estado(10)["tiempos_para_decidir"].any(func(t: Dictionary) -> bool: return t["ausente"]))


func test_a_la_segunda_vez_seguida_se_le_da_por_ausente_y_se_le_avisa() -> void:
	_dejar_ausente_al_0()
	assert_eq(_errores(10), [RoomManager.AVISO_TIEMPO_AGOTADO, RoomManager.AVISO_AUSENTE])


func test_el_ausente_tiene_solo_dos_segundos_y_todos_lo_saben() -> void:
	_dejar_ausente_al_0()
	var tiempo: Dictionary = _estado(11)["tiempos_para_decidir"][0]
	assert_eq(tiempo["posicion"], 0)
	assert_true(tiempo["ausente"], "el cliente de los demás sabe que está ausente")
	assert_almost_eq(tiempo["segundos"], RoomManager.SEGUNDOS_DE_AUSENTE, 0.01)


func test_al_ausente_se_le_juega_a_los_dos_segundos_y_sin_mas_avisos() -> void:
	_dejar_ausente_al_0()
	_avanzar_reloj(AUSENTE_MS - 1)
	assert_eq(_estado(11)["turno"], 0, "aún no")
	_avanzar_reloj(1)
	assert_eq(_estado(11)["turno"], 1, "el servidor ya ha jugado por él")
	assert_eq(_errores(10).size(), 2, "no se le vuelve a avisar en cada turno")


func test_si_el_ausente_vuelve_a_jugar_recupera_su_tiempo_normal() -> void:
	_dejar_ausente_al_0()
	_jugar_a_mano(10)
	_jugar_a_mano(11)
	var tiempo: Dictionary = _estado(10)["tiempos_para_decidir"][0]
	assert_eq(tiempo["posicion"], 0)
	assert_false(tiempo["ausente"])
	assert_almost_eq(tiempo["segundos"], LIMITE_S, 0.01)


func test_agotar_el_tiempo_una_vez_y_jugar_despues_no_acumula() -> void:
	# Las veces tienen que ser seguidas: si juega entre medias, empieza de cero.
	_preparar("falso", {"falso": MotorLargo})
	_avanzar_reloj(LIMITE_MS)
	_jugar_a_mano(11)
	_jugar_a_mano(10)
	_jugar_a_mano(11)
	_avanzar_reloj(LIMITE_MS)
	assert_eq(_errores(10), [RoomManager.AVISO_TIEMPO_AGOTADO, RoomManager.AVISO_TIEMPO_AGOTADO])
	_jugar_a_mano(11)
	assert_false(_estado(10)["tiempos_para_decidir"][0]["ausente"])


# --- Partidas reales sin que nadie toque nada ---

## Juega solo con el tiempo agotado hasta que acaba (o se pasa de vueltas).
func _jugar_solo_por_tiempo(max_vueltas: int) -> void:
	for i in max_vueltas:
		if not rm.salas_activas.has(SALA):
			return
		_avanzar_reloj(LIMITE_MS)


func test_guinote_a_dos_termina_aunque_nadie_juegue() -> void:
	_preparar("guinote", MainServer.MOTORES, 2)
	_jugar_solo_por_tiempo(200)
	assert_false(rm.salas_activas.has(SALA), "la partida acaba")
	assert_eq(_de(10, MensajesRed.PARTIDA_TERMINADA).size(), 1)


func test_guinote_a_cuatro_termina_aunque_nadie_juegue() -> void:
	_preparar("guinote", MainServer.MOTORES, 4)
	_jugar_solo_por_tiempo(400)
	assert_false(rm.salas_activas.has(SALA), "la partida acaba")


func test_tute_a_dos_termina_aunque_nadie_juegue() -> void:
	_preparar("tute", MainServer.MOTORES, 2)
	_jugar_solo_por_tiempo(300)
	assert_false(rm.salas_activas.has(SALA), "la partida acaba")


func test_tute_por_parejas_termina_aunque_nadie_juegue() -> void:
	_preparar("tute", MainServer.MOTORES, 4)
	_jugar_solo_por_tiempo(300)
	assert_false(rm.salas_activas.has(SALA), "la partida acaba")


func test_mus_termina_aunque_nadie_juegue() -> void:
	_preparar("mus", MainServer.MOTORES, 4)
	_jugar_solo_por_tiempo(5000)
	assert_false(rm.salas_activas.has(SALA), "la partida acaba")


# --- Qué juega cada motor por tiempo ---

func test_en_el_mus_se_corta_el_mus() -> void:
	var motor := MotorMus.new()
	var estado := motor.iniciar(4) as EstadoMus
	var turno: int = estado.turno
	assert_eq(motor.jugada_por_tiempo(estado, turno), {"tipo": MensajesRed.NO_MUS})
	assert_eq(motor.jugadores_esperados(estado), [turno] as Array[int])


func test_en_el_tute_cantar_y_el_capote_no_obligan_a_nadie() -> void:
	for jugadores: int in [2, 4]:
		var motor := MotorTute.new()
		var estado := motor.iniciar(jugadores)
		assert_has(motor.tipos_de_jugada_opcionales(), MensajesRed.CANTAR)
		assert_has(motor.tipos_de_jugada_opcionales(), MensajesRed.CAPOTE)
		var esperados := motor.jugadores_esperados(estado)
		assert_eq(esperados.size(), 1, "solo quien tiene que echar carta (a %d)" % jugadores)
		assert_eq(motor.jugada_por_tiempo(estado, esperados[0])["tipo"], MensajesRed.JUGAR_CARTA)


func test_en_el_guinote_se_echa_una_carta_y_cantar_no_obliga() -> void:
	var motor := MotorGuinote.new()
	var estado := motor.iniciar(4) as EstadoGuinote
	assert_eq(motor.jugadores_esperados(estado), [estado.turno] as Array[int])
	assert_eq(motor.jugada_por_tiempo(estado, estado.turno)["tipo"], MensajesRed.JUGAR_CARTA)
	assert_eq(motor.jugada_por_tiempo(estado, (estado.turno + 1) % 4), {}, "quien no tiene turno no debe nada")


# --- Configuración en el arranque del servidor ---

func test_el_tiempo_por_turno_se_lee_del_entorno() -> void:
	assert_eq(MainServer.leer_segundos_por_turno(""), RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO)
	assert_eq(MainServer.leer_segundos_por_turno("45"), 45.0)
	assert_eq(MainServer.leer_segundos_por_turno("0"), 0.0, "0 desactiva el tiempo límite")
	assert_eq(MainServer.leer_segundos_por_turno("treinta"), RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO)
	assert_eq(MainServer.leer_segundos_por_turno("-5"), RoomManager.SEGUNDOS_POR_TURNO_POR_DEFECTO)
