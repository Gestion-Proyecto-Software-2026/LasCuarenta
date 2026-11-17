extends Control
## Sala de espera tras crear/unirse a una sala (ver ClienteRed.preparar, llamado
## desde lobby.gd). Conecta por ENet al servidor de partida indicado por
## `servidor_direccion`, envía `unirse_partida` y espera a que el servidor avise
## de que la partida ha empezado (todos los jugadores conectados).

const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
## La mesa común de los tres juegos, a 2 y a 4 jugadores (PBI-12).
const ESCENA_PARTIDA := "res://client/ui/mesa/partida_mesa.tscn"

@onready var etiqueta_estado: Label = %EtiquetaEstado
@onready var etiqueta_error: Label = %EtiquetaError
@onready var boton_volver: Button = %BotonVolver

## Inyectables en tests (dobles), igual que `api` en lobby.gd.
var api = ClienteApi
var red = ClienteRed


func _ready() -> void:
	etiqueta_error.visible = false
	boton_volver.pressed.connect(_on_boton_volver_pressed)
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


func _on_fallo_conexion() -> void:
	_mostrar_error("No se pudo conectar con el servidor de partida.")


func _on_error_recibido(mensaje: String) -> void:
	_mostrar_error(mensaje)


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
	etiqueta_estado.text = "No se pudo entrar a la partida."
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true
