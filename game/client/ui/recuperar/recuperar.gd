extends Control

@onready var panel_solicitar: VBoxContainer = %PanelSolicitar
@onready var panel_restablecer: VBoxContainer = %PanelRestablecer
@onready var campo_email: LineEdit = %CampoEmail
@onready var boton_solicitar: Button = %BotonSolicitar
@onready var campo_codigo: LineEdit = %CampoCodigo
@onready var campo_password: LineEdit = %CampoPassword
@onready var campo_confirmar: LineEdit = %CampoConfirmarPassword
@onready var boton_restablecer: Button = %BotonRestablecer
@onready var etiqueta_info: Label = %EtiquetaInfo
@onready var etiqueta_error: Label = %EtiquetaError
@onready var boton_volver: Button = %BotonVolver

var email_actual: String = ""


func _ready() -> void:
	etiqueta_info.visible = false
	etiqueta_error.visible = false
	panel_restablecer.visible = false
	boton_solicitar.pressed.connect(_on_boton_solicitar_pressed)
	boton_restablecer.pressed.connect(_on_boton_restablecer_pressed)
	boton_volver.pressed.connect(_on_boton_volver_pressed)


func _on_boton_solicitar_pressed() -> void:
	var email := campo_email.text.strip_edges()
	if email.is_empty():
		_mostrar_error("Escribe tu correo electrónico")
		return

	_ocultar_mensajes()
	boton_solicitar.disabled = true
	var resultado: Dictionary = await ClienteApi.recuperar(email)
	boton_solicitar.disabled = false

	if resultado.ok:
		email_actual = email
		panel_solicitar.visible = false
		panel_restablecer.visible = true
		_mostrar_info("Si el correo existe, te hemos enviado un código. Revisa tu bandeja de entrada.")
	else:
		var mensaje := "No se pudo conectar con el servidor"
		if resultado.datos != null:
			mensaje = resultado.datos.get("error", mensaje)
		_mostrar_error(mensaje)


func _on_boton_restablecer_pressed() -> void:
	var codigo := campo_codigo.text.strip_edges()
	var password := campo_password.text
	var confirmar := campo_confirmar.text

	if codigo.is_empty() or password.is_empty():
		_mostrar_error("Rellena el código y la contraseña nueva")
		return
	if password != confirmar:
		_mostrar_error("Las contraseñas no coinciden")
		return

	_ocultar_mensajes()
	boton_restablecer.disabled = true
	var resultado: Dictionary = await ClienteApi.restablecer(email_actual, codigo, password)
	boton_restablecer.disabled = false

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
	etiqueta_info.visible = false
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _mostrar_info(mensaje: String) -> void:
	etiqueta_error.visible = false
	etiqueta_info.text = mensaje
	etiqueta_info.visible = true


func _ocultar_mensajes() -> void:
	etiqueta_error.visible = false
	etiqueta_info.visible = false
