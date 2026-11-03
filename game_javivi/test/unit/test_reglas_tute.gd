extends GutTest
## Reglas del Tute por parejas (ReglasTute), con manos construidas a mano para
## probar cada obligación del arrastre por separado. Las cartas son las de
## data/Cartas, las mismas que usa la partida.

const OROS := 0
const COPAS := 1
const ESPADAS := 2
const BASTOS := 3
const VALORES := ["As", "Dos", "Tres", "Cuatro", "Cinco", "Seis", "Siete", "Sota", "Caballo", "Rey"]
const PALOS := ["oros", "copas", "espadas", "bastos"]


func _c(id: String) -> Carta:
	return load("res://data/Cartas/%s.tres" % id)


func _mano(ids: Array) -> Array:
	var cartas: Array = []
	for id in ids:
		cartas.append(_c(id))
	return cartas


func _ordenados(ids: Array) -> Array:
	var copia := ids.duplicate()
	copia.sort()
	return copia


func _ids(cartas: Array) -> Array:
	var ids: Array = []
	for carta in cartas:
		ids.append(carta.id)
	return _ordenados(ids)


func _permitidas(mano: Array, baza: Array, triunfo: int) -> Array:
	return _ids(ReglasTute.cartas_permitidas(_mano(mano), _mano(baza), triunfo))


func _baraja_completa() -> Array:
	var cartas: Array = []
	for palo in PALOS:
		for valor in VALORES:
			cartas.append(_c("%s_%s" % [valor, palo]))
	return cartas


# --- Valores y orden ---

func test_en_el_tute_el_caballo_supera_a_la_sota() -> void:
	assert_gt(ReglasTute.rango(_c("Caballo_oros")), ReglasTute.rango(_c("Sota_oros")),
		"Al revés que en el Guiñote")
	assert_eq(ReglasTute.puntos(_c("Caballo_oros")), 3)
	assert_eq(ReglasTute.puntos(_c("Sota_oros")), 2)


func test_valores_de_las_cartas() -> void:
	assert_eq(ReglasTute.puntos(_c("As_copas")), 11)
	assert_eq(ReglasTute.puntos(_c("Tres_copas")), 10)
	assert_eq(ReglasTute.puntos(_c("Rey_copas")), 4)
	assert_eq(ReglasTute.puntos(_c("Siete_copas")), 0, "Las cartas blancas no valen")


func test_la_baraja_suma_120_tantos() -> void:
	var total := 0
	for carta in _baraja_completa():
		total += ReglasTute.puntos(carta)
	assert_eq(total, 120)


func test_orden_de_fuerza_completo() -> void:
	var orden := ["As", "Tres", "Rey", "Caballo", "Sota", "Siete", "Seis", "Cinco", "Cuatro", "Dos"]
	for i in range(orden.size() - 1):
		assert_gt(ReglasTute.rango(_c(orden[i] + "_bastos")), ReglasTute.rango(_c(orden[i + 1] + "_bastos")),
			"%s por encima de %s" % [orden[i], orden[i + 1]])


# --- Reparto ---

func test_reparto_diez_cartas_y_la_ultima_es_del_dador() -> void:
	var baraja := _baraja_completa()
	var manos := ReglasTute.repartir(baraja, 2)
	for mano in manos:
		assert_eq(mano.size(), 10)
	assert_true(manos[2].has(baraja[39]), "La última carta, la que se vuelve como pinta, es del dador")
	assert_true(manos[3].has(baraja[0]), "Se empieza a repartir por la derecha del dador")
	assert_true(manos[0].has(baraja[1]), "Se reparte de una en una")


func test_reparto_no_pierde_ni_repite_cartas() -> void:
	var vistas := {}
	for mano in ReglasTute.repartir(_baraja_completa(), 0):
		for carta in mano:
			vistas[carta.id] = true
	assert_eq(vistas.size(), 40)


# --- Quién gana la baza ---

func test_gana_la_mas_alta_del_palo_de_salida() -> void:
	var baza := _mano(["Sota_oros", "Rey_oros", "As_copas", "Dos_oros"])
	assert_eq(ReglasTute.indice_ganador(baza, ESPADAS), 1,
		"El As de copas no cuenta: no es del palo de salida ni de triunfo")


