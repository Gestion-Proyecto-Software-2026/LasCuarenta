extends GutTest
## Cuenta atrás del tiempo límite para decidir (PBI-14) en la mesa común.

const CuentaAtras := preload("res://client/ui/mesa/cuenta_atras.gd")
const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")

const JUGADORES_2 := [
	{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
	{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis"},
]
const ESTADO := {
	"fase": "robo", "dador": 1, "turno": 1, "palo_triunfo": "oros", "pinta": "oros_5",
	"cartas_en_mazo": 28, "mi_mano": ["oros_1", "copas_12"], "cartas_por_jugador": [6, 6],
	"baza_actual": [], "ultima_baza": {}, "bazas_por_equipo": [0, 0], "bazas_jugadas": 0,
	"cantes": [], "tute": {}, "esperando_cambio_siete": -1, "capote": -1, "mano": "idas",
	"tanteo_idas": [], "ultima_jugada": {}, "jugadas_validas": [],
}

var red
var partida: Control


func _nueva_cuenta() -> Label:
	var cuenta: Label = CuentaAtras.new()
	add_child_autofree(cuenta)
	return cuenta


func _abrir() -> void:
	red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": "guinote", "tu_posicion": 0, "jugadores": JUGADORES_2}
	add_child_autofree(red)
	partida = PARTIDA_MESA.instantiate()
	partida.red = red
	partida.pausa_baza = 0.0
	add_child_autofree(partida)
	await wait_frames(1)


func _con_tiempos(tiempos: Array) -> Dictionary:
	var estado := ESTADO.duplicate(true)
	estado["tiempos_para_decidir"] = tiempos
	return estado


func test_textos() -> void:
	assert_eq(CuentaAtras.texto(25, true, 1, 4), "Te quedan 25 s para jugar")
	assert_eq(CuentaAtras.texto(25, false, 0, 2), "El rival tiene 25 s para jugar")
	assert_eq(CuentaAtras.texto(7, false, 3, 4), "J4 tiene 7 s para jugar")
	assert_eq(CuentaAtras.texto(2, false, 3, 4, true), "J4 está ausente: juega el servidor")
	assert_eq(CuentaAtras.texto(2, false, 1, 2, true), "El rival está ausente: juega el servidor")


func test_si_te_toca_ensena_tu_tiempo() -> void:
	var cuenta := _nueva_cuenta()
	cuenta.actualizar({"tiempos_para_decidir": [
		{"posicion": 0, "segundos": 12.0}, {"posicion": 1, "segundos": 45.0}]}, 1, 4)
	assert_true(cuenta.visible)
	assert_eq(cuenta.text, "Te quedan 45 s para jugar")


func test_si_no_te_toca_ensena_el_de_quien_se_espera() -> void:
	var cuenta := _nueva_cuenta()
	cuenta.actualizar({"tiempos_para_decidir": [{"posicion": 2, "segundos": 9.2}]}, 1, 4)
	assert_eq(cuenta.text, "J3 tiene 10 s para jugar")


func test_si_el_que_se_espera_esta_ausente_se_dice() -> void:
	var cuenta := _nueva_cuenta()
	cuenta.actualizar({"tiempos_para_decidir": [{"posicion": 1, "segundos": 2.0, "ausente": true}]}, 0, 2)
	assert_eq(cuenta.text, "El rival está ausente: juega el servidor")


func test_sin_tiempos_no_se_ve() -> void:
	var cuenta := _nueva_cuenta()
	cuenta.actualizar({"tiempos_para_decidir": [{"posicion": 2, "segundos": 9.0}]}, 1, 4)
	cuenta.actualizar({}, 1, 4)
	assert_false(cuenta.visible, "un servidor sin tiempo límite no manda tiempos")


func test_la_mesa_la_muestra_con_el_estado_y_la_para_al_acabar() -> void:
	await _abrir()
	var cuenta: Label = partida.find_child("CuentaAtras", true, false)
	assert_not_null(cuenta)
	assert_false(cuenta.visible, "sin tiempos no se ve")
	red.estado_actualizado.emit(_con_tiempos([{"posicion": 1, "segundos": 45.0, "ausente": false}]))
	assert_true(cuenta.visible)
	assert_eq(cuenta.text, "Luis tiene 45 s para jugar".replace("Luis", "El rival"))
	red.estado_actualizado.emit(_con_tiempos([{"posicion": 0, "segundos": 30.0, "ausente": false}]))
	assert_eq(cuenta.text, "Te quedan 30 s para jugar")
	red.partida_terminada.emit({"equipo_ganador": 1, "puntos_por_equipo": [0, 1], "motivo": "tantos", "manos": []})
	assert_false(cuenta.visible, "al terminar la partida ya no hay cuenta atrás")


func test_el_tiempo_corre_aunque_la_mesa_este_enseñando_la_baza_anterior() -> void:
	# La cuenta atrás se actualiza al recibir el estado, no cuando la mesa lo enseña.
	await _abrir()
	partida.pausa_baza = 2.0
	var cuenta: Label = partida.find_child("CuentaAtras", true, false)
	var cerrada := ESTADO.duplicate(true)
	cerrada["turno"] = 0
	cerrada["baza_actual"] = []
	cerrada["ultima_jugada"] = {"numero": 1, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "oros_1"}
	cerrada["tiempos_para_decidir"] = [{"posicion": 0, "segundos": 45.0, "ausente": false}]
	red.estado_actualizado.emit(ESTADO)
	red.estado_actualizado.emit(cerrada)
	assert_true(cuenta.visible)
	assert_eq(cuenta.text, "Te quedan 45 s para jugar")
