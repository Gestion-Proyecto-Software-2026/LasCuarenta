extends GutTest
## Pantalla de historial y estadísticas (PBI-06). Como en el resto de pantallas
## del cliente, ClienteApi se sustituye por un doble; la navegación también
## ([member historial.ir_a]), así que aquí sí se comprueba a dónde se iría.

const HISTORIAL := preload("res://client/ui/historial/historial.tscn")
const Historial := preload("res://client/ui/historial/historial.gd")
const ClienteApiFalso := preload("res://tests/unit/client/cliente_api_falso.gd")

const ANA := "00000000-0000-4000-8000-000000000000"
const LUIS := "11111111-1111-4111-8111-111111111111"

const ESTADISTICAS := {
	"usuario_id": ANA,
	"nombre_visible": "Ana",
	"historial_publico": true,
	"totales": {"jugadas": 3.0, "victorias": 2.0, "derrotas": 1.0, "porcentaje_victorias": 66.7},
	"por_juego": [
		{"juego": "guinote", "jugadas": 2.0, "victorias": 2.0, "derrotas": 0.0, "porcentaje_victorias": 100.0},
		{"juego": "mus", "jugadas": 1.0, "victorias": 0.0, "derrotas": 1.0, "porcentaje_victorias": 0.0},
		{"juego": "tute", "jugadas": 0.0, "victorias": 0.0, "derrotas": 0.0, "porcentaje_victorias": 0.0},
	],
	"racha_actual": {"tipo": "victoria", "partidas": 2.0},
	"mejor_racha_victorias": 2.0,
	"ultimos_resultados": ["victoria", "victoria", "derrota"],
}

const GUINOTE := {
	"partida_id": "b0000000-0000-4000-8000-000000000000",
	"juego": "guinote", "num_jugadores": 4.0,
	"fecha_inicio": "2026-11-18T10:00:00.000Z", "fecha_fin": "2026-11-18T10:24:13.000Z",
	"resultado": "victoria", "gano": true, "causa": "completa", "motivo": "tantos",
	"equipo": 0.0, "puntos_equipo": 105.0, "puntos_rival": 52.0,
	"companeros": [{"usuario_id": "u3", "nombre_visible": "Marta", "posicion": 2.0}],
	"rivales": [
		{"usuario_id": LUIS, "nombre_visible": "Luis", "posicion": 1.0},
		{"usuario_id": "u4", "nombre_visible": "Pedro", "posicion": 3.0},
	],
}
const MUS := {
	"partida_id": "a0000000-0000-4000-8000-000000000000",
	"juego": "mus", "num_jugadores": 2.0,
	"fecha_inicio": "2026-11-17T18:00:00.000Z", "fecha_fin": "2026-11-17T18:40:00.000Z",
	"resultado": "derrota", "gano": false, "causa": "completa", "motivo": null,
	"equipo": 1.0, "puntos_equipo": 1.0, "puntos_rival": 2.0,
	"companeros": [],
	"rivales": [{"usuario_id": LUIS, "nombre_visible": "Luis", "posicion": 0.0}],
}

var api
var historial
var navegaciones: Array[String] = []


func before_each() -> void:
	api = ClienteApiFalso.new()
	api.usuario = {"id": ANA, "nombre_visible": "Ana"}
	api.respuesta_estadisticas = {"ok": true, "codigo": 200, "datos": ESTADISTICAS.duplicate(true)}
	api.respuesta_historial = {"ok": true, "codigo": 200, "datos": [GUINOTE, MUS]}
	add_child_autofree(api)
	navegaciones.clear()


func after_each() -> void:
	Historial.usuario_a_consultar = "me"


# --- Ayudas ---

## Abre la pantalla (la de [param usuario], si no es la tuya) y espera a que
## lleguen las respuestas del doble, que tardan un frame cada una.
func _abrir(usuario := "me") -> void:
	Historial.usuario_a_consultar = usuario
	historial = HISTORIAL.instantiate()
	historial.api = api
	historial.ir_a = func(escena: String) -> void: navegaciones.append(escena)
	historial.desfase_min = 60
	add_child_autofree(historial)
	await _esperar_respuestas()


func _esperar_respuestas() -> void:
	await wait_process_frames(4)


func _nodo(nombre: String) -> Node:
	return historial.find_child(nombre, true, false)