func test_gana_el_triunfo_mas_alto() -> void:
	var baza := _mano(["As_oros", "Dos_espadas", "Caballo_espadas", "Tres_oros"])
	assert_eq(ReglasTute.indice_ganador(baza, ESPADAS), 2)


# --- Arrastre: asistir, montar, fallar y pisar ---

func test_quien_sale_puede_echar_cualquier_carta() -> void:
	var mano := ["As_oros", "Dos_copas", "Rey_espadas"]
	assert_eq(_permitidas(mano, [], BASTOS), _ordenados(mano))


func test_hay_que_asistir_al_palo_de_salida() -> void:
	assert_eq(_permitidas(["Dos_oros", "As_copas", "Seis_oros"], ["Siete_oros"], BASTOS),
		["Dos_oros", "Seis_oros"])


func test_hay_que_montar_si_se_puede() -> void:
	assert_eq(_permitidas(["Dos_oros", "Caballo_oros", "As_copas"], ["Siete_oros"], BASTOS),
		["Caballo_oros"])


func test_si_no_puede_montar_vale_cualquiera_del_palo() -> void:
	assert_eq(_permitidas(["Dos_oros", "Cuatro_oros", "As_copas"], ["Rey_oros"], BASTOS),
		["Cuatro_oros", "Dos_oros"])


func test_si_otro_ya_ha_fallado_basta_con_asistir() -> void:
	# Salen oros y alguien falla con triunfo: ningún oro puede ganar ya, pero hay que asistir.
	assert_eq(_permitidas(["As_oros", "Dos_oros", "Rey_bastos"], ["Siete_oros", "Dos_bastos"], BASTOS),
		["As_oros", "Dos_oros"])


func test_si_salen_triunfos_hay_que_montar_con_triunfo() -> void:
	assert_eq(_permitidas(["Dos_bastos", "Tres_bastos", "As_copas"], ["Rey_bastos"], BASTOS),
		["Tres_bastos"])


func test_sin_el_palo_hay_que_fallar() -> void:
	assert_eq(_permitidas(["As_copas", "Dos_bastos", "Rey_bastos"], ["Siete_oros"], BASTOS),
		["Dos_bastos", "Rey_bastos"])


func test_si_ya_hay_un_triunfo_hay_que_pisarlo() -> void:
	assert_eq(_permitidas(["Dos_bastos", "Rey_bastos", "As_copas"], ["Siete_oros", "Caballo_bastos"], BASTOS),
		["Rey_bastos"])


func test_si_no_puede_pisar_contrafallo_libre() -> void:
	var mano := ["Dos_bastos", "As_copas", "Cuatro_espadas"]
	assert_eq(_permitidas(mano, ["Siete_oros", "As_bastos"], BASTOS), _ordenados(mano))


func test_sin_palo_ni_triunfo_vale_cualquier_carta() -> void:
	var mano := ["As_copas", "Cuatro_espadas"]
	assert_eq(_permitidas(mano, ["Siete_oros"], BASTOS), _ordenados(mano))


# --- El motivo que se le enseña al jugador ---

func test_motivos_de_asistir_y_montar() -> void:
	var mano := _mano(["Dos_oros", "Caballo_oros", "As_copas"])
	var baza := _mano(["Siete_oros"])
	assert_string_contains(ReglasTute.motivo_rechazo(mano, baza, BASTOS, _c("As_copas")), "asistir")
	assert_string_contains(ReglasTute.motivo_rechazo(mano, baza, BASTOS, _c("Dos_oros")), "montar")
	assert_eq(ReglasTute.motivo_rechazo(mano, baza, BASTOS, _c("Caballo_oros")), "")


func test_motivos_de_fallar_y_pisar() -> void:
	var mano := _mano(["Dos_bastos", "Rey_bastos", "As_copas"])
	assert_string_contains(
		ReglasTute.motivo_rechazo(mano, _mano(["Siete_oros"]), BASTOS, _c("As_copas")), "fallar")
	assert_string_contains(
		ReglasTute.motivo_rechazo(mano, _mano(["Siete_oros", "Caballo_bastos"]), BASTOS, _c("Dos_bastos")), "pisar")


func test_no_se_puede_echar_una_carta_que_no_tienes() -> void:
	assert_eq(ReglasTute.motivo_rechazo(_mano(["Dos_oros"]), [], BASTOS, _c("As_oros")), "No tienes esa carta.")


# --- Cantes y Tute ---

