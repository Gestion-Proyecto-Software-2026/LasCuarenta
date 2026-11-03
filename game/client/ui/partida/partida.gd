extends Control
## Mesa de juego: pinta el `estado_partida` que manda el servidor y deja hacer
## las jugadas que aparecen en `jugadas_validas` (nunca decide si una jugada es
## válida, igual que dice docs/mapa/cliente.md). De momento solo Guiñote (PBI-03);
## el resto de juegos mandan el mismo tipo de mensajes (docs/mapa/protocolo.md),
## así que esta pantalla podría reutilizarse cuando los admita el lobby.

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
const RUTA_TEXTURAS := "res://client/assets/cartas/%s.png"
const AccionesGuinote := preload("res://client/ui/partida/acciones_guinote.gd")

@onready var etiqueta_fase: Label = %EtiquetaFase
@onready var etiqueta_turno: Label = %EtiquetaTurno
@onready var etiqueta_tanteo: Label = %EtiquetaTanteo
@onready var etiqueta_cantes: Label = %EtiquetaCantes
@onready var etiqueta_error: Label = %EtiquetaError
@onready var baza_actual: HBoxContainer = %BazaActual
@onready var acciones_especiales: HBoxContainer = %AccionesEspeciales
@onready var mano_jugador: HBoxContainer = %ManoJugador
@onready var panel_resultado: PanelContainer = %PanelResultado
@onready var etiqueta_resultado: Label = %EtiquetaResultado
@onready var boton_volver_lobby: Button = %BotonVolverLobby

## Inyectable en tests (doble), igual que `api` en lobby.gd.
var red = ClienteRed


func _ready() -> void:
	etiqueta_error.visible = false
	panel_resultado.visible = false
	boton_volver_lobby.pressed.connect(_on_boton_volver_lobby_pressed)
	red.estado_actualizado.connect(_renderizar_estado)
	red.error_recibido.connect(_on_error_recibido)
	red.partida_terminada.connect(_on_partida_terminada)

	# Puede que estado/partida_iniciada ya hayan llegado antes de entrar a esta
	# escena (CanalRed los cachea en ClienteRed): se pinta lo que ya haya.
	if not red.ultimo_estado.is_empty():
		_renderizar_estado(red.ultimo_estado)


func _renderizar_estado(estado: Dictionary) -> void:
	etiqueta_error.visible = false
	_renderizar_info(estado)
	_renderizar_baza(estado.get("baza_actual", []))
	_renderizar_acciones(estado.get("jugadas_validas", []))
	_renderizar_mano(estado.get("mi_mano", []), estado.get("jugadas_validas", []))


func _renderizar_info(estado: Dictionary) -> void:
	var tu_posicion: int = red.config.get("tu_posicion", -1)
	etiqueta_fase.text = "Fase: %s · Mano: %s · Triunfo: %s" % [
		estado.get("fase", "?"), estado.get("mano", "?"), estado.get("palo_triunfo", "?"),
	]
	if estado.get("turno", -1) == tu_posicion:
		etiqueta_turno.text = "Es tu turno"
	else:
		etiqueta_turno.text = "Turno del jugador %s" % estado.get("turno", "?")
	var bazas: Array = estado.get("bazas_por_equipo", [])
	var tanteo: Array = estado.get("tanteo_idas", [])
	etiqueta_tanteo.text = "Bazas: equipo A %s · equipo B %s%s" % [
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


func _renderizar_baza(jugadas: Array) -> void:
	_vaciar(baza_actual)
	for jugada: Dictionary in jugadas:
		baza_actual.add_child(_crear_carta_vista(jugada.get("carta_id", ""), "J%s" % jugada.get("jugador_id", "?")))


## Botones para jugadas que no son "jugar_carta" (cantar, cantar_tute,
## cambiar_siete...), agrupadas por AccionesGuinote (compartido con la pantalla
## de 2 jugadores) para no repetir un botón por cada carta de la mano que
## permite el mismo cante.
func _renderizar_acciones(jugadas_validas: Array) -> void:
	_vaciar(acciones_especiales)
	for jugada: Dictionary in AccionesGuinote.jugadas_especiales(jugadas_validas):
		var boton := Button.new()
		boton.text = AccionesGuinote.texto(jugada)
		boton.pressed.connect(_on_accion_pulsada.bind(jugada))
		acciones_especiales.add_child(boton)


func _renderizar_mano(mi_mano: Array, jugadas_validas: Array) -> void:
	_vaciar(mano_jugador)
	var cartas_jugables := {}
	for jugada: Dictionary in jugadas_validas:
		if jugada.get("tipo") == MensajesRed.JUGAR_CARTA:
			cartas_jugables[jugada.get("carta_id")] = true
	for carta_id: String in mi_mano:
		var vista := _crear_carta_vista(carta_id, "")
		var boton: TextureButton = vista.get_child(0)
		boton.disabled = not cartas_jugables.has(carta_id)
		if not boton.disabled:
			boton.pressed.connect(_on_carta_pulsada.bind(carta_id))
		mano_jugador.add_child(vista)


func _crear_carta_vista(carta_id: String, pie: String) -> Control:
	var contenedor := VBoxContainer.new()
	var boton := TextureButton.new()
	boton.custom_minimum_size = Vector2(64, 96)
	boton.ignore_texture_size = true
	boton.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	boton.texture_normal = load(RUTA_TEXTURAS % carta_id) if carta_id != "" else null
	contenedor.add_child(boton)
	if not pie.is_empty():
		var etiqueta := Label.new()
		etiqueta.text = pie
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		contenedor.add_child(etiqueta)
	return contenedor


func _on_carta_pulsada(carta_id: String) -> void:
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
	var tu_equipo := tu_posicion % 2 if tu_posicion != -1 else -1
	var equipo_ganador: int = resultado.get("equipo_ganador", -1)
	var puntos: Array = resultado.get("puntos_por_equipo", [])
	var texto := "¡Has ganado!" if equipo_ganador == tu_equipo else "Has perdido."
	texto += "\nPuntos: equipo A %s · equipo B %s" % [
		puntos[0] if puntos.size() > 0 else 0,
		puntos[1] if puntos.size() > 1 else 0,
	]
	if resultado.has("motivo"):
		texto += "\nMotivo: %s" % resultado["motivo"]
	return texto


func _on_boton_volver_lobby_pressed() -> void:
	red.desconectar()
	get_tree().change_scene_to_file(ESCENA_LOBBY)


func _vaciar(contenedor: Node) -> void:
	for hijo in contenedor.get_children():
		contenedor.remove_child(hijo)
		hijo.queue_free()