func _filas() -> Array[Node]:
	return _nodo("ListaPartidas").get_children()


func _texto_de_fila(fila: Node, etiqueta: String) -> String:
	return (fila.find_child(etiqueta, true, false) as Label).text


# --- Al entrar ---

func test_al_entrar_pide_tus_estadisticas_y_tus_partidas() -> void:
	await _abrir()

	assert_eq(api.llamadas, [["estadisticas", "me"], ["historial", "me", ""]])
	assert_eq((_nodo("EtiquetaSubtitulo") as Label).text, "Tus partidas")
	assert_eq(Historial.usuario_a_consultar, "me")


func test_pinta_el_resumen_de_estadisticas() -> void:
	await _abrir()

	assert_true(_nodo("PanelEstadisticas").visible)
	assert_eq((_nodo("EtiquetaResumen") as Label).text, "3 partidas · 2 victorias · 1 derrota · 66,7 % de victorias")
	assert_eq((_nodo("EtiquetaPorJuego") as Label).text,
		"Guiñote: 2 partidas · 2 victorias · 0 derrotas · 100 %\nMus: 1 partida · 0 victorias · 1 derrota · 0 %",
		"el Tute, sin partidas, no sale")
	assert_eq((_nodo("EtiquetaRachas") as Label).text, "Racha: 2 victorias seguidas · Mejor racha: 2 victorias seguidas")
	var ultimos := _nodo("UltimosResultados") as RichTextLabel
	assert_true(ultimos.visible)
	assert_eq(ultimos.get_parsed_text(), "Últimos resultados: V V D")


func test_una_fila_por_partida_con_sus_datos() -> void:
	await _abrir()

	assert_eq(_filas().size(), 2)
	var fila := _filas()[0]
	assert_eq(_texto_de_fila(fila, "EtiquetaResultado"), "VICTORIA")
	assert_eq(_texto_de_fila(fila, "EtiquetaJuego"), "Guiñote · por parejas")
	assert_eq(_texto_de_fila(fila, "EtiquetaMarcador"), "105 – 52")
	assert_eq(_texto_de_fila(fila, "EtiquetaDetalle"), "18/11/2026 11:24 · 24 min · Por tantos")
	assert_eq(_texto_de_fila(fila, "EtiquetaJugadores"), "Con Marta · Contra Luis y Pedro")
	var mus := _filas()[1]
	assert_eq(_texto_de_fila(mus, "EtiquetaResultado"), "DERROTA")
	assert_eq(_texto_de_fila(mus, "EtiquetaMarcador"), "1 – 2 juegos")
	assert_eq(_texto_de_fila(mus, "EtiquetaJugadores"), "Contra Luis")
	assert_false(_nodo("EtiquetaVacia").visible)


func test_de_la_mas_reciente_a_la_mas_antigua_aunque_lleguen_desordenadas() -> void:
	api.respuesta_historial = {"ok": true, "codigo": 200, "datos": [MUS, GUINOTE]}
	await _abrir()

	assert_eq(_filas().map(func(fila: Node) -> String: return fila.partida_id),
		[GUINOTE["partida_id"], MUS["partida_id"]])


func test_ordenar_por_fecha_deja_al_final_las_que_no_la_tienen_y_desempata_por_id() -> void:
	var sin_fecha := {"partida_id": "z", "fecha_fin": null}
	var a := {"partida_id": "a", "fecha_fin": "2026-11-18T10:00:00.000Z"}
	var b := {"partida_id": "b", "fecha_fin": "2026-11-18T10:00:00.000Z"}
	var antigua := {"partida_id": "c", "fecha_fin": "2025-01-01T00:00:00.000Z"}

	assert_eq(Historial.ordenar_por_fecha([sin_fecha, antigua, a, "basura", b]), [b, a, antigua, sin_fecha])


func test_sin_partidas_lo_dice() -> void:
	api.respuesta_historial = {"ok": true, "codigo": 200, "datos": []}
	await _abrir()

	assert_true(_nodo("EtiquetaVacia").visible)
	assert_eq((_nodo("EtiquetaVacia") as Label).text, "Todavía no hay partidas terminadas.")
	assert_false(_nodo("Lista").visible)