func test_rey_y_caballo_del_mismo_palo_son_las_20() -> void:
	var opcion := ReglasTute.mejor_cante(_mano(["Rey_copas", "Caballo_copas", "Dos_oros"]), BASTOS, [])
	assert_eq(opcion.get("tipo"), "cante")
	assert_eq(opcion.get("palo"), COPAS)
	assert_eq(opcion.get("puntos"), 20)


func test_en_el_palo_de_triunfo_son_las_40_y_van_primero() -> void:
	var mano := _mano(["Rey_copas", "Caballo_copas", "Rey_bastos", "Caballo_bastos"])
	var opcion := ReglasTute.mejor_cante(mano, BASTOS, [])
	assert_eq(opcion.get("palo"), BASTOS)
	assert_eq(opcion.get("puntos"), 40)


func test_sota_y_rey_no_son_cante_en_el_tute() -> void:
	assert_true(ReglasTute.mejor_cante(_mano(["Rey_copas", "Sota_copas"]), BASTOS, []).is_empty(),
		"Sota y Rey es el cante del Guiñote, no del Tute")


func test_un_palo_ya_cantado_no_se_vuelve_a_cantar() -> void:
	assert_true(ReglasTute.mejor_cante(_mano(["Rey_copas", "Caballo_copas"]), BASTOS, [COPAS]).is_empty())


func test_tute_de_reyes_y_de_caballos() -> void:
	var reyes := ReglasTute.mejor_cante(_mano(["Rey_oros", "Rey_copas", "Rey_espadas", "Rey_bastos"]), OROS, [])
	assert_eq(reyes.get("tipo"), "tute")
	assert_eq(reyes.get("figura"), "reyes")
	var caballos := ReglasTute.mejor_cante(
		_mano(["Caballo_oros", "Caballo_copas", "Caballo_espadas", "Caballo_bastos", "As_oros"]), OROS, [])
	assert_eq(caballos.get("figura"), "caballos")


func test_cuatro_sotas_no_son_tute() -> void:
	assert_eq(ReglasTute.tute_en_mano(_mano(["Sota_oros", "Sota_copas", "Sota_espadas", "Sota_bastos"])), "",
		"Las cuatro sotas son Tute en el Guiñote, no en el Tute")


func test_el_tute_va_antes_que_las_40() -> void:
	var mano := _mano(["Rey_oros", "Rey_copas", "Rey_espadas", "Rey_bastos", "Caballo_oros"])
	assert_eq(ReglasTute.mejor_cante(mano, OROS, []).get("tipo"), "tute")


func test_texto_de_los_botones_de_cantar() -> void:
	assert_eq(ReglasTute.texto_cante({"tipo": "cante", "palo": OROS, "puntos": 40}), "Cantar las 40 (oros)")
	assert_eq(ReglasTute.texto_cante({"tipo": "cante", "palo": COPAS, "puntos": 20}), "Cantar las 20 en copas")
	assert_eq(ReglasTute.texto_cante({"tipo": "tute", "figura": "reyes"}), "Cantar TUTE de reyes")


# --- Tanteo ---

func test_tanteo_por_parejas_con_diez_de_ultimas() -> void:
	var cartas := [_mano(["As_oros", "Tres_oros"]), _mano(["Rey_copas"]), _mano(["Caballo_espadas"]), []]
	var t := ReglasTute.tanteo(cartas, [20, 0, 0, 40], 1)
	# Pareja A (asientos 0 y 2): 11 + 10 + 3 de cartas y 20 de cantes.
	# Pareja B (asientos 1 y 3): 4 de cartas, 40 de cantes y las diez de últimas.
	assert_eq(t["cartas"], [24, 4])
	assert_eq(t["cantes"], [20, 40])
	assert_eq(t["ultimas"], [0, 10])
	assert_eq(t["total"], [44, 54])
	assert_eq(t["ganador"], 1)


func test_si_empatan_gana_la_pareja_de_la_ultima_baza() -> void:
	var t := ReglasTute.tanteo([[], [], [], []], [0, 0, 10, 0], 3)
	assert_eq(t["total"], [10, 10])
	assert_eq(t["ganador"], 1)


func test_parejas_y_companeros() -> void:
	assert_eq(ReglasTute.companero(0), 2)
	assert_eq(ReglasTute.companero(3), 1)
	assert_eq(ReglasTute.equipo(2), 0)
	assert_eq(ReglasTute.equipo(1), 1)
