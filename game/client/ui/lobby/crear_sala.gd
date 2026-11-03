extends Control
## Diálogo para crear una sala: juego, capacidad, nombre y contraseña opcional
## (docs/analisis_funcional_app.md §5). Se instancia desde lobby.gd al pulsar
## "Crear sala"; no habla con el backend, solo recoge los datos y los emite.

signal confirmado(juego: String, capacidad: int, nombre: String, password: String)
signal cancelado

## Capacidades admitidas por juego, con la que se preselecciona primero (la
## habitual hasta ahora, 4): duplica a propósito lo que expresa
## jugadores_admitidos() en cada motor de game/server/game_engine/*/motor_*.gd
## (lobbyService.js, en el backend, tiene el mismo mapa por el mismo motivo:
## Node y GDScript no pueden compartir una única fuente de verdad).
const CAPACIDADES_POR_JUEGO := {
	"guinote": [4, 2],
	"mus": [4, 2],
}

@onready var opcion_juego: OptionButton = %OpcionJuego
@onready var opcion_capacidad: OptionButton = %OpcionCapacidad
@onready var campo_nombre: LineEdit = %CampoNombre
@onready var campo_password: LineEdit = %CampoPassword
@onready var boton_crear: Button = %BotonConfirmarCrear
@onready var boton_cancelar: Button = %BotonCancelar


func _ready() -> void:
	opcion_juego.clear()
	for juego: String in CAPACIDADES_POR_JUEGO:
		opcion_juego.add_item(juego.capitalize())
	opcion_juego.item_selected.connect(_on_juego_seleccionado)
	boton_crear.pressed.connect(_on_boton_crear_pressed)
	boton_cancelar.pressed.connect(func() -> void: cancelado.emit())
	_actualizar_capacidades()


func _juego_actual() -> String:
	return (CAPACIDADES_POR_JUEGO.keys() as Array)[opcion_juego.selected]


func _on_juego_seleccionado(_indice: int) -> void:
	_actualizar_capacidades()


func _actualizar_capacidades() -> void:
	opcion_capacidad.clear()
	for capacidad: int in CAPACIDADES_POR_JUEGO[_juego_actual()]:
		opcion_capacidad.add_item("%d jugadores" % capacidad)


func _on_boton_crear_pressed() -> void:
	var capacidad: int = CAPACIDADES_POR_JUEGO[_juego_actual()][opcion_capacidad.selected]
	confirmado.emit(_juego_actual(), capacidad, campo_nombre.text.strip_edges(), campo_password.text)
