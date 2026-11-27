extends GutTest
## Animaciones de la mesa (PBI-22): las cartas nuevas vuelan del mazo a su sitio,
## se pueden saltar (también con un clic, que sigue sirviendo para coger la
## carta), duran menos de un segundo y, desactivadas, todo aparece ya en su
## sitio. El cambio del siete cruza dos cartas fantasma que siempre se liberan.
## Con unos ajustes de prueba en un fichero temporal, nunca con los de verdad.

const TAPETE := preload("res://client/ui/mesa/tapete_mesa.tscn")
const AnimacionesMesa := preload("res://client/ui/mesa/animaciones_mesa.gd")
const AjustesScript := preload("res://client/autoload/ajustes.gd")
const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")
const RUTA := "user://test_ajustes_animaciones.cfg"
const CERCA := Vector2(0.5, 0.5)

## Guiñote a 2, recién repartido: me toca a mí (asiento 0).
const GUINOTE := {
	"fase": "robo", "dador": 1, "turno": 0, "palo_triunfo": "oros", "pinta": "oros_5",
	"cartas_en_mazo": 28,
	"mi_mano": ["oros_1", "copas_12", "copas_10", "bastos_10", "espadas_3", "oros_7"],
	"cartas_por_jugador": [6, 6], "baza_actual": [], "ultima_baza": {},
	"bazas_por_equipo": [0, 0], "bazas_jugadas": 0, "cantes": [], "tute": {},
	"esperando_cambio_siete": -1, "capote": -1, "mano": "idas", "tanteo_idas": [],
	"ultima_jugada": {},
}
const JUGABLES := [{"tipo": "jugar_carta", "carta_id": "oros_1"}, {"tipo": "jugar_carta", "carta_id": "copas_12"}]

var ajustes: Node
var tapete: Control


func before_each() -> void:
	ajustes = AjustesScript.new()
	ajustes.ruta = RUTA
	add_child_autofree(ajustes)


func after_each() -> void:
	if FileAccess.file_exists(RUTA):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA))


## Una mesa de [param juego] con los ajustes de prueba, todavía sin cartas.
func _mesa(juego := "guinote", jugadores := 2, animaciones := true, liberar_solo := true) -> void:
	ajustes.animaciones = animaciones
	# El ratón, lejos de la mesa: en headless la ventana es diminuta y el ratón se
	# queda en (0, 0), justo donde pasan las cartas; al rozarlo, una carta que
	# vuela se levanta (como debe) y deja de estar donde se mira.
	var lejos := InputEventMouseMotion.new()
	lejos.position = Vector2(100000, 100000)
	get_viewport().push_input(lejos)
	tapete = TAPETE.instantiate()
	tapete.ajustes = ajustes
	if liberar_solo:
		add_child_autofree(tapete)
	else:
		add_child(tapete)
	tapete.configurar_mesa(juego, ["Ana", "Luis", "Marta", "Pablo"].slice(0, jugadores), 0, "oros_5", jugadores - 1)


func _con(estado: Dictionary, cambios: Dictionary) -> Dictionary:
	var nuevo := estado.duplicate(true)
	nuevo.merge(cambios, true)
	return nuevo


## Dónde nace una carta nueva de tu mano: el origen del reparto, en
## coordenadas de la mano.
func _origen_en_la_mano() -> Vector2:
	return tapete.global_position + tapete._origen_reparto() - tapete.nodo_mano.global_position


func _origen_en_los_dorsos(asiento: int) -> Vector2:
	return (tapete.dorsos[asiento] as Node2D).to_local(tapete.global_position + tapete._origen_reparto())


func _sitio_del_dorso(i: int, cuantas: int) -> Vector2:
	return Vector2((i - (cuantas - 1) / 2.0) * tapete.SEPARACION_DORSOS, 0)


func _assert_en_su_hueco(cartas: Array) -> void:
	for carta: CartaMesa in cartas:
		assert_almost_eq(carta.position, carta.pos_base, CERCA, "%s en su hueco" % carta.id)
		assert_almost_eq(carta.rotation_degrees, carta.rot_base, 0.01)


func _assert_dorsos_en_su_sitio(asiento: int) -> void:
	var grupo: Node2D = tapete.dorsos[asiento]
	for i in grupo.get_child_count():
		assert_almost_eq((grupo.get_child(i) as Node2D).position, _sitio_del_dorso(i, grupo.get_child_count()), CERCA)


func _fantasmas() -> Array:
	return tapete.get_children().filter(func(hijo: Node) -> bool:
		return hijo is Sprite2D and hijo.name.begins_with("Fantasma") and not hijo.is_queued_for_deletion())


func _clic(pulsado: bool) -> void:
	var evento := InputEventMouseButton.new()
	evento.button_index = MOUSE_BUTTON_LEFT
	evento.pressed = pulsado
	tapete.get_viewport().push_input(evento)


