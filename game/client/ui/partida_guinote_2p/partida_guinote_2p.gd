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
		var boton := Button.new()
		boton.text = AccionesGuinote.texto(jugada)
		boton.pressed.connect(_on_accion_pulsada.bind(jugada))
		acciones_especiales.add_child(boton)


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
