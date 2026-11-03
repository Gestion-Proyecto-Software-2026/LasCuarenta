extends Control
## Diálogo mínimo para pedir la contraseña de una sala protegida antes de
## unirse (ver sala_fila.gd). No habla con el backend, solo recoge el dato.

signal confirmada(password: String)
signal cancelada

@onready var campo_password: LineEdit = %CampoPassword
@onready var boton_unirse: Button = %BotonConfirmarUnirse
@onready var boton_cancelar: Button = %BotonCancelar


func _ready() -> void:
	boton_unirse.pressed.connect(func() -> void: confirmada.emit(campo_password.text))
	boton_cancelar.pressed.connect(func() -> void: cancelada.emit())
	campo_password.grab_focus()
