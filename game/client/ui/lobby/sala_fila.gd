extends HBoxContainer
## Una sala de la lista del lobby: estado de plazas y botón para unirse.

const ESCENA_PEDIR_PASSWORD := preload("res://client/ui/lobby/pedir_password.tscn")

## [param password] vacía si la sala no tenía contraseña.
signal unirse_pulsado(sala_id: String, password: String)

@onready var etiqueta: Label = %Etiqueta
@onready var boton_unirse: Button = %BotonUnirse

var sala_id := ""
var _tiene_contrasena := false


func _ready() -> void:
	boton_unirse.pressed.connect(_on_boton_unirse_pressed)


## Llamar después de add_child, cuando los nodos únicos ya están listos.
func configurar(sala: Dictionary) -> void:
	sala_id = sala.get("id", "")
	_tiene_contrasena = sala.get("tiene_contrasena", false)
	var candado := " 🔒" if _tiene_contrasena else ""
	etiqueta.text = "%s%s · %d/%d jugadores%s" % [
		sala.get("nombre", "Sala de Guiñote"),
		candado,
		sala.get("jugadores_actuales", 0),
		sala.get("capacidad", 4),
		_sufijo_nombres(sala.get("jugadores", [])),
	]


## " (Ana, Luis)" con los nombres de quien ya está sentado, o "" si la sala no
## trae esa información (p. ej. los dobles de test que no rellenan `jugadores`).
func _sufijo_nombres(jugadores: Variant) -> String:
	if not jugadores is Array:
		return ""
	var nombres: Array = []
	for jugador: Variant in jugadores:
		if jugador is Dictionary:
			var nombre: String = str(jugador.get("nombre_visible", ""))
			if not nombre.is_empty():
				nombres.append(nombre)
	if nombres.is_empty():
		return ""
	return " (%s)" % ", ".join(nombres)


func bloquear(bloqueado: bool) -> void:
	boton_unirse.disabled = bloqueado


func _on_boton_unirse_pressed() -> void:
	if not _tiene_contrasena:
		unirse_pulsado.emit(sala_id, "")
		return
	var dialogo := ESCENA_PEDIR_PASSWORD.instantiate()
	add_child(dialogo)
	dialogo.confirmada.connect(func(password: String) -> void:
		dialogo.queue_free()
		unirse_pulsado.emit(sala_id, password))
	dialogo.cancelada.connect(dialogo.queue_free)
