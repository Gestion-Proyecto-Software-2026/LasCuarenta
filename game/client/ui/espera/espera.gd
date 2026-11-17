extends Control
## Sala de espera tras crear/unirse a una sala (ver ClienteRed.preparar, llamado
## desde lobby.gd). Conecta por ENet al servidor de partida indicado por
## `servidor_direccion`, envía `unirse_partida` y espera a que el servidor avise
## de que la partida ha empezado. Mientras tanto muestra quién está sentado;
## el creador puede expulsar a los demás y empezar la partida cuando la sala
## está completa (PBI-09).

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
## La mesa común de los tres juegos, a 2 y a 4 jugadores (PBI-12).
const ESCENA_PARTIDA := "res://client/ui/mesa/partida_mesa.tscn"
const COLOR_TEXTO := Color(0.106, 0.086, 0.071, 1)
const COLOR_SECUNDARIO := Color(0.267, 0.157, 0.078, 1)

@onready var etiqueta_estado: Label = %EtiquetaEstado
@onready var etiqueta_error: Label = %EtiquetaError
@onready var boton_volver: Button = %BotonVolver
@onready var boton_empezar: Button = %BotonEmpezar
@onready var lista_jugadores: VBoxContainer = %ListaJugadores

## Inyectables en tests (dobles), igual que `api` en lobby.gd.
var api = ClienteApi
var red = ClienteRed


func _ready() -> void:
	etiqueta_error.visible = false
	boton_volver.pressed.connect(_on_boton_volver_pressed)
	boton_empezar.pressed.connect(_on_boton_empezar_pressed)
	red.sala_actualizada.connect(_on_sala_actualizada)
	red.conectado.connect(_on_conectado)
	red.fallo_conexion.connect(_on_fallo_conexion)
	red.error_recibido.connect(_on_error_recibido)
	red.desconectado_del_servidor.connect(_on_desconectado_del_servidor)
	red.partida_iniciada.connect(_on_partida_iniciada)
	etiqueta_estado.text = "Conectando con el servidor de partida (%s)..." % red.servidor_direccion
	red.conectar_al_servidor()


func _on_conectado() -> void:
	etiqueta_estado.text = "Conectado. Esperando a que se unan los demás jugadores..."
	red.unirse_partida(api.usuario.get("id", ""), api.token)


## Pinta la lista de la sala de espera tal como la manda el servidor:
## { creador_id, capacidad, jugadores: [{ usuario_id, nombre, posicion, conectado }] }.
func _on_sala_actualizada(sala: Dictionary) -> void:
	for fila in lista_jugadores.get_children():
		lista_jugadores.remove_child(fila)
		fila.queue_free()

	var mi_id: String = api.usuario.get("id", "")
	var creador_id: String = str(sala.get("creador_id", ""))
	var soy_creador := not mi_id.is_empty() and mi_id == creador_id
	var jugadores: Array = sala.get("jugadores", [])
	var capacidad := int(sala.get("capacidad", 0))
	for jugador: Dictionary in jugadores:
		lista_jugadores.add_child(_crear_fila(jugador, mi_id, creador_id, soy_creador))

	var completa := capacidad > 0 and jugadores.size() == capacidad \
		and jugadores.all(func(j: Dictionary) -> bool: return j.get("conectado", false))
	boton_empezar.visible = soy_creador
	boton_empezar.disabled = not completa
	if completa:
		etiqueta_estado.text = "Sala completa. Pulsa EMPEZAR cuando queráis." if soy_creador \
			else "Sala completa. Esperando a que el creador empiece la partida..."
	else:
		etiqueta_estado.text = "Esperando jugadores (%d/%d)..." % [jugadores.size(), capacidad]


func _crear_fila(jugador: Dictionary, mi_id: String, creador_id: String, soy_creador: bool) -> HBoxContainer:
	var usuario_id: String = str(jugador.get("usuario_id", ""))
	var fila := HBoxContainer.new()
	fila.name = "Jugador_%s" % usuario_id
	fila.add_theme_constant_override("separation", 8)

	var nombre := Label.new()
	nombre.name = "Nombre"
	var texto: String = str(jugador.get("nombre", ""))
	if texto.is_empty():
		texto = "Jugador %d" % (int(jugador.get("posicion", 0)) + 1)
	if usuario_id == creador_id:
		texto += " (creador)"
	if usuario_id == mi_id:
		texto += " (tú)"
	nombre.text = texto
	nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nombre.clip_text = true
	nombre.add_theme_color_override("font_color", COLOR_TEXTO)
	nombre.add_theme_font_size_override("font_size", 16)
	fila.add_child(nombre)

	var estado := Label.new()
	estado.name = "Estado"
	estado.text = "conectado" if jugador.get("conectado", false) else "conectando..."
	estado.add_theme_color_override("font_color", COLOR_SECUNDARIO)
	estado.add_theme_font_size_override("font_size", 13)
	fila.add_child(estado)

	if soy_creador and usuario_id != mi_id:
		var boton := Button.new()
		boton.name = "BotonExpulsar"
		boton.text = "Expulsar"
		boton.flat = true
		boton.add_theme_color_override("font_color", Color(0.643, 0.11, 0.122, 1))
		boton.add_theme_font_size_override("font_size", 14)
		boton.pressed.connect(_on_expulsar_pulsado.bind(usuario_id, boton))
		fila.add_child(boton)
	return fila


