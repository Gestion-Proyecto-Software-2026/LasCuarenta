extends GutTest
## PBI-08 de punta a punta, como pide el Issue #10: varias sesiones de la misma
## sala se escriben por el chat de su mesa y todas lo reciben; una sesión de
## otra sala no. Después, la denuncia completa: un rival denuncia desde su chat,
## todas las mesas se pausan, la pareja denunciada lo admite desde su panel y la
## partida termina por renuncio, con el resultado registrado en el backend. Cada
## jugador es una pantalla partida_mesa.tscn de verdad que habla con un
## RoomManager de verdad (motor de Guiñote) por red_en_bucle.gd.

const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")
const RedEnBucle := preload("res://tests/integration/red_en_bucle.gd")
const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const OTRA_SALA := "8d0f7780-8536-41ef-a55c-f18ed2a01bf8"
const NOMBRES := ["Ana", "Luis", "Marta", "Pablo"]

var backend: Node
var servidor: RoomManager
var redes: Array = []
var mesas: Array = []
var otras: Array = []


static func _usuario(posicion: int, sala := SALA) -> String:
	return "%d%d000000-0000-4000-8000-000000000000" % [posicion, 1 if sala == SALA else 2]


func _sala(sala: String, capacidad: int) -> Dictionary:
	var participantes := []
	for posicion in capacidad:
		participantes.append({"usuario_id": _usuario(posicion, sala), "posicion": posicion,
			"equipo": posicion % 2, "nombre_visible": NOMBRES[posicion]})
	return {"id": sala, "juego": "guinote", "estado": "esperando", "capacidad": capacidad,
		"participantes": participantes}


func _conectar(sala: String, posicion: int, peer: int) -> Node:
	var red: Node = RedEnBucle.new(servidor, peer)
	red.sala_id = sala
	add_child_autofree(red)
	return red


func before_each() -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	backend.salas[SALA] = _sala(SALA, 4)
	backend.salas[OTRA_SALA] = _sala(OTRA_SALA, 2)
	servidor = RoomManager.new(backend, SECRETO, MainServer.MOTORES)
	servidor.espera_entre_intentos_s = 0.0
	add_child_autofree(servidor)
	redes.clear()
	mesas.clear()
	otras.clear()
	for posicion in 4:
		redes.append(_conectar(SALA, posicion, 10 + posicion))
	for posicion in 2:
		otras.append(_conectar(OTRA_SALA, posicion, 20 + posicion))
	for posicion in 4:
		redes[posicion].unirse_partida(_usuario(posicion), JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO))
	for posicion in 2:
		var usuario := _usuario(posicion, OTRA_SALA)
		otras[posicion].unirse_partida(usuario, JwtDePrueba.firmar({"id": usuario}, SECRETO))
	# Como en el cliente: la mesa se abre cuando llega partida_iniciada.
	for posicion in 4:
		var mesa: Control = PARTIDA_MESA.instantiate()
		mesa.red = redes[posicion]
		mesa.pausa_baza = 0.0
		add_child_autofree(mesa)
		mesas.append(mesa)
	await wait_frames(1)


func _escribir(posicion: int, texto: String) -> void:
	var campo: LineEdit = mesas[posicion].chat.campo
	campo.text = texto
	campo.text_submitted.emit(texto)


func test_dos_sesiones_de_la_misma_sala_se_leen_y_otra_sala_no() -> void:
	_escribir(1, "¡Suerte a todos!")
	_escribir(2, "Igualmente")
	for posicion in 4:
		var visible: String = mesas[posicion].chat.texto_visible()
		assert_string_contains(visible, "J2 · Luis", "mesa %d" % posicion)
		assert_string_contains(visible, "¡Suerte a todos!", "mesa %d" % posicion)
		assert_string_contains(visible, "J3 · Marta", "mesa %d" % posicion)
		assert_eq(redes[posicion].chat.size(), 2)
	for red: Node in otras:
		assert_eq(red.chat, [], "el chat de una sala no llega a otra")
	assert_eq(redes[0].errores, [] as Array[String])


func test_denuncia_admitida_de_punta_a_punta() -> void:
	_escribir(1, "tengo el as de oros")
	var chat_de_ana: Control = mesas[0].chat
	assert_string_contains(chat_de_ana.historial.text, "[url=denunciar:1]")
	chat_de_ana.historial.meta_clicked.emit("denunciar:1")
	chat_de_ana.dialogo_denuncia.confirmed.emit()
	chat_de_ana.dialogo_denuncia.hide()
	await wait_frames(1)
	for posicion in 4:
		assert_true(mesas[posicion]._en_pausa, "mesa %d en pausa" % posicion)
		assert_true(mesas[posicion].chat.panel_denuncia.visible)
	assert_true(mesas[3].chat.boton_admitir.visible, "Pablo, compañero de Luis, puede responder")
	assert_false(mesas[2].chat.boton_admitir.visible, "Marta no")

	mesas[3].chat.boton_admitir.pressed.emit()
	await wait_frames(1)
	for posicion in 4:
		var mesa: Control = mesas[posicion]
		assert_true(mesa._terminada, "mesa %d terminada" % posicion)
		var panel: Control = mesa.tapete.find_child("PanelResultado", true, false)
		assert_string_contains((panel.get_child(0) as Label).text, "Gana la pareja A (Ana y Marta) por renuncio")
		assert_string_contains(mesa.chat.texto_visible(), "Denuncia admitida")
	assert_eq(backend.partidas_registradas.size(), 1)
	assert_eq(backend.partidas_registradas[0]["resultado"]["causa"], "renuncio")
	assert_eq(backend.partidas_registradas[0]["resultado"]["equipo_ganador"], 0)

	# Tras la partida se sigue hablando hasta volver al lobby.
	_escribir(1, "Perdón, se me escapó")
	for posicion in 4:
		assert_string_contains(mesas[posicion].chat.texto_visible(), "Perdón, se me escapó")


func test_denuncia_no_admitida_y_se_sigue_jugando() -> void:
	_escribir(1, "pinta oros")
	mesas[2].chat.denunciar(1)
	mesas[2].chat.dialogo_denuncia.confirmed.emit()
	mesas[2].chat.dialogo_denuncia.hide()
	mesas[1].chat.boton_no_admitir.pressed.emit()
	await wait_frames(1)
	for posicion in 4:
		assert_false(mesas[posicion]._en_pausa, "mesa %d sin pausa" % posicion)
		assert_false(mesas[posicion]._terminada)
		assert_string_contains(mesas[posicion].chat.texto_visible(), "Luis no admite la denuncia")
	var turno: int = redes[0].ultimo_estado["turno"]
	assert_false((redes[turno].ultimo_estado["jugadas_validas"] as Array).is_empty(),
		"a quien le toca vuelve a tener jugadas")