func test_los_controles_se_bloquean_mientras_carga() -> void:
	Historial.usuario_a_consultar = "me"
	historial = HISTORIAL.instantiate()
	historial.api = api
	add_child_autofree(historial)

	assert_true((_nodo("OpcionJuego") as OptionButton).disabled)
	assert_true((_nodo("BotonActualizar") as Button).disabled)
	await _esperar_respuestas()
	assert_false((_nodo("OpcionJuego") as OptionButton).disabled)
	assert_false((_nodo("BotonActualizar") as Button).disabled)


# --- Filtro y actualizar ---

func test_el_filtro_pide_las_partidas_de_ese_juego() -> void:
	await _abrir()
	api.respuesta_historial = {"ok": true, "codigo": 200, "datos": [MUS]}

	var filtro := _nodo("OpcionJuego") as OptionButton
	assert_eq(filtro.item_count, 4)
	assert_eq(filtro.get_item_text(2), "Mus")
	filtro.select(2)
	filtro.item_selected.emit(2)
	await _esperar_respuestas()

	assert_eq(api.llamadas.back(), ["historial", "me", "mus"])
	assert_eq(api.veces_llamado("estadisticas"), 1, "las estadísticas no dependen del filtro")
	assert_eq(_filas().size(), 1)


func test_actualizar_lo_vuelve_a_pedir_todo_con_el_filtro_puesto() -> void:
	await _abrir()
	var filtro := _nodo("OpcionJuego") as OptionButton
	filtro.select(1)
	filtro.item_selected.emit(1)
	await _esperar_respuestas()

	(_nodo("BotonActualizar") as Button).pressed.emit()
	await _esperar_respuestas()

	assert_eq(api.veces_llamado("estadisticas"), 2)
	assert_eq(api.llamadas.back(), ["historial", "me", "guinote"])


# --- Privacidad ---

func test_el_interruptor_dice_si_tu_historial_es_publico() -> void:
	api.respuesta_estadisticas["datos"]["historial_publico"] = false
	await _abrir()

	var interruptor := _nodo("InterruptorPublico") as CheckButton
	assert_true(interruptor.visible)
	assert_false(interruptor.button_pressed)
	assert_false(interruptor.disabled)
	assert_eq(api.veces_llamado("cambiar_privacidad"), 0, "pintarlo no cambia nada en el backend")


func test_sin_saber_si_tu_historial_es_publico_el_interruptor_no_se_puede_tocar() -> void:
	api.respuesta_estadisticas = {"ok": false, "codigo": 0, "datos": null}
	await _abrir()

	var interruptor := _nodo("InterruptorPublico") as CheckButton
	assert_true(interruptor.disabled, "enseñaría el valor por defecto de la escena, no el tuyo")
	assert_false((_nodo("BotonActualizar") as Button).disabled, "se puede volver a intentar")

	api.respuesta_estadisticas = {"ok": true, "codigo": 200, "datos": ESTADISTICAS.duplicate(true)}
	api.respuesta_estadisticas["datos"]["historial_publico"] = false
	(_nodo("BotonActualizar") as Button).pressed.emit()
	await _esperar_respuestas()

	assert_false(interruptor.disabled, "en cuanto el backend lo dice, ya se puede cambiar")
	assert_false(interruptor.button_pressed)
	assert_eq(api.veces_llamado("cambiar_privacidad"), 0)


func test_cambiar_el_interruptor_cambia_la_privacidad() -> void:
	api.respuesta_cambiar_privacidad = {"ok": true, "codigo": 200, "datos": {"historial_publico": false}}
	await _abrir()

	var interruptor := _nodo("InterruptorPublico") as CheckButton
	interruptor.button_pressed = false
	await _esperar_respuestas()

	assert_eq(api.llamadas.back(), ["cambiar_privacidad", false])
	assert_false(interruptor.button_pressed)
	assert_false(_nodo("EtiquetaError").visible)


func test_si_no_se_puede_cambiar_la_privacidad_vuelve_a_como_estaba() -> void:
	api.respuesta_cambiar_privacidad = {"ok": false, "codigo": 500, "datos": {"error": "error interno"}}
	await _abrir()

	var interruptor := _nodo("InterruptorPublico") as CheckButton
	interruptor.button_pressed = false
	await _esperar_respuestas()

	assert_true(interruptor.button_pressed)
	assert_true(_nodo("EtiquetaError").visible)
	assert_eq((_nodo("EtiquetaError") as Label).text, "error interno")
	assert_eq(api.veces_llamado("cambiar_privacidad"), 1, "volver a su valor no lo vuelve a pedir")


