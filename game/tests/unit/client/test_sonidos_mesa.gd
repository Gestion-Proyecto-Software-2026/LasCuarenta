extends GutTest
## Cuándo suena cada cosa en la mesa (PBI-21), con estados a mano: el reparto,
## el robo, el cambio del siete, la carta jugada (tuya o de otro) y el aviso de
## turno, con y sin tiempo límite en el servidor.

const SonidosMesa := preload("res://client/ui/mesa/sonidos_mesa.gd")
const Sonido := preload("res://client/autoload/sonidos.gd")

## Guiñote a 2, recién repartido, y me toca a mí (asiento 0) con tiempo límite.
const INICIO := {
	"turno": 0, "pinta": "oros_5",
	"mi_mano": ["oros_1", "copas_12", "copas_10", "bastos_10", "espadas_3", "oros_7"],
	"ultima_jugada": {},
	"jugadas_validas": [
		{"tipo": "jugar_carta", "carta_id": "oros_1"},
		{"tipo": "jugar_carta", "carta_id": "copas_12"},
		{"tipo": "cambiar_siete"},
	],
	"tiempos_para_decidir": [{"posicion": 0, "segundos": 45.0, "ausente": false}],
}


func _con(estado: Dictionary, cambios: Dictionary) -> Dictionary:
	var nuevo := estado.duplicate(true)
	nuevo.merge(cambios, true)
	return nuevo


## Como INICIO, pero esperando al rival (asiento 1).
func _le_toca_al_rival(estado: Dictionary) -> Dictionary:
	return _con(estado, {"turno": 1, "jugadas_validas": [],
		"tiempos_para_decidir": [{"posicion": 1, "segundos": 45.0, "ausente": false}]})


func _sonidos(anterior: Dictionary, estado: Dictionary, mi_asiento := 0) -> Array[String]:
	return SonidosMesa.sonidos_entre(anterior, estado, mi_asiento)


# --- Reparto y robo ---

func test_al_empezar_se_reparte_y_me_toca() -> void:
	assert_eq(_sonidos({}, INICIO), [Sonido.REPARTIR, Sonido.TURNO] as Array[String])


func test_al_empezar_sin_ser_mi_turno_solo_se_reparte() -> void:
	assert_eq(_sonidos({}, _le_toca_al_rival(INICIO)), [Sonido.REPARTIR] as Array[String])


