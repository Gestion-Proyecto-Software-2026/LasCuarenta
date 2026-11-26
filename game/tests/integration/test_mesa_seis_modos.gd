extends GutTest
## PBI-12: los tres juegos, a 2 y a 4 jugadores, se juegan de principio a fin
## con la mesa común contra el servidor de partida. Cada jugador es una pantalla
## partida_mesa.tscn de verdad que juega sola (autojugar) y habla con un
## RoomManager de verdad (con los motores de main_server.gd) por red_en_bucle.gd.
##
## PBI-22, criterio 6 (verificación automática): cada modo se juega dos veces,
## con las animaciones activadas y desactivadas, y las dos partidas terminan
## igual de bien. Las animaciones no retrasan nada (autojugar echa la carta en
## cuanto llega, aunque aún esté volando), así que no alargan la CI. Cada mesa
## usa unos ajustes de prueba, nunca los del usuario.

const BackendFalso := preload("res://tests/unit/server/backend_falso.gd")
const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const MainServer := preload("res://server/main_server.gd")
const RedEnBucle := preload("res://tests/integration/red_en_bucle.gd")
const PARTIDA_MESA := preload("res://client/ui/mesa/partida_mesa.tscn")
const AjustesScript := preload("res://client/autoload/ajustes.gd")

const SECRETO := "secreto_de_prueba"
const SALA := "7c9e6679-7425-40de-944b-e07fc1f90ae7"
const NOMBRES := ["Ana", "Luis", "Marta", "Pablo"]
const SEGUNDOS_MAXIMOS := 120
const RUTA_AJUSTES := "user://test_ajustes_seis_modos.cfg"
## Cada modo, con animaciones y sin ellas.
const CON_Y_SIN_ANIMACIONES := [true, false]

var backend: Node
var servidor: RoomManager
var redes: Array = []
var mesas: Array = []


func after_each() -> void:
	if FileAccess.file_exists(RUTA_AJUSTES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_AJUSTES))


static func _usuario(posicion: int) -> String:
	return "%d0000000-0000-4000-8000-000000000000" % posicion


## Sienta a todos, abre una mesa por jugador y espera a que acabe la partida.
func _jugar(juego: String, capacidad: int, animaciones: bool) -> void:
	backend = BackendFalso.new()
	add_child_autofree(backend)
	var participantes := []
	for posicion in capacidad:
		participantes.append({"usuario_id": _usuario(posicion), "posicion": posicion,
			"equipo": posicion % 2, "nombre_visible": NOMBRES[posicion]})
	backend.salas[SALA] = {
		"id": SALA, "juego": juego, "estado": "esperando", "capacidad": capacidad, "creador_id": _usuario(0),
		"participantes": participantes,
	}
	servidor = RoomManager.new(backend, SECRETO, MainServer.MOTORES)
	add_child_autofree(servidor)

	redes.clear()
	mesas.clear()
	for posicion in capacidad:
		var red: Node = RedEnBucle.new(servidor, 10 + posicion)
		red.sala_id = SALA
		add_child_autofree(red)
		redes.append(red)
	for posicion in capacidad:
		redes[posicion].unirse_partida(_usuario(posicion), JwtDePrueba.firmar({"id": _usuario(posicion)}, SECRETO))
	redes[0].enviar(MensajesRed.EMPEZAR_PARTIDA)
	var ajustes: Node = AjustesScript.new()
	ajustes.ruta = RUTA_AJUSTES
	add_child_autofree(ajustes)
	ajustes.animaciones = animaciones
	# Como en el cliente: la pantalla de partida se abre cuando llega partida_iniciada.
	for posicion in capacidad:
		assert_eq(redes[posicion].config.get("tu_posicion"), posicion, "todos reciben partida_iniciada")
		var mesa: Control = PARTIDA_MESA.instantiate()
		mesa.red = redes[posicion]
		mesa.autojugar = true
		mesa.pausa_baza = 0.0
		mesa.ajustes = ajustes
		add_child_autofree(mesa)
		mesa.tapete.espera_autojugar_carta = 0.0
		mesa.tapete.espera_autojugar_accion = 0.0
		mesas.append(mesa)

	await wait_until(func() -> bool: return mesas.all(func(m: Control) -> bool: return m._terminada),
		SEGUNDOS_MAXIMOS, "la partida de %s a %d termina en todas las mesas" % [juego, capacidad])


func _comprobar_final(juego: String, capacidad: int, animaciones: bool) -> void:
	assert_false(servidor.salas_activas.has(SALA), "el servidor cierra la sala")
	assert_eq(backend.partidas_registradas.size(), 1, "el resultado se envía al backend")
	for posicion in capacidad:
		var red: Node = redes[posicion]
		assert_eq(red.errores, [] as Array[String], "al jugador %d no se le rechaza ninguna jugada" % posicion)
		assert_true(red.resultado.get("equipo_ganador") in [0, 1], "todos reciben el resultado")
		var mesa: Control = mesas[posicion]
		var panel: Control = mesa.tapete.find_child("PanelResultado", true, false)
		assert_not_null(panel, "la mesa %d enseña el resultado" % posicion)
		if panel:
			assert_true(panel.visible)
			assert_string_starts_with((panel.get_child(0) as Label).text, "FIN DE LA PARTIDA")
		assert_true((mesa.find_child("BotonVolverLobby", true, false) as Button).visible,
			"al acabar se puede volver al lobby")
		assert_eq(mesa.tapete.nombres, NOMBRES.slice(0, capacidad), "la mesa conoce los nombres de %s" % juego)
		var vuelos: int = mesa.tapete.animaciones.vuelos_lanzados
		if animaciones:
			assert_gt(vuelos, 0, "con animaciones, la mesa %d ha animado el reparto" % posicion)
		else:
			assert_eq(vuelos, 0, "sin animaciones, la mesa %d no anima nada" % posicion)


func test_guinote_1_contra_1(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("guinote", 2, animaciones)
	_comprobar_final("guinote", 2, animaciones)


func test_guinote_por_parejas(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("guinote", 4, animaciones)
	_comprobar_final("guinote", 4, animaciones)


func test_tute_1_contra_1(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("tute", 2, animaciones)
	_comprobar_final("tute", 2, animaciones)


func test_tute_por_parejas(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("tute", 4, animaciones)
	_comprobar_final("tute", 4, animaciones)


func test_mus_1_contra_1(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("mus", 2, animaciones)
	_comprobar_final("mus", 2, animaciones)


func test_mus_por_parejas(animaciones: bool = use_parameters(CON_Y_SIN_ANIMACIONES)) -> void:
	await _jugar("mus", 4, animaciones)
	_comprobar_final("mus", 4, animaciones)
