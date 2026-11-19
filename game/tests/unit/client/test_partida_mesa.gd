extends GutTest
## La pantalla de partida común (PBI-12): pinta en la mesa lo que manda el
## servidor y envía lo que el jugador quiere hacer, para los tres juegos. No se
## prueba el arrastre con el ratón (interacción de bajo nivel, fuera del alcance
## de GUT) ni la navegación al lobby, igual que en el resto del cliente; las
## partidas completas están en tests/integration/test_mesa_seis_modos.gd.

const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")
const PartidaMesa := preload("res://client/ui/mesa/partida_mesa.gd")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")

const JUGADORES_2 := [
	{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
	{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": ""},
]
const JUGADORES_4 := [
	{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
	{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis"},
	{"usuario_id": "u2", "posicion": 2, "equipo": 0, "nombre": "Marta"},
	{"usuario_id": "u3", "posicion": 3, "equipo": 1, "nombre": "Pablo"},
]

## Guiñote a 2, recién repartido: me toca a mí (asiento 0).
const GUINOTE := {
	"fase": "robo", "dador": 1, "turno": 0, "palo_triunfo": "oros", "pinta": "oros_5",
	"cartas_en_mazo": 28,
	"mi_mano": ["oros_1", "copas_12", "copas_10", "bastos_10", "espadas_3", "oros_7"],
	"cartas_por_jugador": [6, 6], "baza_actual": [], "ultima_baza": {},
	"bazas_por_equipo": [0, 0], "bazas_jugadas": 0, "cantes": [], "tute": {},
	"esperando_cambio_siete": -1, "capote": -1, "mano": "idas", "tanteo_idas": [],
	"ultima_jugada": {},
	"jugadas_validas": [
		{"tipo": "jugar_carta", "carta_id": "oros_1"},
		{"tipo": "jugar_carta", "carta_id": "copas_12"},
		{"tipo": "cantar", "palo": "copas"},
		{"tipo": "cantar", "palo": "oros"},
		{"tipo": "cambiar_siete"},
	],
}

const MUS := {
	"fase": "mus", "mano": 1, "turno": 0, "mi_mano": ["oros_12", "copas_12", "bastos_1", "espadas_4"],
	"cartas_por_jugador": [4, 4, 4, 4], "cartas_en_mazo": 24,
	"cartas_pedidas": [0, 0, 0, 0], "rondas_de_descarte": 0, "lance": null, "hablan": [0, 1, 2, 3],
	"envite": {}, "lances_jugados": [], "tienen_pares": null, "tienen_juego": null,
	"piedras": [3, 7], "amarracos": [0, 1], "cobros": [], "juegos": [1, 0],
	"piedras_por_juego": 40, "juegos_para_ganar": 2, "ultima_mano": {},
	"ultima_jugada": {},
	"jugadas_validas": [{"tipo": "mus"}, {"tipo": "no_mus"}],
}

var red
var partida: Control


func _abrir(juego: String, jugadores: Array, estado: Dictionary, pausa := 0.0) -> void:
	red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": juego, "tu_posicion": 0, "jugadores": jugadores}
	red.ultimo_estado = estado
	add_child_autofree(red)
	partida = PARTIDA_MESA.instantiate()
	partida.red = red
	partida.pausa_baza = pausa
	add_child_autofree(partida)
	await wait_frames(1)


func _con(estado: Dictionary, cambios: Dictionary) -> Dictionary:
	var nuevo := estado.duplicate(true)
	nuevo.merge(cambios, true)
	return nuevo


func _tapete() -> Control:
	return partida.tapete


func _botones() -> Array:
	var caja := _tapete().find_child("Acciones", true, false)
	return caja.get_children().map(func(b: Button) -> String: return b.text) if caja else []


func _pulsar(texto: String) -> void:
	for boton: Button in _tapete().find_child("Acciones", true, false).get_children():
		if boton.text == texto:
			boton.pressed.emit()
			return
	fail_test("no hay ningún botón «%s»" % texto)


func _textos_en_la_mesa() -> Array:
	var textos := []
	for hijo in _tapete().get_children():
		if hijo is Label and hijo.visible:
			textos.append(hijo.text)
	return textos


func _etiqueta(asiento: int) -> String:
	return (_tapete().etiquetas_jugador[asiento].get_child(0) as Label).text


func _enviados() -> Array:
	return red.llamadas.filter(func(l: Array) -> bool: return l[0] == "enviar")


# --- Guiñote ---

func test_pinta_la_mano_los_dorsos_del_rival_y_el_mazo() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	assert_eq(_tapete().cartas_en_mano.map(func(c: Node) -> String: return c.id), GUINOTE["mi_mano"])
	assert_eq(_tapete().dorsos[1].get_child_count(), 6, "un dorso por carta del rival")
	assert_has(_textos_en_la_mesa(), "28 en el mazo")
	assert_not_null(_tapete().find_child("Pila", true, false), "con mazo, la pila va junto a la baza")


func test_las_etiquetas_llevan_el_asiento_y_el_nombre() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	assert_eq(_etiqueta(0), "J1 · Ana")
	assert_eq(_etiqueta(1), "J2", "sin nombre, solo el asiento")


func test_oscurece_las_cartas_que_no_se_pueden_echar() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	var cartas: Array = _tapete().cartas_en_mano
	assert_eq(cartas[0].self_modulate, Color.WHITE, "oros_1 se puede echar")
	assert_eq(cartas[2].self_modulate, _tapete().COLOR_NO_JUGABLE, "copas_10 no")


func test_un_boton_por_cada_jugada_que_no_es_echar_carta() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	assert_eq(_botones(), ["Cantar las 20 en copas", "Cantar las 40", "Cambiar el 7 por la pinta"])


func test_pulsar_un_boton_envia_la_jugada_al_servidor() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_pulsar("Cantar las 40")
	assert_eq(_enviados(), [["enviar", "cantar", {"palo": "oros"}]])
	assert_eq(_botones(), [], "los botones se quitan hasta que conteste el servidor")


func test_echar_una_carta_la_envia_al_servidor() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_tapete()._jugar_carta_en_mesa(_tapete().cartas_en_mano[0])
	assert_eq(_enviados(), [["enviar", "jugar_carta", {"carta_id": "oros_1"}]])
	assert_eq(_tapete().cartas_en_mano.size(), 5, "la carta sale de la mano hacia la mesa")


func test_si_el_servidor_la_rechaza_la_carta_vuelve_y_se_explica_por_que() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_tapete()._jugar_carta_en_mesa(_tapete().cartas_en_mano[2])
	red.error_recibido.emit("Tienes que asistir: echa una carta de oros.")
	assert_eq(_tapete().cartas_en_mano.size(), 6, "la carta vuelve a la mano")
	assert_null(_tapete().carta_en_mesa)
	assert_has(_textos_en_la_mesa(), "Tienes que asistir: echa una carta de oros.")


func test_tras_un_rechazo_vuelven_los_botones() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_pulsar("Cantar las 40")
	red.error_recibido.emit("Jugada no válida")
	assert_eq(_botones().size(), 3)


func test_cuando_el_servidor_acepta_mi_carta_se_queda_en_la_baza() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_tapete()._jugar_carta_en_mesa(_tapete().cartas_en_mano[0])
	red.estado_actualizado.emit(_con(GUINOTE, {
		"turno": 1, "mi_mano": GUINOTE["mi_mano"].slice(1), "cartas_por_jugador": [5, 6],
		"baza_actual": [{"jugador_id": 0, "carta_id": "oros_1"}], "jugadas_validas": [],
		"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_1"},
	}))
	assert_not_null(_tapete().carta_en_mesa)
	assert_eq(_tapete().carta_en_mesa.id, "oros_1")
	assert_eq(_tapete().cartas_en_mano.size(), 5)
	assert_eq(_tapete().cartas_otros_en_mesa.size(), 0, "no se pinta dos veces")


func test_la_carta_del_rival_aparece_en_la_baza() -> void:
	await _abrir("guinote", JUGADORES_2, _con(GUINOTE, {"turno": 1, "jugadas_validas": []}))
	red.estado_actualizado.emit(_con(GUINOTE, {
		"cartas_por_jugador": [6, 5], "baza_actual": [{"jugador_id": 1, "carta_id": "espadas_1"}],
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"},
	}))
	assert_eq(_tapete().cartas_otros_en_mesa.size(), 1)
	assert_eq(_tapete().cartas_otros_en_mesa[0].id, "espadas_1")
	assert_eq(_tapete().dorsos[1].get_child_count(), 5)


func test_la_baza_completa_se_queda_a_la_vista_antes_de_recogerla() -> void:
	var con_una := _con(GUINOTE, {
		"turno": 1, "mi_mano": GUINOTE["mi_mano"].slice(1), "cartas_por_jugador": [5, 6],
		"baza_actual": [{"jugador_id": 0, "carta_id": "oros_1"}], "jugadas_validas": [],
		"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_1"},
	})
	await _abrir("guinote", JUGADORES_2, con_una, 0.3)
	# El rival cierra la baza: el servidor ya la manda recogida y con el robo hecho.
	red.estado_actualizado.emit(_con(GUINOTE, {
		"turno": 0, "cartas_en_mazo": 26, "cartas_por_jugador": [6, 6], "baza_actual": [],
		"mi_mano": GUINOTE["mi_mano"].slice(1) + ["bastos_2"],
		"ultima_jugada": {"numero": 2, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"},
	}))
	assert_eq(_tapete().cartas_otros_en_mesa.size(), 2, "las dos cartas de la baza siguen en la mesa")
	assert_eq(_tapete().cartas_en_mano.size(), 5, "todavía no se ha robado")
	assert_eq(_botones(), [], "mientras se ve la baza no se puede hacer nada")
	await wait_seconds(0.5)
	assert_eq(_tapete().cartas_otros_en_mesa.size(), 0, "luego se recoge")
	assert_eq(_tapete().cartas_en_mano.size(), 6, "y se roba")
	assert_has(_textos_en_la_mesa(), "26 en el mazo")


func test_lo_que_dice_un_jugador_sale_en_un_letrero() -> void:
	await _abrir("guinote", JUGADORES_2, _con(GUINOTE, {"turno": 1, "jugadas_validas": []}))
	red.estado_actualizado.emit(_con(GUINOTE, {
		"turno": 1, "jugadas_validas": [],
		"cantes": [{"jugador_id": 1, "palo": "oros", "puntos": 40, "mano": "idas"}],
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "cantar", "palo": "oros"},
	}))
	assert_has(_textos_en_la_mesa(), "¡Las 40!")


func test_un_estado_repetido_no_vuelve_a_anunciar_la_jugada() -> void:
	var cantado := _con(GUINOTE, {
		"ultima_jugada": {"numero": 4, "jugador_id": 1, "tipo": "cantar", "palo": "oros"}})
	await _abrir("guinote", JUGADORES_2, cantado)
	assert_does_not_have(_textos_en_la_mesa(), "¡Las 40!", "al entrar (o reconectarse) no se anuncia lo que ya pasó")
	red.estado_actualizado.emit(cantado)
	assert_does_not_have(_textos_en_la_mesa(), "¡Las 40!")


func test_al_empezar_la_vuelta_se_avisa_y_se_ve_como_acabaron_las_idas() -> void:
	await _abrir("guinote", JUGADORES_2, _con(GUINOTE, {"turno": 1, "jugadas_validas": []}))
	red.estado_actualizado.emit(_con(GUINOTE, {
		"mano": "vuelta", "tanteo_idas": [88, 72],
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"},
	}))
	assert_has(_textos_en_la_mesa(), "Nadie pasa de 100: ¡vuelta! Idas 88 - 72")
	assert_has(_textos_en_la_mesa(), "Vuelta · idas: J1 88 · J2 72")


# --- Tute ---

func test_el_tute_de_dos_es_otro_juego_que_el_de_parejas() -> void:
	assert_eq(PartidaMesa.juego_de_mesa("tute", 2), "tute_dos")
	assert_eq(PartidaMesa.juego_de_mesa("tute", 4), "tute")
	assert_eq(PartidaMesa.juego_de_mesa("guinote", 2), "guinote")
	assert_eq(PartidaMesa.juego_de_mesa("mus", 4), "mus")


func test_en_el_tute_por_parejas_no_hay_mazo_y_la_pinta_va_en_la_esquina() -> void:
	await _abrir("tute", JUGADORES_4, _con(GUINOTE, {
		"fase": "arrastre", "dador": 3, "cartas_en_mazo": 1, "cartas_por_jugador": [10, 10, 10, 10]}))
	assert_null(_tapete().find_child("Pila", true, false))
	assert_eq(_tapete().cartas_en_mazo.size(), 1)
	assert_eq(_tapete().cartas_en_mazo[0].id, "oros_5")
	assert_eq(_etiqueta(2), "J3 · Marta")
	assert_eq(_tapete().dorsos.keys(), [1, 2, 3], "dorsos de los otros tres")


func test_en_el_tute_de_dos_se_puede_anunciar_capote_y_cambiar_con_el_dos() -> void:
	await _abrir("tute", JUGADORES_2, _con(GUINOTE, {"pinta": "oros_5", "jugadas_validas": [
		{"tipo": "capote"}, {"tipo": "cambiar_siete"}]}))
	assert_eq(_botones(), ["Anunciar capote", "Cambiar el 2 por la pinta"])


# --- Mus ---

func test_mus_marcador_botones_y_texto_del_centro() -> void:
	await _abrir("mus", JUGADORES_4, MUS)
	assert_eq(_botones(), ["Mus", "No hay mus"])
	assert_has(_textos_en_la_mesa(), "¿Mus?")
	assert_has(_textos_en_la_mesa(), "Piedras: Pareja A 3 · Pareja B 7\nJuegos: 1 - 0 (a 40 piedras)\nEs mano J2")
	assert_has(_textos_en_la_mesa(), "24 en el mazo")
	_pulsar("No hay mus")
	assert_eq(_enviados(), [["enviar", "no_mus", {}]])


func test_mus_de_los_envites_solo_hay_boton_para_2_5_y_ordago() -> void:
	var jugadas: Array = [{"tipo": "pasar"}]
	for cantidad in range(2, 11):
		jugadas.append({"tipo": "envidar", "cantidad": cantidad})
	jugadas.append({"tipo": "ordago"})
	await _abrir("mus", JUGADORES_4, _con(MUS, {"fase": "lances", "lance": "grande", "jugadas_validas": jugadas}))
	assert_eq(_botones(), ["Paso", "Envido 2", "Envido 5", "¡Órdago!"])
	assert_has(_textos_en_la_mesa(), "Lance: Grande")


func test_mus_descartarse_de_las_cartas_elegidas() -> void:
	await _abrir("mus", JUGADORES_4, _con(MUS, {"fase": "descarte", "jugadas_validas": [
		{"tipo": "descartar", "cartas": ["bastos_1"]}, {"tipo": "descartar", "cartas": ["espadas_4"]},
		{"tipo": "descartar", "cartas": ["bastos_1", "espadas_4"]}]}))
	assert_eq(_botones(), ["Elige cartas para descartar"], "un solo botón para todos los descartes")
	var cartas: Array = _tapete().cartas_en_mano
	# En el Mus, pulsar una carta durante tu descarte la elige.
	_tapete()._on_carta_soltada(cartas[2])
	_tapete()._on_carta_soltada(cartas[3])
	assert_eq(_botones(), ["Descartar 2"])
	_pulsar("Descartar 2")
	assert_eq(_enviados(), [["enviar", "descartar", {"cartas": ["bastos_1", "espadas_4"]}]])


func test_mus_al_acabar_la_mano_se_ensenan_las_cartas_de_todos() -> void:
	await _abrir("mus", JUGADORES_4, _con(MUS, {"fase": "lances", "lance": "juego", "jugadas_validas": []}), 0.1)
	red.estado_actualizado.emit(_con(MUS, {
		"mano": 2, "piedras": [5, 7],
		"ultima_jugada": {"numero": 9, "jugador_id": 3, "tipo": "pasar"},
		"ultima_mano": {
			"mano": 1, "juego_para": -1, "lances": [],
			"manos": [["oros_12", "copas_12", "bastos_1", "espadas_4"], ["oros_1", "copas_1", "bastos_2", "espadas_5"],
				["oros_3", "copas_3", "bastos_3", "espadas_6"], ["oros_4", "copas_4", "bastos_4", "espadas_7"]],
			"cobros": [{"lance": "grande", "equipo": 0, "piedras": 2, "concepto": "paso"}],
		},
	}))
	var panel: Control = _tapete().find_child("PanelFinDeMano", true, false)
	assert_not_null(panel)
	assert_true(panel.visible, "las cartas de todos, a la vista")
	assert_has(_textos_en_la_mesa(), "Paso")
	await wait_seconds(0.5)
	assert_false(panel.visible, "al repartir la siguiente mano se quita")


# --- Fin de la partida ---

func test_al_terminar_ensena_el_resultado_y_deja_volver_al_lobby() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	var boton: Button = partida.find_child("BotonVolverLobby", true, false)
	assert_false(boton.visible, "durante la partida no")
	red.partida_terminada.emit({
		"equipo_ganador": 0, "puntos_por_equipo": [101, 40], "motivo": "tantos",
		"manos": [{"total": [101, 40], "cartas": [81, 40], "cantes": [20, 0], "diez_ultimas": [0, 0]}],
	})
	var panel: Control = _tapete().find_child("PanelResultado", true, false)
	assert_true(panel.visible)
	assert_string_starts_with((panel.get_child(0) as Label).text,
		"FIN DE LA PARTIDA\nGana Ana por tantos al acabar las idas.")
	assert_true(boton.visible)
	assert_eq(_botones(), [], "ya no hay nada que jugar")


func test_un_error_que_llega_con_la_partida_ya_terminada_no_se_ensena() -> void:
	# Dos compañeros actúan a la vez: uno canta y con eso se acaba la partida;
	# lo que intentó el otro llega tarde y el servidor lo rechaza.
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_pulsar("Cambiar el 7 por la pinta")
	red.partida_terminada.emit({
		"equipo_ganador": 1, "puntos_por_equipo": [40, 101], "motivo": "tantos",
		"manos": [{"total": [40, 101], "cartas": [40, 81], "cantes": [0, 20], "diez_ultimas": [0, 0]}],
	})
	red.error_recibido.emit("Primero tienes que unirte a una partida")
	assert_does_not_have(_textos_en_la_mesa(), "Primero tienes que unirte a una partida")
	assert_eq(_botones(), [], "y no vuelven los botones")


func test_si_se_cae_el_servidor_se_avisa_y_se_puede_salir() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	red.desconectado_del_servidor.emit()
	var panel: Control = _tapete().find_child("PanelResultado", true, false)
	assert_string_starts_with((panel.get_child(0) as Label).text, "SE HA PERDIDO LA CONEXIÓN")
	assert_true((partida.find_child("BotonVolverLobby", true, false) as Button).visible)


# --- Chat y denuncias (PBI-08) ---

const DENUNCIA := {"estado": "pendiente", "mensaje_id": 1, "mensaje": "tengo el as", "denunciante": 1,
	"denunciado": 0, "equipo_denunciado": 0, "segundos": 60.0, "respondido_por": -1}


func _denunciar(estado := "pendiente") -> void:
	var denuncia := DENUNCIA.duplicate()
	denuncia["estado"] = estado
	red.denuncia = denuncia if estado == "pendiente" else {}
	red.denuncia_actualizada.emit(denuncia)


func test_la_mesa_tiene_su_chat_con_los_mensajes_que_ya_habian_llegado() -> void:
	red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": "guinote", "tu_posicion": 0, "jugadores": JUGADORES_4}
	red.ultimo_estado = _con(GUINOTE, {"cartas_por_jugador": [6, 6, 6, 6]})
	red.chat = [{"id": 1, "posicion": 1, "equipo": 1, "nombre": "Luis", "mensaje": "¡suerte!", "durante_partida": false}]
	add_child_autofree(red)
	partida = PARTIDA_MESA.instantiate()
	partida.red = red
	partida.pausa_baza = 0.0
	add_child_autofree(partida)
	await wait_frames(1)
	assert_not_null(partida.chat)
	assert_string_contains(partida.chat.texto_visible(), "J2 · Luis: ¡suerte!")


func test_una_denuncia_pendiente_pausa_la_mesa() -> void:
	var estado := _con(GUINOTE, {"tiempos_para_decidir": [{"posicion": 0, "segundos": 40.0, "ausente": false}]})
	await _abrir("guinote", JUGADORES_2, estado)
	assert_ne(_botones(), [], "antes de la denuncia se puede jugar")
	assert_true(partida.cuenta_atras.visible)
	_denunciar()
	assert_eq(_botones(), [], "en pausa no se ofrece ninguna jugada")
	assert_false(partida.cuenta_atras.visible, "la cuenta atrás se para")
	assert_has(_textos_en_la_mesa(), partida.ANUNCIO_PAUSA)
	red.error_recibido.emit(RoomManager.ERROR_EN_PAUSA)
	assert_eq(_botones(), [], "un error no devuelve las jugadas en pausa")


func test_al_reanudarse_vuelven_las_jugadas_con_el_estado_nuevo() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_denunciar()
	_denunciar("no_admitida")
	red.estado_actualizado.emit(_con(GUINOTE, {"tiempos_para_decidir": [{"posicion": 0, "segundos": 30.0, "ausente": false}]}))
	assert_ne(_botones(), [])
	assert_true(partida.cuenta_atras.visible)


func test_quien_se_reconecta_en_pausa_empieza_sin_jugadas() -> void:
	red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": "guinote", "tu_posicion": 0, "jugadores": JUGADORES_2}
	red.ultimo_estado = _con(GUINOTE, {"tiempos_para_decidir": [{"posicion": 0, "segundos": 40.0, "ausente": false}]})
	red.denuncia = DENUNCIA.duplicate()
	add_child_autofree(red)
	partida = PARTIDA_MESA.instantiate()
	partida.red = red
	partida.pausa_baza = 0.0
	add_child_autofree(partida)
	await wait_frames(1)
	assert_eq(_botones(), [])
	assert_false(partida.cuenta_atras.visible)
	assert_true(partida.chat.panel_denuncia.visible, "y ve la denuncia en el chat")


func test_al_terminar_por_renuncio_el_chat_sigue_pero_sin_denuncias() -> void:
	await _abrir("guinote", JUGADORES_2, GUINOTE)
	_denunciar()
	_denunciar("admitida")
	red.partida_terminada.emit({"equipo_ganador": 1, "puntos_por_equipo": [12, 30], "causa": "renuncio",
		"motivo": "", "manos": []})
	var panel: Control = _tapete().find_child("PanelResultado", true, false)
	assert_string_contains((panel.get_child(0) as Label).text, "por renuncio")
	assert_true(partida.chat._terminada)
	assert_true(partida.chat.visible)


func test_el_chat_no_tapa_la_etiqueta_del_jugador_de_la_izquierda() -> void:
	await _abrir("guinote", JUGADORES_4, _con(GUINOTE, {"cartas_por_jugador": [6, 6, 6, 6]}))
	var etiqueta: Control = _tapete().etiquetas_jugador[3]
	var alto := partida.get_viewport_rect().size.y
	assert_true(partida.chat.position.y >= etiqueta.position.y + etiqueta.size.y,
		"el chat empieza por debajo de la etiqueta de la izquierda")
	assert_almost_eq(partida.chat.position.y + partida.chat.size.y, alto - 10.0, 0.5, "pegado abajo")
