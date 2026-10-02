extends Control
## Lobby mínimo: solo confirma que el login funcionó y permite cerrar sesión.
## El lobby real (listar/crear/unirse a salas, PBI-02/PBI-09) depende de
## endpoints del backend que todavía no están implementados (devuelven 501).

@onready var etiqueta_usuario: Label = %EtiquetaUsuario
@onready var boton_cerrar_sesion: Button = %BotonCerrarSesion


func _ready() -> void:
	var nombre: String = ClienteApi.usuario.get("nombre_visible", "")
	etiqueta_usuario.text = "Bienvenido/a, %s" % nombre
	boton_cerrar_sesion.pressed.connect(_on_boton_cerrar_sesion_pressed)


func _on_boton_cerrar_sesion_pressed() -> void:
	ClienteApi.cerrar_sesion()
	get_tree().change_scene_to_file("res://client/ui/login/login.tscn")
