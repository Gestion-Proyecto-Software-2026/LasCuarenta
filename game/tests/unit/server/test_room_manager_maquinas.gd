extends GutTest
## Plazas de máquina en el servidor de partida (PBI-20): salen en la sala de espera,
## cuentan para poder empezar, juegan solas con un retardo, no tienen cuenta atrás,
## no se guardan como usuarios y la partida no cuenta para el ranking.

const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const U0 := "00000000-0000-4000-8000-000000000000"
const U1 := "11111111-1111-4111-8111-111111111111"

var backend: Node
var rm: RoomManager
var enviados: Array[Dictionary] = []  # { peer, tipo, payload }
var ahora := 0


func before_each() -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	backend.salas[SALA] = _sala(2, [{"posicion": 1, "dificultad": "normal"}], [U0])
	rm = RoomManager.new(backend, SECRETO, {"guinote": preload("res://server/game_engine/guinote/motor_guinote.gd")})
	rm.retardo_maquina_ms = 0
	rm.reloj = func() -> int: return ahora
	add_child_autofree(rm)
	enviados.clear()
	ahora = 0
	rm.mensaje_para.connect(func(peer: int, m: Dictionary) -> void:
		enviados.append({"peer": peer, "tipo": m["tipo"], "payload": m["payload"]}))


# --- Ayudas ---

func _sala(capacidad: int, maquinas: Array, personas: Array) -> Dictionary:
	var participantes := []
	for i in personas.size():
		participantes.append({"usuario_id": personas[i], "posicion": i, "equipo": i % 2, "nombre_visible": "Persona %d" % i})
	return {"id": SALA, "juego": "guinote", "estado": "esperando", "capacidad": capacidad,
		"creador_id": personas[0], "participantes": participantes, "maquinas": maquinas}


func _unirse(peer: int, usuario: String) -> void:
	rm.conectar(peer)
	rm.recibir(peer, MensajesRed.crear(MensajesRed.UNIRSE_PARTIDA,
		{"usuario_id": usuario, "token": JwtDePrueba.firmar({"id": usuario}, SECRETO), "sala_id": SALA}))


func _de(peer: int, tipo: String) -> Array[Dictionary]:
	return enviados.filter(func(e: Dictionary) -> bool: return e["peer"] == peer and e["tipo"] == tipo)


func _empezar() -> void:
	rm.recibir(10, MensajesRed.crear(MensajesRed.EMPEZAR_PARTIDA))


## Juega cartas por la persona (la primera válida) y deja jugar a la máquina,
## hasta que acaba la partida o se agotan los pasos.
func _jugar_hasta_el_final() -> void:
	var sala: SalaActiva = rm.salas_activas.get(SALA)
	var pasos := 0
	while rm.salas_activas.has(SALA) and pasos < 400:
		pasos += 1
		sala = rm.salas_activas[SALA]
		var esperados := sala.motor.jugadores_esperados(sala.estado)
		if esperados.has(0):
			var jugada := sala.motor.jugada_por_tiempo(sala.estado, 0)
			rm.recibir(10, MensajesRed.crear(jugada["tipo"], jugada))
		else:
			rm.comprobar_maquinas()


# --- Sala de espera ---

func test_la_maquina_sale_en_la_sala_de_espera_con_su_nombre_y_dificultad() -> void:
	_unirse(10, U0)
	var vista: Dictionary = _de(10, MensajesRed.SALA_ACTUALIZADA).back()["payload"]
	var jugadores: Array = vista["jugadores"]
	assert_eq(jugadores.size(), 2)
	var maquina: Dictionary = jugadores[1]
	assert_true(maquina["maquina"])
	assert_eq(maquina["nombre"], "Máquina · Normal")
	assert_eq(maquina["dificultad"], "normal")
	assert_eq(maquina["posicion"], 1)
	assert_true(maquina["conectado"], "las máquinas siempre están listas")


func test_con_la_plaza_ocupada_por_una_maquina_el_creador_puede_empezar() -> void:
	_unirse(10, U0)
	_empezar()
	assert_true(rm.salas_activas[SALA].empezada(), "empezó sin esperar a nadie más")
	assert_eq(_de(10, MensajesRed.PARTIDA_INICIADA).size(), 1)


func test_sin_la_maquina_y_con_una_plaza_vacia_no_se_puede_empezar() -> void:
	backend.salas[SALA] = _sala(2, [], [U0])
	_unirse(10, U0)
	_empezar()
	assert_false(rm.salas_activas[SALA].empezada())
	assert_eq(_de(10, MensajesRed.ERROR).size(), 1)


func test_partida_iniciada_marca_que_asiento_es_de_maquina() -> void:
	_unirse(10, U0)
	_empezar()
	var jugadores: Array = _de(10, MensajesRed.PARTIDA_INICIADA).back()["payload"]["config"]["jugadores"]
	assert_false(jugadores[0]["maquina"])
	assert_true(jugadores[1]["maquina"])
	assert_eq(jugadores[1]["nombre"], "Máquina · Normal")


func test_el_creador_cambia_la_dificultad_y_el_servidor_la_actualiza() -> void:
	_unirse(10, U0)
	backend.salas[SALA] = _sala(2, [{"posicion": 1, "dificultad": "dificil"}], [U0])
	rm.recibir(10, MensajesRed.crear(MensajesRed.ACTUALIZAR_SALA))
	var vista: Dictionary = _de(10, MensajesRed.SALA_ACTUALIZADA).back()["payload"]
	assert_eq(vista["jugadores"][1]["dificultad"], "dificil")
	assert_eq(vista["jugadores"][1]["nombre"], "Máquina · Difícil")