# --- Historial de otro jugador ---

func test_el_historial_de_otro_jugador() -> void:
	var de_luis := ESTADISTICAS.duplicate(true)
	de_luis["usuario_id"] = LUIS
	de_luis["nombre_visible"] = "Luis"
	api.respuesta_estadisticas = {"ok": true, "codigo": 200, "datos": de_luis}
	await _abrir(LUIS)

	assert_eq(api.llamadas, [["estadisticas", LUIS], ["historial", LUIS, ""]])
	assert_eq((_nodo("EtiquetaSubtitulo") as Label).text, "Partidas de Luis")
	assert_false(_nodo("InterruptorPublico").visible, "la privacidad solo la cambia el titular")
	assert_eq(Historial.usuario_a_consultar, "me", "la próxima vez se abre el tuyo")


func test_tu_propio_id_es_tu_historial() -> void:
	await _abrir(ANA)

	assert_eq(api.llamadas[0], ["estadisticas", "me"])
	assert_eq((_nodo("EtiquetaSubtitulo") as Label).text, "Tus partidas")
	assert_true(_nodo("InterruptorPublico").visible)


func test_un_historial_privado_lo_dice_y_no_pide_las_partidas() -> void:
	api.respuesta_estadisticas = {"ok": false, "codigo": 403, "datos": {"error": "este historial es privado"}}
	await _abrir(LUIS)

	assert_eq((_nodo("EtiquetaError") as Label).text, "Este jugador tiene su historial en privado.")
	assert_true(_nodo("EtiquetaError").visible)
	assert_false(_nodo("PanelEstadisticas").visible)
	assert_eq(api.veces_llamado("historial"), 0)
	assert_eq(_filas().size(), 0)


func test_si_lo_hace_privado_mientras_lo_miras_desaparece_al_actualizar() -> void:
	await _abrir(LUIS)
	api.respuesta_estadisticas = {"ok": false, "codigo": 403, "datos": {"error": "este historial es privado"}}

	(_nodo("BotonActualizar") as Button).pressed.emit()
	await _esperar_respuestas()

	assert_eq((_nodo("EtiquetaError") as Label).text, "Este jugador tiene su historial en privado.")
	assert_false(_nodo("PanelEstadisticas").visible)
	assert_false(_nodo("Lista").visible)


# --- Errores y navegación ---

func test_sin_conexion_lo_dice() -> void:
	api.respuesta_estadisticas = {"ok": false, "codigo": 0, "datos": null}
	await _abrir()

	assert_eq((_nodo("EtiquetaError") as Label).text, "No se pudo conectar con el servidor")


func test_un_error_al_pedir_las_partidas_no_deja_las_de_antes() -> void:
	await _abrir()
	api.respuesta_historial = {"ok": false, "codigo": 500, "datos": {"error": "error interno"}}

	(_nodo("BotonActualizar") as Button).pressed.emit()
	await _esperar_respuestas()

	assert_eq((_nodo("EtiquetaError") as Label).text, "error interno")
	assert_false(_nodo("Lista").visible)
	assert_false(_nodo("EtiquetaVacia").visible, "no es que no haya partidas")


func test_con_la_sesion_caducada_vuelve_al_login() -> void:
	api.respuesta_estadisticas = {"ok": false, "codigo": 401, "datos": {"error": "token no válido"}}
	await _abrir()

	assert_false(api.esta_autenticado(), "se cierra la sesión")
	assert_eq(navegaciones, [Historial.ESCENA_LOGIN] as Array[String])


func test_sin_sesion_va_al_login_sin_pedir_nada() -> void:
	api.autenticado = false
	await _abrir()

	assert_eq(navegaciones, [Historial.ESCENA_LOGIN] as Array[String])
	assert_eq(api.llamadas, [])


func test_volver_al_lobby() -> void:
	await _abrir()

	var volver := _nodo("BotonVolver") as Button
	assert_eq(volver.text, "VOLVER AL LOBBY")
	volver.pressed.emit()

	assert_eq(navegaciones, [Historial.ESCENA_LOBBY] as Array[String])
	assert_true(ResourceLoader.exists(Historial.ESCENA_LOBBY))
	assert_true(ResourceLoader.exists(Historial.ESCENA_LOGIN))