# --- Vuelos ---

func test_tus_cartas_nuevas_salen_del_mazo_y_acaban_en_su_hueco() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	assert_true(tapete.animaciones.en_curso())
	for carta: CartaMesa in tapete.cartas_en_mano:
		assert_almost_eq(carta.position, _origen_en_la_mano(), CERCA, "%s empieza en el mazo" % carta.id)
		assert_false(carta.bloqueada, "mientras vuela sigue siendo una carta que se puede coger")
	await wait_seconds(1.0)
	assert_false(tapete.animaciones.en_curso())
	_assert_en_su_hueco(tapete.cartas_en_mano)


func test_los_dorsos_nuevos_salen_del_mazo() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	var grupo: Node2D = tapete.dorsos[1]
	assert_eq(grupo.get_child_count(), 6)
	for dorso: Node2D in grupo.get_children():
		assert_almost_eq(dorso.position, _origen_en_los_dorsos(1), CERCA)
	tapete.animaciones.saltar()
	_assert_dorsos_en_su_sitio(1)


func test_al_robar_solo_vuela_la_carta_nueva() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	tapete.animaciones.saltar()
	tapete.actualizar_vista(_con(GUINOTE, {"cartas_en_mazo": 26, "cartas_por_jugador": [7, 7],
		"mi_mano": GUINOTE["mi_mano"] + ["bastos_2"]}), JUGABLES)
	var nueva: CartaMesa = tapete.cartas_en_mano[6]
	assert_eq(nueva.id, "bastos_2")
	assert_almost_eq(nueva.position, _origen_en_la_mano(), CERCA, "la robada sale del mazo")
	assert_ne(tapete.cartas_en_mano[0].position, _origen_en_la_mano(), "las demás no vuelven al mazo")
	var grupo: Node2D = tapete.dorsos[1]
	assert_almost_eq((grupo.get_child(6) as Node2D).position, _origen_en_los_dorsos(1), CERCA, "el dorso robado también")
	assert_almost_eq((grupo.get_child(0) as Node2D).position, _sitio_del_dorso(0, 7), CERCA)
	assert_eq(tapete.animaciones.vuelos_lanzados, 12 + 2)


func test_saltar_lo_deja_todo_en_su_sitio_al_instante() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	assert_true(tapete.animaciones.en_curso(), "justo después, volando")
	tapete.animaciones.saltar()
	assert_false(tapete.animaciones.en_curso())
	_assert_en_su_hueco(tapete.cartas_en_mano)
	_assert_dorsos_en_su_sitio(1)


func test_desactivadas_todo_aparece_ya_en_su_sitio() -> void:
	_mesa("guinote", 2, false)
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	assert_false(tapete.animaciones.en_curso())
	assert_eq(tapete.animaciones.vuelos_lanzados, 0)
	_assert_en_su_hueco(tapete.cartas_en_mano)
	_assert_dorsos_en_su_sitio(1)


func test_desactivarlas_con_algo_en_vuelo_lo_salta() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	ajustes.poner_animaciones(false)
	assert_false(tapete.animaciones.activadas, "la mesa escucha el ajuste")
	assert_false(tapete.animaciones.en_curso())
	_assert_en_su_hueco(tapete.cartas_en_mano)
	ajustes.poner_animaciones(true)
	assert_true(tapete.animaciones.activadas)


func test_con_y_sin_animaciones_la_mano_y_la_baza_son_las_mismas() -> void:
	var resultado := []
	for animaciones in [true, false]:
		_mesa("guinote", 2, animaciones)
		watch_signals(tapete)
		tapete.actualizar_vista(GUINOTE, JUGABLES)
		tapete._jugar_carta_en_mesa(tapete.cartas_en_mano[0])
		assert_signal_emitted_with_parameters(tapete, "jugada_solicitada", [{"tipo": "jugar_carta", "carta_id": "oros_1"}])
		resultado.append([tapete.cartas_en_mano.map(func(c: CartaMesa) -> String: return c.id),
			tapete.carta_en_mesa.id, tapete.dorsos[1].get_child_count()])
		tapete.queue_free()
	assert_eq(resultado[0], resultado[1])


# --- Saltar al pulsar ---

func test_un_clic_durante_el_vuelo_lo_salta_y_la_carta_responde() -> void:
	_mesa()
	watch_signals(tapete)
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	var carta: CartaMesa = tapete.cartas_en_mano[0]
	# El ratón está sobre la carta que vuela (lo que haría el picking físico).
	carta.dentro = true
	_clic(true)
	assert_false(tapete.animaciones.en_curso(), "el clic termina todo lo que vuela")
	_assert_dorsos_en_su_sitio(1)
	assert_almost_eq(carta.position, carta.pos_base, CERCA, "la carta ya está en su hueco")
	assert_eq(carta.current_state, CartaMesa.State.CLICKED, "y el mismo clic la ha cogido")
	# Se suelta sobre la mesa: se echa como siempre.
	tapete.cartas_sobre_area_mesa.append(carta)
	_clic(false)
	assert_signal_emitted_with_parameters(tapete, "jugada_solicitada", [{"tipo": "jugar_carta", "carta_id": "oros_1"}])
	assert_eq(tapete.carta_en_mesa, carta)