func test_quitar_la_maquina_deja_la_plaza_libre() -> void:
	_unirse(10, U0)
	backend.salas[SALA] = _sala(2, [], [U0])
	rm.recibir(10, MensajesRed.crear(MensajesRed.ACTUALIZAR_SALA))
	var vista: Dictionary = _de(10, MensajesRed.SALA_ACTUALIZADA).back()["payload"]
	assert_eq(vista["jugadores"].size(), 1)
	assert_false(rm.salas_activas[SALA].todos_conectados())


func test_una_maquina_en_una_plaza_de_persona_se_rechaza() -> void:
	backend.salas[SALA] = _sala(2, [{"posicion": 0, "dificultad": "normal"}], [U0])
	_unirse(10, U0)
	assert_eq(_de(10, MensajesRed.ERROR).size(), 1, "la sala está mal formada")
	assert_false(rm.salas_activas.has(SALA))


func test_una_dificultad_desconocida_se_rechaza() -> void:
	backend.salas[SALA] = _sala(2, [{"posicion": 1, "dificultad": "imposible"}], [U0])
	_unirse(10, U0)
	assert_eq(_de(10, MensajesRed.ERROR).size(), 1)


# --- Durante la partida ---

func test_la_maquina_espera_su_retardo_antes_de_jugar() -> void:
	rm.retardo_maquina_ms = 1000
	_unirse(10, U0)
	_empezar()
	var sala: SalaActiva = rm.salas_activas[SALA]
	# Llevamos la partida hasta que le toque a la máquina.
	var pasos := 0
	while not sala.motor.jugadores_esperados(sala.estado).has(1) and pasos < 10:
		pasos += 1
		var jugada := sala.motor.jugada_por_tiempo(sala.estado, 0)
		rm.recibir(10, MensajesRed.crear(jugada["tipo"], jugada))
		sala = rm.salas_activas[SALA]
	var numero_antes: int = sala.ultima_jugada.get("numero", 0)
	rm.comprobar_maquinas()
	assert_eq(sala.ultima_jugada.get("numero", 0), numero_antes, "todavía no ha pasado su retardo")
	ahora += 3000
	rm.comprobar_maquinas()
	assert_eq(sala.ultima_jugada.get("numero", 0), numero_antes + 1, "ya ha jugado")


func test_la_maquina_no_tiene_cuenta_atras() -> void:
	_unirse(10, U0)
	_empezar()
	var sala: SalaActiva = rm.salas_activas[SALA]
	assert_false(sala.limite_de.has(1), "a la máquina no se le acaba el tiempo")


func test_una_partida_entera_contra_la_maquina_termina_y_solo_guarda_a_la_persona() -> void:
	_unirse(10, U0)
	_empezar()
	_jugar_hasta_el_final()
	assert_false(rm.salas_activas.has(SALA), "la partida terminó")
	assert_eq(_de(10, MensajesRed.PARTIDA_TERMINADA).size(), 1)
	assert_eq(backend.partidas_registradas.size(), 1)
	var guardada: Dictionary = backend.partidas_registradas[0]
	assert_eq(guardada["jugadores"].size(), 1, "solo la persona, la máquina no es un usuario")
	assert_eq(guardada["jugadores"][0]["usuario_id"], U0)
	assert_true(guardada["resultado"]["contra_maquina"], "marcada para que no cuente en el ranking")


func test_los_tres_niveles_terminan_la_partida() -> void:
	for nivel: String in ["facil", "normal", "dificil"]:
		backend.salas[SALA] = _sala(2, [{"posicion": 1, "dificultad": nivel}], [U0])
		backend.partidas_registradas.clear()
		rm.salas_activas.clear()
		rm._sala_de_peer.clear()
		_unirse(10, U0)
		_empezar()
		_jugar_hasta_el_final()
		assert_false(rm.salas_activas.has(SALA), "nivel %s: la partida terminó" % nivel)
		rm.desconectar(10)


func test_con_cuatro_plazas_y_tres_maquinas_tambien_se_puede_empezar() -> void:
	backend.salas[SALA] = _sala(4, [
		{"posicion": 1, "dificultad": "facil"}, {"posicion": 2, "dificultad": "normal"},
		{"posicion": 3, "dificultad": "dificil"}], [U0])
	_unirse(10, U0)
	_empezar()
	assert_true(rm.salas_activas[SALA].empezada())
	_jugar_hasta_el_final()
	assert_false(rm.salas_activas.has(SALA), "la partida a 4 terminó")


func test_si_no_queda_ninguna_persona_no_se_guarda_la_partida() -> void:
	_unirse(10, U0)
	_empezar()
	rm.desconectar(10)
	var sala: SalaActiva = rm.salas_activas[SALA]
	var pasos := 0
	while rm.salas_activas.has(SALA) and pasos < 400:
		pasos += 1
		# La persona desconectada no juega: lo hace el servidor por ella al agotarse el tiempo.
		ahora += int(rm.segundos_por_turno * 1000) + 1
		rm.comprobar_tiempos()
		rm.comprobar_maquinas()
	assert_eq(backend.partidas_registradas.size(), 1, "sigue habiendo una persona sentada: se guarda")
	assert_not_null(sala)
