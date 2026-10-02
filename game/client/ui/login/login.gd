extends Control

@onready var campo_email: LineEdit = %CampoEmail
@onready var campo_password: LineEdit = %CampoPassword
@onready var boton_login: Button = %BotonLogin
@onready var etiqueta_error: Label = %EtiquetaError
@onready var boton_registro: Button = %BotonRegistro
@onready var boton_recuperar: Button = %BotonRecuperar


func _ready() -> void:
	etiqueta_error.visible = false
	boton_login.pressed.connect(_on_boton_login_pressed)
	boton_registro.pressed.connect(_on_boton_registro_pressed)
	boton_recuperar.pressed.connect(_on_boton_recuperar_pressed)


func _on_boton_login_pressed() -> void:
	var email := campo_email.text.strip_edges()
	var password := campo_password.text

	if email.is_empty() or password.is_empty():
		_mostrar_error("Rellena correo y contraseña")
		return

	_bloquear_formulario(true)
	var resultado: Dictionary = await ClienteApi.login(email, password)
	_bloquear_formulario(false)

	if resultado.ok:
		get_tree().change_scene_to_file("res://client/ui/lobby/lobby.tscn")
	else:
		var mensaje := "No se pudo conectar con el servidor"
		if resultado.datos != null:
			mensaje = resultado.datos.get("error", mensaje)
		_mostrar_error(mensaje)


func _on_boton_registro_pressed() -> void:
	get_tree().change_scene_to_file("res://client/ui/registro/registro.tscn")


func _on_boton_recuperar_pressed() -> void:
	get_tree().change_scene_to_file("res://client/ui/recuperar/recuperar.tscn")


func _mostrar_error(mensaje: String) -> void:
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _bloquear_formulario(bloqueado: bool) -> void:
	boton_login.disabled = bloqueado
	campo_email.editable = not bloqueado
	campo_password.editable = not bloqueado
