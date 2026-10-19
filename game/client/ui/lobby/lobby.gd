extends Control
## Lobby de Guiñote: lista las salas en espera y permite crear o unirse a una.
## Todo va por ClienteApi (REST). ENet solo entra cuando la sala se completa.

const ESCENA_FILA := preload("res://client/ui/lobby/sala_fila.tscn")
const ESCENA_LOGIN := "res://client/ui/login/login.tscn"

@onready var etiqueta_usuario: Label = %EtiquetaUsuario
@onready var etiqueta_error: Label = %EtiquetaError
@onready var etiqueta_vacia: Label = %EtiquetaVacia
@onready var boton_crear: Button = %BotonCrear
@onready var boton_actualizar: Button = %BotonActualizar
@onready var boton_cerrar_sesion: Button = %BotonCerrarSesion
@onready var lista_salas: VBoxContainer = %ListaSalas

## Por defecto el autoload; los tests de GUT lo sustituyen por un doble.
var api = ClienteApi


func _ready() -> void:
	if not api.esta_autenticado():
		get_tree().change_scene_to_file.call_deferred(ESCENA_LOGIN)
		return
	etiqueta_usuario.text = "Bienvenido/a, %s" % api.usuario.get("nombre_visible", "")
	etiqueta_error.visible = false
	boton_crear.pressed.connect(_on_boton_crear_pressed)
	boton_actualizar.pressed.connect(_on_boton_actualizar_pressed)
	boton_cerrar_sesion.pressed.connect(_on_boton_cerrar_sesion_pressed)
	refrescar()


func refrescar() -> void:
	_bloquear(true)
	var resultado: Dictionary = await api.listar_salas()
	_bloquear(false)
	if resultado.ok:
		_pintar_salas(resultado.datos)
	elif resultado.codigo == 401:
		_cerrar_sesion_caducada()
	else:
		_mostrar_error(_mensaje_de(resultado))


func _pintar_salas(salas: Array) -> void:
	for fila in lista_salas.get_children():
		lista_salas.remove_child(fila)
		fila.queue_free()

	etiqueta_vacia.visible = salas.is_empty()
	for sala in salas:
		var fila = ESCENA_FILA.instantiate()
		lista_salas.add_child(fila)
		fila.configurar(sala)
		fila.unirse_pulsado.connect(_on_unirse_pulsado)


func _on_boton_actualizar_pressed() -> void:
	_ocultar_error()
	refrescar()


func _on_boton_crear_pressed() -> void:
	_ocultar_error()
	_bloquear(true)
	var resultado: Dictionary = await api.crear_sala()
	if resultado.ok:
		refrescar()
	elif resultado.codigo == 401:
		_cerrar_sesion_caducada()
	else:
		_bloquear(false)
		_mostrar_error(_mensaje_de(resultado))


func _on_unirse_pulsado(sala_id: String) -> void:
	_ocultar_error()
	_bloquear(true)
	var resultado: Dictionary = await api.unirse_sala(sala_id)
	if resultado.ok:
		refrescar()
	elif resultado.codigo == 401:
		_cerrar_sesion_caducada()
	else:
		_mostrar_error(_mensaje_de(resultado))
		refrescar()


func _on_boton_cerrar_sesion_pressed() -> void:
	api.cerrar_sesion()
	get_tree().change_scene_to_file(ESCENA_LOGIN)


func _cerrar_sesion_caducada() -> void:
	api.cerrar_sesion()
	get_tree().change_scene_to_file(ESCENA_LOGIN)


func _mensaje_de(resultado: Dictionary) -> String:
	if resultado.datos is Dictionary:
		return resultado.datos.get("error", "No se pudo completar la acción")
	return "No se pudo conectar con el servidor"


func _mostrar_error(mensaje: String) -> void:
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _ocultar_error() -> void:
	etiqueta_error.visible = false


func _bloquear(bloqueado: bool) -> void:
	boton_crear.disabled = bloqueado
	boton_actualizar.disabled = bloqueado
	for fila in lista_salas.get_children():
		fila.bloquear(bloqueado)