func test_la_rueda_del_raton_no_salta_nada() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	for boton in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var rueda := InputEventMouseButton.new()
		rueda.button_index = boton
		rueda.pressed = true
		tapete.get_viewport().push_input(rueda)
	assert_true(tapete.animaciones.en_curso(), "mover la rueda (p. ej. en el chat) no es pulsar")


func test_pulsar_sobre_una_carta_que_vuela_la_para_donde_esta() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	await wait_seconds(0.12)  # que las primeras cartas ya hayan salido del mazo
	var punto: Vector2 = (tapete.cartas_en_mano[0] as CartaMesa).global_position
	# La que se ve bajo el puntero es la de encima de las que se solapan ahí.
	var pulsada: CartaMesa = tapete.animaciones._carta_volando_en(punto)
	assert_not_null(pulsada)
	var donde := pulsada.position
	assert_ne(donde, pulsada.pos_base, "todavía va de camino")
	tapete.animaciones.pulsar_en(punto)
	assert_false(tapete.animaciones.en_curso(), "lo demás salta a su sitio")
	assert_eq(pulsada.position, donde, "la pulsada se queda bajo el puntero: el arrastre la sigue")
	_assert_en_su_hueco(tapete.cartas_en_mano.filter(func(c: CartaMesa) -> bool: return c != pulsada))
	_assert_dorsos_en_su_sitio(1)
	assert_true(tapete.cartas_en_mano.has(pulsada), "y sigue en la mano, utilizable")


func test_sin_nada_volando_el_clic_no_hace_nada_raro() -> void:
	_mesa("guinote", 2, false)
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	_clic(true)
	_clic(false)
	assert_false(tapete.animaciones.en_curso())
	_assert_en_su_hueco(tapete.cartas_en_mano)


# --- Duración ---

func test_cada_vuelo_y_cada_reparto_duran_menos_de_un_segundo() -> void:
	assert_lte(AnimacionesMesa.DURACION_VUELO, 0.4)
	for cartas in range(1, 41):
		var escalonado := AnimacionesMesa.escalonado(cartas)
		assert_lt(AnimacionesMesa.DURACION_VUELO + escalonado * (cartas - 1), 1.0, "reparto de %d cartas" % cartas)
		assert_almost_eq(AnimacionesMesa.duracion_reparto(cartas), AnimacionesMesa.DURACION_VUELO + escalonado * (cartas - 1), 0.0001)


func test_el_reparto_de_las_40_cartas_del_tute_sale_del_sitio_del_mazo_y_dura_menos_de_un_segundo() -> void:
	_mesa("tute", 4)
	var mano := ["oros_1", "oros_3", "oros_12", "copas_1", "copas_3", "copas_12", "bastos_1", "bastos_3", "espadas_1", "espadas_3"]
	tapete.actualizar_vista(_con(GUINOTE, {"fase": "arrastre", "dador": 3, "cartas_en_mazo": 1, "mi_mano": mano,
		"cartas_por_jugador": [10, 10, 10, 10]}), [])
	assert_eq(tapete.animaciones.vuelos_lanzados, 40, "las diez tuyas y los treinta dorsos")
	assert_eq(tapete._origen_reparto(), tapete._pos_pila(), "sin mazo, del sitio donde estaría")
	# Nunca del centro: es donde se sueltan las cartas para jugarlas.
	var zona: CollisionShape2D = tapete.get_node("centro_tapete/area_mesa/CollisionShape2D")
	var rect := Rect2(zona.global_position - zona.shape.size / 2.0, zona.shape.size)
	assert_false(rect.has_point(tapete.global_position + tapete._origen_reparto()), "fuera de la zona de soltar")
	assert_almost_eq(tapete.cartas_en_mano[0].position, _origen_en_la_mano(), CERCA)
	assert_lt(tapete.animaciones.duracion_ultima_tanda, 1.0)
	await wait_seconds(1.0)
	assert_false(tapete.animaciones.en_curso(), "pasado un segundo ya ha llegado todo")
	_assert_en_su_hueco(tapete.cartas_en_mano)
	for asiento in [1, 2, 3]:
		_assert_dorsos_en_su_sitio(asiento)


func test_en_los_juegos_con_mazo_salen_del_mazo() -> void:
	_mesa()
	assert_eq(tapete._origen_reparto(), tapete._pos_pila())


