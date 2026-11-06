extends Control
## Mesa de juego de Guiñote a 2 jugadores, con la interfaz visual portada de
## game_javivi (mesa con abanico de mano y arrastre de cartas, ver
## tapete_guinote.gd). El canal con el servidor es el mismo que el de la
## pantalla de 4 jugadores (partida.gd): `ClienteRed.estado_actualizado` trae
## la `vista_para_jugador` + `jugadas_validas` ya calculadas por
## motor_guinote.gd, y `red.enviar(tipo, payload)` manda las jugadas — nunca
## decide aquí si una jugada es válida.

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
const AccionesGuinote := preload("res://client/ui/partida/acciones_guinote.gd")

const BOTON_NORMAL := preload("res://client/ui/theme/boton_dorado_normal.tres")
const BOTON_HOVER := preload("res://client/ui/theme/boton_dorado_hover.tres")
const BOTON_PRESSED := preload("res://client/ui/theme/boton_dorado_pressed.tres")
const FUENTE_BOLD := preload("res://client/ui/theme/fuente_titulo_bold.tres")

## Tiempo que se deja la baza completa (las dos cartas) a la vista antes de
## redibujar el estado "real" que ya trae la baza siguiente vacía/el robo
## hecho. `motor_guinote.gd::_resolver_baza` limpia `baza_actual` y rellena
## `ultima_baza` {ganador, cartas} en la misma jugada que completa la baza, así
## que el cliente NUNCA recibe un `estado_partida` con las dos cartas a la vez
## en `baza_actual` — hay que construir ese estado intermedio a partir de
## `ultima_baza` para poder enseñarlo antes de pasar al estado real.
const COOLDOWN_BAZA_COMPLETA := 2.5

@onready var etiqueta_fase: Label = %EtiquetaFase
@onready var etiqueta_tanteo: Label = %EtiquetaTanteo
@onready var etiqueta_cantes: Label = %EtiquetaCantes
@onready var etiqueta_error: Label = %EtiquetaError
@onready var acciones_especiales: HBoxContainer = %AccionesEspeciales
@onready var tapete: Control = %TapeteGuinote
@onready var panel_resultado: PanelContainer = %PanelResultado
@onready var etiqueta_resultado: Label = %EtiquetaResultado
@onready var boton_volver_lobby: Button = %BotonVolverLobby

## Inyectable en tests (doble), igual que en partida.gd.
var red = ClienteRed

var _ultimo_estado_renderizado: Dictionary = {}
var _en_cooldown_baza := false
var _estado_mas_reciente: Dictionary = {}


func _ready() -> void:
	etiqueta_error.visible = false
	panel_resultado.visible = false
	boton_volver_lobby.pressed.connect(_on_boton_volver_lobby_pressed)
	red.estado_actualizado.connect(_renderizar_estado)
	red.error_recibido.connect(_on_error_recibido)
	red.partida_terminada.connect(_on_partida_terminada)
	tapete.jugar_carta_solicitada.connect(_on_jugar_carta_solicitada)

	if not red.ultimo_estado.is_empty():
		_renderizar_estado(red.ultimo_estado)


func _renderizar_estado(estado: Dictionary) -> void:
	etiqueta_error.visible = false
	_estado_mas_reciente = estado
	if _en_cooldown_baza:
		return
	var ultima_baza_anterior: Dictionary = _ultimo_estado_renderizado.get("ultima_baza", {})
	var ultima_baza_nueva: Dictionary = estado.get("ultima_baza", {})
	var baza_recien_completada := not ultima_baza_nueva.is_empty() and ultima_baza_nueva != ultima_baza_anterior
	if baza_recien_completada:
		_en_cooldown_baza = true
		# Estado "de mentira" solo para esta pintura: mismo estado real pero con
		# las dos cartas de la baza que se acaba de ganar en baza_actual, para
		# que se vean juntas el tiempo del cooldown antes de pasar al siguiente
		# estado de verdad (que ya trae baza_actual vacía).
		var estado_transitorio := estado.duplicate()
		estado_transitorio["baza_actual"] = ultima_baza_nueva.get("cartas", [])
		_aplicar_estado(estado_transitorio)
		await get_tree().create_timer(COOLDOWN_BAZA_COMPLETA).timeout
		_en_cooldown_baza = false
		_renderizar_estado(_estado_mas_reciente)
		return
	_aplicar_estado(estado)


func _aplicar_estado(estado: Dictionary) -> void:
	_ultimo_estado_renderizado = estado
	_renderizar_info(estado)
	_renderizar_acciones(estado.get("jugadas_validas", []))
	tapete.actualizar(estado, red.config.get("tu_posicion", -1))