## Expulsa por REST (el backend libera la plaza) y pide al servidor de partida
## que relea la sala: así desconecta al expulsado y avisa al resto.
func _on_expulsar_pulsado(usuario_id: String, boton: Button) -> void:
	boton.disabled = true
	etiqueta_error.visible = false
	var resultado: Dictionary = await api.expulsar_jugador(red.sala_id, usuario_id)
	if resultado.ok:
		red.actualizar_sala()
		return
	if is_instance_valid(boton):
		boton.disabled = false
	etiqueta_error.text = _mensaje_de(resultado)
	etiqueta_error.visible = true


func _on_boton_empezar_pressed() -> void:
	boton_empezar.disabled = true
	etiqueta_error.visible = false
	red.empezar_partida()


func _mensaje_de(resultado: Dictionary) -> String:
	if resultado.datos is Dictionary:
		return resultado.datos.get("error", "No se pudo expulsar al jugador")
	return "No se pudo conectar con el servidor"


func _on_fallo_conexion() -> void:
	_mostrar_error("No se pudo conectar con el servidor de partida.")


func _on_error_recibido(mensaje: String) -> void:
	if _esperando_en_la_sala() and not _es_definitivo(mensaje):
		# Error recuperable de la sala de espera (p. ej. "Faltan jugadores"):
		# se avisa sin cortar la conexión.
		etiqueta_error.text = mensaje
		etiqueta_error.visible = true
		return
	_mostrar_error(mensaje)


func _esperando_en_la_sala() -> bool:
	return not red.sala.is_empty()


## Errores tras los que el servidor cierra la conexión (expulsión, sesión
## duplicada...): hay que volver al lobby.
static func _es_definitivo(mensaje: String) -> bool:
	return mensaje in [
		"El creador de la sala te ha expulsado",
		"Te has conectado a esta partida desde otra sesión",
	]


## El servidor cortó la conexión sin mandar antes un mensaje de error (p. ej.
## se reinició mientras esperábamos a los demás jugadores): antes de esto nos
## quedábamos aquí sin avisar y sin forma de reintentar (CLAUDE.md,
## "Huecos que quedan" en docs/mapa/INDEX.md).
func _on_desconectado_del_servidor() -> void:
	_mostrar_error("Se perdió la conexión con el servidor de partida. Vuelve a intentarlo.")


func _on_partida_iniciada(config: Dictionary) -> void:
	get_tree().change_scene_to_file(_escena_para(config))


## Todos los juegos y modos se juegan en la misma mesa, que se adapta al juego
## y al número de jugadores de `config`. Separado de _on_partida_iniciada para
## poder probarlo sin disparar la navegación real.
func _escena_para(_config: Dictionary) -> String:
	return ESCENA_PARTIDA


func _on_boton_volver_pressed() -> void:
	boton_volver.disabled = true
	await _abandonar_sala()
	get_tree().change_scene_to_file(ESCENA_LOBBY)


## Abandona la sala (si la llegamos a tener, p. ej. la creamos nosotros o nos
## unimos por HTTP) antes de volver al lobby: si no, quedaría como sala
## fantasma (ocupando un hueco, o apareciendo ya "unido" para quien la mire).
## Separado de `_on_boton_volver_pressed` para poder probarlo sin disparar la
## navegación de escena (ver docs/mapa/tests-ci.md).
func _abandonar_sala() -> void:
	await api.salir_sala(red.sala_id)
	red.desconectar()


func _mostrar_error(mensaje: String) -> void:
	red.desconectar()
	boton_empezar.visible = false
	for fila in lista_jugadores.get_children():
		fila.queue_free()
	etiqueta_estado.text = "No se pudo entrar a la partida."
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true