# --- Cambio del siete ---

func test_el_cambio_del_siete_de_otro_cruza_dos_fantasmas_que_se_liberan_al_llegar() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	tapete.animaciones.saltar()
	tapete.animar_cambio_siete(1, "oros_7", "oros_5")
	var fantasmas := _fantasmas()
	assert_eq(fantasmas.size(), 2, "el 7 y la pinta antigua")
	assert_almost_eq((fantasmas[0] as Node2D).position, tapete._pos_dorsos(2), CERCA, "el 7 sale del rival")
	assert_almost_eq((fantasmas[1] as Node2D).position, tapete._pos_pila() + Vector2(62, 0), CERCA, "la pinta, del mazo")
	assert_true(tapete.animaciones.en_curso())
	await wait_seconds(0.6)
	assert_eq(_fantasmas(), [], "al llegar se liberan")
	assert_false(tapete.animaciones.en_curso())


func test_saltar_el_cambio_del_siete_libera_los_fantasmas() -> void:
	_mesa()
	tapete.animar_cambio_siete(1, "oros_7", "oros_5")
	var fantasmas := _fantasmas().map(func(f: Node) -> WeakRef: return weakref(f))
	assert_eq(fantasmas.size(), 2)
	tapete.animaciones.saltar()
	assert_eq(_fantasmas(), [])
	await wait_frames(1)
	for fantasma: WeakRef in fantasmas:
		assert_null(fantasma.get_ref(), "liberado")


func test_si_el_siete_lo_cambias_tu_vuela_tu_siete_y_la_pinta_llega_como_carta_nueva() -> void:
	_mesa()
	tapete.actualizar_vista(GUINOTE, JUGABLES)
	tapete.animaciones.saltar()
	var siete: CartaMesa = tapete.cartas_en_mano[5]
	assert_eq(siete.id, "oros_7")
	tapete.animar_cambio_siete(0, "oros_7", "oros_5")
	var fantasmas := _fantasmas()
	assert_eq(fantasmas.size(), 1, "solo el 7")
	assert_almost_eq((fantasmas[0] as Node2D).position, siete.global_position - tapete.global_position, CERCA)
	var mano: Array = GUINOTE["mi_mano"].duplicate()
	mano[5] = "oros_5"
	tapete.actualizar_vista(_con(GUINOTE, {"pinta": "oros_7", "mi_mano": mano}), JUGABLES)
	var pinta: CartaMesa = tapete.cartas_en_mano[5]
	assert_eq(pinta.id, "oros_5")
	assert_almost_eq(pinta.position, _origen_en_la_mano(), CERCA, "la pinta sale del mazo")
	tapete.animaciones.saltar()
	assert_eq(_fantasmas(), [])
	_assert_en_su_hueco(tapete.cartas_en_mano)


func test_si_se_cierra_la_mesa_a_mitad_no_quedan_fantasmas() -> void:
	_mesa("guinote", 2, true, false)
	tapete.animar_cambio_siete(1, "oros_7", "oros_5")
	var fantasmas := _fantasmas().map(func(f: Node) -> WeakRef: return weakref(f))
	assert_eq(fantasmas.size(), 2)
	tapete.queue_free()
	await wait_frames(1)
	for fantasma: WeakRef in fantasmas:
		assert_null(fantasma.get_ref(), "se van con la mesa")


func test_desactivadas_no_hay_fantasmas() -> void:
	_mesa("guinote", 2, false)
	tapete.animar_cambio_siete(1, "oros_7", "oros_5")
	assert_eq(_fantasmas(), [])


func test_la_pantalla_de_partida_anima_el_cambio_del_siete() -> void:
	var red = ClienteRedFalso.new()
	red.config = {"sala_id": "s1", "juego": "guinote", "tu_posicion": 0, "jugadores": [
		{"usuario_id": "u0", "posicion": 0, "equipo": 0, "nombre": "Ana"},
		{"usuario_id": "u1", "posicion": 1, "equipo": 1, "nombre": "Luis"}]}
	red.ultimo_estado = _con(GUINOTE, {"turno": 1, "jugadas_validas": []})
	add_child_autofree(red)
	var partida: Control = PARTIDA_MESA.instantiate()
	partida.red = red
	partida.ajustes = ajustes
	partida.pausa_baza = 0.0
	add_child_autofree(partida)
	await wait_frames(1)
	tapete = partida.tapete
	assert_eq(tapete.ajustes, ajustes, "la pantalla le pasa sus ajustes a la mesa")
	red.estado_actualizado.emit(_con(GUINOTE, {"turno": 1, "pinta": "oros_7", "jugadas_validas": [],
		"ultima_jugada": {"numero": 1, "jugador_id": 1, "tipo": "cambiar_siete"}}))
	assert_eq(_fantasmas().size(), 2)
	tapete.animaciones.saltar()