func _renderizar_info(estado: Dictionary) -> void:
	etiqueta_fase.text = "Fase: %s · Mano: %s · Triunfo: %s" % [
		estado.get("fase", "?"), estado.get("mano", "?"), estado.get("palo_triunfo", "?"),
	]
	var bazas: Array = estado.get("bazas_por_equipo", [])
	var tanteo: Array = estado.get("tanteo_idas", [])
	etiqueta_tanteo.text = "Bazas: tú %s · rival %s%s" % [
		bazas[0] if bazas.size() > 0 else 0,
		bazas[1] if bazas.size() > 1 else 0,
		"" if tanteo.is_empty() else " · Idas: %s - %s" % [tanteo[0], tanteo[1]],
	]
	var cantes: Array = estado.get("cantes", [])
	if cantes.is_empty():
		etiqueta_cantes.text = ""
	else:
		var textos: Array = cantes.map(func(c: Dictionary) -> String:
			return "jugador %s canta %s (%s)" % [c["jugador_id"], c["palo"], c["puntos"]])
		etiqueta_cantes.text = "Cantes: " + ", ".join(textos)


## Mismo patrón que partida.gd (comparten AccionesGuinote): un botón por cada
## jugada que no sea "jugar_carta" (esa se juega arrastrando en el tapete).
func _renderizar_acciones(jugadas_validas: Array) -> void:
	for hijo in acciones_especiales.get_children():
		acciones_especiales.remove_child(hijo)
		hijo.queue_free()
	for jugada: Dictionary in AccionesGuinote.jugadas_especiales(jugadas_validas):
		var boton := _crear_boton_accion(jugada)
		acciones_especiales.add_child(boton)
		_animar_aparicion(boton)


## Mismo botón dorado que el resto de la interfaz (login, lobby…), en vez del
## `Button` por defecto sin estilo que quedaba soso sobre el tapete.
func _crear_boton_accion(jugada: Dictionary) -> Button:
	var boton := Button.new()
	boton.text = AccionesGuinote.texto(jugada)
	boton.custom_minimum_size = Vector2(0, 44)
	boton.add_theme_font_override("font", FUENTE_BOLD)
	boton.add_theme_font_size_override("font_size", 16)
	boton.add_theme_color_override("font_color", Color(0.106, 0.086, 0.071, 1))
	boton.add_theme_color_override("font_hover_color", Color(0.106, 0.086, 0.071, 1))
	boton.add_theme_color_override("font_pressed_color", Color(0.106, 0.086, 0.071, 1))
	boton.add_theme_stylebox_override("normal", BOTON_NORMAL)
	boton.add_theme_stylebox_override("hover", BOTON_HOVER)
	boton.add_theme_stylebox_override("pressed", BOTON_PRESSED)
	boton.pressed.connect(_on_accion_pulsada.bind(jugada))
	return boton


## Pequeño "pop" de aparición (en vez de surgir de golpe) para que se note que
## hay una acción nueva disponible.
func _animar_aparicion(boton: Button) -> void:
	boton.pivot_offset = boton.custom_minimum_size / 2.0
	boton.scale = Vector2(0.6, 0.6)
	boton.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(boton, "scale", Vector2.ONE, 0.25)
	tween.parallel().tween_property(boton, "modulate:a", 1.0, 0.15)


func _on_jugar_carta_solicitada(carta_id: String) -> void:
	red.enviar(MensajesRed.JUGAR_CARTA, {"carta_id": carta_id})


func _on_accion_pulsada(jugada: Dictionary) -> void:
	var payload := jugada.duplicate()
	var tipo: String = payload.get("tipo", "")
	payload.erase("tipo")
	red.enviar(tipo, payload)


func _on_error_recibido(mensaje: String) -> void:
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _on_partida_terminada(resultado: Dictionary) -> void:
	etiqueta_resultado.text = _texto_resultado(resultado)
	panel_resultado.visible = true


func _texto_resultado(resultado: Dictionary) -> String:
	var tu_posicion: int = red.config.get("tu_posicion", -1)
	var equipo_ganador: int = resultado.get("equipo_ganador", -1)
	var puntos: Array = resultado.get("puntos_por_equipo", [])
	var texto := "¡Has ganado!" if equipo_ganador == tu_posicion else "Has perdido."
	texto += "\nPuntos: tú %s · rival %s" % [
		puntos[tu_posicion] if tu_posicion >= 0 and tu_posicion < puntos.size() else 0,
		puntos[1 - tu_posicion] if tu_posicion in [0, 1] and (1 - tu_posicion) < puntos.size() else 0,
	]
	if resultado.has("motivo"):
		texto += "\nMotivo: %s" % resultado["motivo"]
	return texto


func _on_boton_volver_lobby_pressed() -> void:
	red.desconectar()
	get_tree().change_scene_to_file(ESCENA_LOBBY)
