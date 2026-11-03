extends Sprite2D
## Carta visual con arrastre (drag&drop), resaltado al pasar el ratón por
## encima y shader de borde — puerto de game_javivi/compartido/Escenas/carta/
## Carta_escena.gd para la mesa de Guiñote a 2 jugadores (tapete_guinote.gd).
## Distinta de `game/shared/carta.gd::Carta` (el valor inmutable sin textura
## que viaja por red) y de `game/client/scenes/carta/carta.gd` (otro
## prototipo interno sin terminar, sin arrastre ni abanico): esta es solo la
## representación visual que arrastra el jugador.

const RUTA_TEXTURAS := "res://client/assets/cartas/%s.png"

## Id de la carta ("palo_valor", o "reverso" boca abajo); ver game/shared/carta.gd.
var id: String = ""
var tween_borde: Tween = null
@onready var nodo_borde: Control = $Borde

signal carta_soltada(carta)
var bloqueada: bool = false

var tween_actual: Tween
var z_index_base: int = 0
var pos_base: Vector2 = Vector2.ZERO
var rot_base: float = 0.0

enum State { IDLE, HOVER, CLICKED, DRAG }
var current_state: State = State.IDLE

var dentro: bool = false
var offset_drag: Vector2 = Vector2.ZERO


func _ready() -> void:
	cambiar_estado(State.IDLE)
	# Las señales mouse_entered/exited y el picking de Area2D necesitan que el
	# picking físico esté activado en el viewport; sin esto, _on_area_2d_* no
	# se dispara nunca y la carta no responde al ratón aunque esté bien
	# colocada en pantalla.
	get_viewport().physics_object_picking = true


func _process(_delta: float) -> void:
	if bloqueada:
		return
	if current_state == State.IDLE or current_state == State.HOVER:
		if dentro and soy_la_mas_alta():
			if current_state == State.IDLE:
				cambiar_estado(State.HOVER)
		else:
			if current_state == State.HOVER:
				cambiar_estado(State.IDLE)


func inicializar(nueva_id: String) -> void:
	id = nueva_id
	texture = load(RUTA_TEXTURAS % nueva_id) if not nueva_id.is_empty() else null


func resaltar_borde(tiempo: float = 1.0, color: Color = Color.YELLOW, intermitente: bool = false) -> void:
	if tween_borde:
		tween_borde.kill()

	nodo_borde.modulate = color
	nodo_borde.modulate.a = 0.2
	nodo_borde.visible = true
	tween_borde = FuncionesGlobales.lanzar_tweens_simultaneos([
		{"prop": "modulate:a", "valor": .9, "dur": 0.2}
	], nodo_borde)

	if intermitente:
		tween_borde.set_loops()
		tween_borde.tween_property(nodo_borde, "modulate:a", 0.2, 0.5)
		tween_borde.tween_property(nodo_borde, "modulate:a", 1.0, 0.5)

	if tiempo > 0:
		get_tree().create_timer(tiempo).timeout.connect(parar_resaltar_borde)


func parar_resaltar_borde() -> void:
	if tween_borde:
		tween_borde.kill()
	if nodo_borde:
		nodo_borde.visible = false
		nodo_borde.modulate.a = 1.0


func cambiar_estado(nuevo_estado: State) -> void:
	if tween_actual:
		tween_actual.kill()
	current_state = nuevo_estado

	match current_state:
		State.IDLE:
			z_index = z_index_base
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.72, 0.72), "dur": 0.2},
				{"prop": "modulate", "valor": Color(1, 1, 1, 1), "dur": 0.2},
				{"prop": "position", "valor": pos_base, "dur": 0.2},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.2},
			], self)
		State.HOVER:
			z_index = 100
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.8, 0.8), "dur": 0.1},
				{"prop": "position", "valor": pos_base + Vector2(0, -20), "dur": 0.1},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.1},
			], self)
			resaltar_borde(0)
		State.CLICKED:
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.75, 0.75), "dur": 0.05},
			], self)
		State.DRAG:
			z_index = 101
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "rotation", "valor": 0.0, "dur": 0.1},
				{"prop": "scale", "valor": Vector2(0.8, 0.8), "dur": 0.1},
			], self)


func _on_area_2d_mouse_entered() -> void:
	dentro = true


func _on_area_2d_mouse_exited() -> void:
	dentro = false
	parar_resaltar_borde()


func soy_la_mas_alta() -> bool:
	for hermana: Node in get_parent().get_children():
		if hermana is Node and hermana != self and hermana.get("dentro") == true:
			if hermana.z_index > z_index or (hermana.z_index == z_index and hermana.get_index() > get_index()):
				return false
	return true


func _input(event: InputEvent) -> void:
	if bloqueada:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if dentro and soy_la_mas_alta() and (current_state == State.HOVER or current_state == State.IDLE):
				offset_drag = global_position - get_global_mouse_position()
				cambiar_estado(State.CLICKED)
				get_viewport().set_input_as_handled()
		else:
			if current_state == State.CLICKED or current_state == State.DRAG:
				carta_soltada.emit(self)
				cambiar_estado(State.IDLE)
	elif event is InputEventMouseMotion:
		if current_state == State.CLICKED:
			cambiar_estado(State.DRAG)
		if current_state == State.DRAG:
			global_position = get_global_mouse_position() + offset_drag