func test_robar_tras_la_baza() -> void:
	var antes := _le_toca_al_rival(_con(INICIO, {"mi_mano": INICIO["mi_mano"].slice(1)}))
	var despues := _le_toca_al_rival(_con(antes, {"mi_mano": antes["mi_mano"] + ["bastos_2"],
		"ultima_jugada": {"numero": 3, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"}}))
	assert_eq(_sonidos(antes, despues), [Sonido.CARTA, Sonido.ROBAR] as Array[String],
		"la carta del rival cierra la baza y luego se roba")


func test_cambiar_el_siete_es_un_robo() -> void:
	var cambiado := _con(INICIO, {"pinta": "oros_7",
		"mi_mano": ["oros_1", "copas_12", "copas_10", "bastos_10", "espadas_3", "oros_5"],
		"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "cambiar_siete"}})
	assert_eq(_sonidos(INICIO, cambiado), [Sonido.ROBAR] as Array[String],
		"te llevas la pinta; sigue tocándote, así que no se vuelve a avisar")


func test_mano_nueva_del_mus_es_un_reparto() -> void:
	var antes := {"mi_mano": ["oros_12", "copas_12", "bastos_1", "espadas_4"], "ultima_jugada": {"numero": 20}}
	var despues := {"mi_mano": ["oros_3", "copas_5", "bastos_1", "espadas_7"],
		"ultima_jugada": {"numero": 21, "jugador_id": 3, "tipo": "pasar"}}
	assert_eq(_sonidos(antes, despues, 2), [Sonido.REPARTIR] as Array[String])


func test_reponer_dos_cartas_en_el_mus_es_un_reparto() -> void:
	var antes := {"mi_mano": ["oros_12", "copas_12", "bastos_1", "espadas_4"]}
	var despues := {"mi_mano": ["oros_12", "copas_12", "oros_6", "copas_2"]}
	assert_has(_sonidos(antes, despues), Sonido.REPARTIR)


func test_echar_una_carta_no_suena_como_robo() -> void:
	var despues := _le_toca_al_rival(_con(INICIO, {"mi_mano": INICIO["mi_mano"].slice(1)}))
	assert_does_not_have(_sonidos(INICIO, despues), Sonido.ROBAR)
	assert_does_not_have(_sonidos(INICIO, despues), Sonido.REPARTIR)


# --- Carta jugada ---

func test_mi_carta_jugada_suena() -> void:
	var despues := _le_toca_al_rival(_con(INICIO, {"mi_mano": INICIO["mi_mano"].slice(1),
		"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_1"}}))
	assert_eq(_sonidos(INICIO, despues), [Sonido.CARTA] as Array[String])


func test_la_carta_del_rival_suena_y_me_toca() -> void:
	var antes := _le_toca_al_rival(INICIO)
	var despues := _con(INICIO, {
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"}})
	assert_eq(_sonidos(antes, despues), [Sonido.CARTA, Sonido.TURNO] as Array[String])


func test_un_estado_repetido_no_suena() -> void:
	var jugado := _con(INICIO, {
		"ultima_jugada": {"numero": 4, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"}})
	assert_eq(_sonidos(jugado, jugado), [] as Array[String])


func test_otra_jugada_que_no_es_echar_carta_no_suena_a_carta() -> void:
	var antes := _le_toca_al_rival(INICIO)
	var despues := _le_toca_al_rival(_con(INICIO, {
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "cantar", "palo": "oros"}}))
	assert_eq(_sonidos(antes, despues), [] as Array[String])


func test_al_reconectarse_a_mitad_de_partida_no_suena_el_reparto() -> void:
	# En el arrastre, con 3 cartas: ya estaban repartidas antes de entrar.
	var a_mitad := _con(INICIO, {"mi_mano": ["oros_1", "copas_12", "copas_10"],
		"ultima_jugada": {"numero": 7, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_1"}})
	assert_eq(_sonidos({}, a_mitad), [Sonido.TURNO] as Array[String], "solo se avisa de que te toca")
	assert_eq(_sonidos({}, _le_toca_al_rival(a_mitad)), [] as Array[String])


func test_al_reconectarse_con_una_carta_no_suena_un_robo() -> void:
	var ultima := _le_toca_al_rival(_con(INICIO, {"mi_mano": ["oros_1"],
		"ultima_jugada": {"numero": 37, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_2"}}))
	assert_eq(_sonidos({}, ultima), [] as Array[String])


func test_al_entrar_no_suena_la_carta_que_ya_se_habia_jugado() -> void:
	var jugado := _le_toca_al_rival(_con(INICIO, {
		"ultima_jugada": {"numero": 7, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_2"}}))
	assert_does_not_have(_sonidos({}, jugado), Sonido.CARTA, "solo se oye lo que se ve pasar")


# --- Turno ---

func test_me_toca_con_tiempo_limite() -> void:
	assert_true(SonidosMesa.me_toca(INICIO, 0))
	assert_false(SonidosMesa.me_toca(INICIO, 1))
	assert_false(SonidosMesa.me_toca({}, 0))


func test_varios_esperados_a_la_vez() -> void:
	# En el Mus hablan todos a la vez para pedir mus.
	var mus := {"jugadas_validas": [{"tipo": "mus"}, {"tipo": "no_mus"}], "tiempos_para_decidir": [
		{"posicion": 0, "segundos": 45.0, "ausente": false}, {"posicion": 2, "segundos": 30.0, "ausente": false}]}
	assert_true(SonidosMesa.me_toca(mus, 2))
	assert_false(SonidosMesa.me_toca(mus, 1))


func test_con_tiempo_limite_manda_la_lista_aunque_haya_jugadas() -> void:
	# Te ofrecen cantar tras ganar la baza, pero a quien se espera es al rival.
	var estado := _con(_le_toca_al_rival(INICIO), {"jugadas_validas": [{"tipo": "jugar_carta", "carta_id": "oros_1"}]})
	assert_false(SonidosMesa.me_toca(estado, 0))


func test_sin_tiempo_limite_me_toca_si_puedo_jugar() -> void:
	var sin_tiempo := INICIO.duplicate(true)
	sin_tiempo.erase("tiempos_para_decidir")
	assert_true(SonidosMesa.me_toca(sin_tiempo, 0))
	assert_true(SonidosMesa.me_toca(_con(sin_tiempo, {"tiempos_para_decidir": []}), 0), "vacío es lo mismo")
	assert_eq(_sonidos({}, sin_tiempo), [Sonido.REPARTIR, Sonido.TURNO] as Array[String])


func test_sin_tiempo_limite_con_solo_jugadas_opcionales_no_me_toca() -> void:
	for opcionales: Array in [
			[{"tipo": "cantar", "palo": "oros"}, {"tipo": "cambiar_siete"}],
			[{"tipo": "cantar_tute"}], [{"tipo": "capote"}], []]:
		assert_false(SonidosMesa.me_toca({"jugadas_validas": opcionales}, 0), str(opcionales))


func test_sin_tiempo_limite_decidir_el_cambio_del_siete_si_es_tu_turno() -> void:
	var decidir := {"jugadas_validas": [{"tipo": "cambiar_siete"}, {"tipo": "no_cambiar_siete"}]}
	assert_true(SonidosMesa.me_toca(decidir, 0))


func test_el_turno_no_se_repite_mientras_me_siga_tocando() -> void:
	var otro_tiempo := _con(INICIO, {"tiempos_para_decidir": [{"posicion": 0, "segundos": 30.0, "ausente": false}]})
	assert_eq(_sonidos(INICIO, otro_tiempo), [] as Array[String])


func test_me_vuelve_a_tocar() -> void:
	var antes := _le_toca_al_rival(INICIO)
	assert_eq(_sonidos(antes, INICIO), [Sonido.TURNO] as Array[String])


## Guiñote a 2: el rival ha salido y me toca responder (asiento 0).
func _respondo() -> Dictionary:
	return _con(INICIO, {"baza_actual": [{"jugador_id": 1, "carta_id": "espadas_4"}],
		"ultima_jugada": {"numero": 5, "jugador_id": 1, "tipo": "jugar_carta", "carta_id": "espadas_4"}})


## Tras [method _respondo]: echo el as, cierro la baza, la gano, robo y salgo yo.
func _gano_la_baza(antes: Dictionary) -> Dictionary:
	var mano: Array = antes["mi_mano"].slice(1) + ["bastos_2"]
	return _con(antes, {"mi_mano": mano, "baza_actual": [],
		"ultima_jugada": {"numero": 6, "jugador_id": 0, "tipo": "jugar_carta", "carta_id": "oros_1"}})


func test_cierro_la_baza_la_gano_y_salgo_suena_el_turno() -> void:
	# El servidor me estrena tiempo: sigo en tiempos_para_decidir en los dos
	# estados, pero es un turno nuevo, tras la pausa de la baza completa.
	var antes := _respondo()
	assert_eq(_sonidos(antes, _gano_la_baza(antes)),
		[Sonido.CARTA, Sonido.ROBAR, Sonido.TURNO] as Array[String])


func test_cierro_la_baza_y_salgo_sin_tiempo_limite_tambien_suena_el_turno() -> void:
	var antes := _respondo()
	antes.erase("tiempos_para_decidir")
	assert_has(_sonidos(antes, _gano_la_baza(antes)), Sonido.TURNO)


func test_en_el_arrastre_cierro_la_baza_y_salgo_suena_el_turno() -> void:
	var antes := _respondo()
	var despues := _con(_gano_la_baza(antes), {"mi_mano": antes["mi_mano"].slice(1)})
	assert_eq(_sonidos(antes, despues), [Sonido.CARTA, Sonido.TURNO] as Array[String], "sin robo")


func test_la_mano_del_mus_contesta_un_envite_y_abre_el_lance_siguiente() -> void:
	var mano := ["oros_12", "copas_12", "bastos_1", "espadas_4"]
	var antes := {"mi_mano": mano, "jugadas_validas": [{"tipo": "quiero"}, {"tipo": "no_quiero"}],
		"ultima_jugada": {"numero": 9, "jugador_id": 1, "tipo": "envidar", "cantidad": 2},
		"tiempos_para_decidir": [{"posicion": 0, "segundos": 12.0, "ausente": false}]}
	var despues := _con(antes, {"jugadas_validas": [{"tipo": "pasar"}, {"tipo": "ordago"}],
		"ultima_jugada": {"numero": 10, "jugador_id": 0, "tipo": "quiero"},
		"tiempos_para_decidir": [{"posicion": 0, "segundos": 45.0, "ausente": false}]})
	assert_eq(_sonidos(antes, despues), [Sonido.TURNO] as Array[String])


func test_cantar_y_seguir_tocandome_no_vuelve_a_avisar() -> void:
	var cantado := _con(INICIO, {"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "cantar", "palo": "copas"}})
	assert_eq(_sonidos(INICIO, cantado), [] as Array[String])


func test_no_cambiar_el_siete_y_seguir_tocandome_no_vuelve_a_avisar() -> void:
	var decidir := _con(INICIO, {"jugadas_validas": [{"tipo": "cambiar_siete"}, {"tipo": "no_cambiar_siete"}]})
	var decidido := _con(INICIO, {"ultima_jugada": {"numero": 1, "jugador_id": 0, "tipo": "no_cambiar_siete"}})
	assert_eq(_sonidos(decidir, decidido), [] as Array[String], "se decide antes de echar carta: el mismo turno")


func test_la_jugada_de_otro_con_la_que_me_sigue_tocando_no_avisa() -> void:
	# El compañero canta mientras yo pienso: no es un turno nuevo para mí.
	var cantado := _con(INICIO, {"ultima_jugada": {"numero": 1, "jugador_id": 2, "tipo": "cantar", "palo": "oros"}})
	assert_eq(_sonidos(INICIO, cantado), [] as Array[String])


func test_sin_estado_no_suena_nada() -> void:
	assert_eq(_sonidos(INICIO, {}), [] as Array[String])
