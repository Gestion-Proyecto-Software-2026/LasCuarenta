extends HBoxContainer
## Una sala de la lista del lobby: estado de plazas y botón para unirse.

signal unirse_pulsado(sala_id: String)

@onready var etiqueta: Label = %Etiqueta
@onready var boton_unirse: Button = %BotonUnirse

var sala_id := ""


func _ready() -> void:
	boton_unirse.pressed.connect(_on_boton_unirse_pressed)


## Llamar después de add_child, cuando los nodos únicos ya están listos.
func configurar(sala: Dictionary) -> void:
	sala_id = sala.get("id", "")
	etiqueta.text = "Guiñote · %d/%d jugadores" % [
		sala.get("jugadores_actuales", 0),
		sala.get("capacidad", 4),
	]


func bloquear(bloqueado: bool) -> void:
	boton_unirse.disabled = bloqueado


func _on_boton_unirse_pressed() -> void:
	unirse_pulsado.emit(sala_id)
