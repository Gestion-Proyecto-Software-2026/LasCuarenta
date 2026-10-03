extends Control

@onready var campo_nombre: LineEdit = %CampoNombreVisible
@onready var campo_email: LineEdit = %CampoEmail
@onready var campo_password: LineEdit = %CampoPassword
@onready var campo_confirmar: LineEdit = %CampoConfirmarPassword
@onready var boton_registro: Button = %BotonRegistro
@onready var etiqueta_error: Label = %EtiquetaError
@onready var boton_volver: Button = %BotonVolver


func _ready() -> void:
	etiqueta_error.visible = false
	boton_registro.pressed.connect(_on_boton_registro_pressed)
	boton_volver.pressed.connect(_on_boton_volver_pressed)


func _on_boton_registro_pressed() -> void:
	var nombre_visible := campo_nombre.text.strip_edges()
	var email := campo_email.text.strip_edges()
	var password := campo_password.text
	var confirmar := campo_confirmar.text

	if nombre_visible.is_empty() or email.is_empty() or password.is_empty():
		_mostrar_error("Rellena todos los campos")
		return
	if password != confirmar:
		_mostrar_error("Las contraseñas no coinciden")
		return

	_bloquear_formulario(true)
	var resultado: Dictionary = await ClienteApi.registrar(email, password, nombre_visible)
	_bloquear_formulario(false)

	if resultado.ok:
		get_tree().change_scene_to_file("res://client/ui/login/login.tscn")
	else:
		var mensaje := "No se pudo conectar con el servidor"
		if resultado.datos != null:
			mensaje = resultado.datos.get("error", mensaje)
		_mostrar_error(mensaje)


func _on_boton_volver_pressed() -> void:
	get_tree().change_scene_to_file("res://client/ui/login/login.tscn")


func _mostrar_error(mensaje: String) -> void:
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _bloquear_formulario(bloqueado: bool) -> void:
	boton_registro.disabled = bloqueado
	campo_nombre.editable = not bloqueado
	campo_email.editable = not bloqueado
	campo_password.editable = not bloqueado
	campo_confirmar.editable = not bloqueado
