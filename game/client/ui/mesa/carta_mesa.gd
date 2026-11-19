class_name CartaMesa
extends Sprite2D
## Carta de la mesa común (tapete_mesa.gd): se arrastra, se levanta al pasar el
## ratón y se le ilumina el borde. Es la carta del prototipo unificado
## (Carta_escena.gd de Javier, con la escala por mesa y el abanico), con las
## imágenes y los ids del cliente ("palo_valor", p. ej. "oros_12"; "reverso"
## boca abajo). No confundir con game/shared/carta.gd::Carta, el valor sin
## textura que usan los motores.

const RUTA_TEXTURAS := "res://client/assets/cartas/%s.png"
const ID_DORSO := "reverso"

signal carta_soltada(carta)  # Avisa a la mesa cuando se suelta el clic

enum State { IDLE, HOVER, CLICKED, DRAG }

var id: String = ID_DORSO
var bloqueada: bool = false
var current_state: State = State.IDLE
var dentro: bool = false
var offset_drag: Vector2 = Vector2.ZERO

var tween_borde: Tween = null
var tween_actual: Tween
## Animación con la que la mano la lleva a su hueco del abanico. Se para al
## cambiar de estado: si no, al echar la carta justo después de robar, el
## abanico la devolvía a la mano.
var tween_abanico: Tween
var z_index_base: int = 0
var pos_base: Vector2 = Vector2.ZERO  # Su posición en el abanico
var rot_base: float = 0.0  # Su rotación en el abanico
## Escala en reposo; el resto de estados (hover, clic, arrastre) escalan en
## proporción a ella.
var escala_base: float = 0.72

@onready var nodo_borde: Control = $Borde


func _ready() -> void:
	cambiar_estado(State.IDLE)
	# Sin el picking físico del viewport, el Area2D de la carta no recibe el
	# ratón (mouse_entered/exited) y la carta no responde.
	get_viewport().physics_object_picking = true


func _process(_delta: float) -> void:
	# Si la carta está bloqueada, no calculamos el hover.
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
	var ruta := RUTA_TEXTURAS % nueva_id
	if not ResourceLoader.exists(ruta):
		push_error("No se ha encontrado la imagen de la carta: " + ruta)
		return
	id = nueva_id
	texture = load(ruta)


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
	# Se mata siempre el tween anterior, sea cual sea el estado.
	if tween_actual:
		tween_actual.kill()
	if tween_abanico:
		tween_abanico.kill()
	current_state = nuevo_estado

	match current_state:
		State.IDLE:
			z_index = z_index_base
			# Vuelve a su posición, rotación y escala base exactas.
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2.ONE * escala_base, "dur": 0.2},
				{"prop": "modulate", "valor": Color(1, 1, 1, 1), "dur": 0.2},
				{"prop": "position", "valor": pos_base, "dur": 0.2},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.2}
			], self)
		State.HOVER:
			z_index = 100
			# Sube 20 px respecto a su pos_base (absoluto, no relativo).
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2.ONE * escala_base * (0.8 / 0.72), "dur": 0.1},
				{"prop": "position", "valor": pos_base + Vector2(0, -20), "dur": 0.1},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.1}
			], self)
			resaltar_borde(0)
		State.CLICKED:
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2.ONE * escala_base * (0.75 / 0.72), "dur": 0.05}
			], self)
		State.DRAG:
			z_index = 101
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "rotation", "valor": 0.0, "dur": 0.1},
				{"prop": "scale", "valor": Vector2.ONE * escala_base * (0.8 / 0.72), "dur": 0.1}
			], self)


func _on_area_2d_mouse_entered() -> void:
	dentro = true


func _on_area_2d_mouse_exited() -> void:
	dentro = false
	parar_resaltar_borde()


func soy_la_mas_alta() -> bool:
	for hermana in get_parent().get_children():
		if hermana is CartaMesa and hermana != self and hermana.dentro:
			# La hermana está por encima (mayor z_index), o en la misma capa
			# pero más a la derecha en el árbol de nodos.
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
				# _process se encarga de volver al IDLE o HOVER correcto en el
				# siguiente frame; aquí solo se fuerza a IDLE un momento.
				cambiar_estado(State.IDLE)
	elif event is InputEventMouseMotion:
		if current_state == State.CLICKED:
			cambiar_estado(State.DRAG)
		if current_state == State.DRAG:
			global_position = get_global_mouse_position() + offset_drag
