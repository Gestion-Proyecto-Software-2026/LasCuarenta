extends Sprite2D
class_name CartaEscene # Para poder identificarla fácilmente

var id: String ="reverse"
var valor : int = 0
var palo : FuncionesGlobales.palos = FuncionesGlobales.palos.oros
var imagen : CompressedTexture2D 

signal carta_soltada(carta) # Avisará al Tapete cuando soltemos el clic
var bloqueada: bool = false

var tween_actual: Tween
var z_index_base: int = 0 
var pos_base: Vector2 = Vector2.ZERO # Guardará su posición en el abanico
var rot_base: float = 0.0 # Guardará su rotación en el abanico

# Definimos los posibles estados de la carta
enum State { IDLE, HOVER, CLICKED, DRAG }
var current_state: State = State.IDLE

@onready var Label_carta: Label = $Label

var dentro: bool = false
var offset_drag: Vector2 = Vector2.ZERO

func _ready():
	cambiar_estado(State.IDLE)

func _process(_delta):
	# Si la carta está bloqueada, no calculamos el Hover
	if bloqueada: return 
	
	if current_state == State.IDLE or current_state == State.HOVER:
		if dentro and soy_la_mas_alta():
			if current_state == State.IDLE:
				cambiar_estado(State.HOVER)
		else:
			if current_state == State.HOVER:
				cambiar_estado(State.IDLE)

func inicializar(nueva_id: String) -> void:
	var path_cartas = "res://data/Cartas/"
	var ruta_completa = path_cartas + nueva_id + ".tres" 
	
	if ResourceLoader.exists(ruta_completa):
		var recurso_carta: Carta = load(ruta_completa) as Carta
		if recurso_carta != null:
			id = recurso_carta.id
			valor = recurso_carta.valor
			palo = recurso_carta.palo
			imagen = recurso_carta.imagen
			texture = imagen
		else:
			push_error("El archivo existe, pero no es 'Carta': " + ruta_completa)
	else:
		push_error("No se ha encontrado el recurso: " + ruta_completa)

# Máquina de estados
func cambiar_estado(nuevo_estado: State):
	# 1. MATAMOS SIEMPRE EL TWEEN ANTERIOR (sea cual sea el estado)
	if tween_actual:
		tween_actual.kill()
		
	current_state = nuevo_estado
	
	match current_state:
		State.IDLE:
			Label_carta.text = "Idle"
			z_index = z_index_base 
			
			# Volvemos a su posición, rotación y escala base exactas
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.72, 0.72), "dur": 0.2},
				{"prop": "modulate", "valor": Color(1,1,1,1), "dur": 0.2},
				{"prop": "position", "valor": pos_base, "dur": 0.2},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.2}
			], self)

		State.HOVER:
			Label_carta.text = "Hover"
			z_index = 100 
			
			# Subimos 20 px respecto a su pos_base (absoluto, no relativo)
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.8, 0.8), "dur": 0.1},
				{"prop": "position", "valor": pos_base + Vector2(0, -20), "dur": 0.1},
				{"prop": "rotation_degrees", "valor": rot_base, "dur": 0.1}
			], self)

		State.CLICKED:
			Label_carta.text = "Clicked"
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "scale", "valor": Vector2(0.75, 0.75), "dur": 0.05}
			], self)

		State.DRAG:
			Label_carta.text = "Drag"
			z_index = 101 
			tween_actual = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "rotation", "valor": 0.0, "dur": 0.1},
				{"prop": "scale", "valor": Vector2(0.8, 0.8), "dur": 0.1}
			], self)

# Eventos de Área
func _on_area_2d_mouse_entered():
	dentro = true
	#if current_state == State.IDLE:
		#cambiar_estado(State.HOVER)

func _on_area_2d_mouse_exited():
	dentro = false
	#if current_state == State.HOVER:
		#cambiar_estado(State.IDLE)
		
func soy_la_mas_alta() -> bool:
	for hermana in get_parent().get_children():
		if hermana is CartaEscene and hermana != self and hermana.dentro:
			# Si la hermana está por encima (mayor z_index) o está en la misma capa pero más a la derecha en el árbol de nodos
			if hermana.z_index > self.z_index or (hermana.z_index == self.z_index and hermana.get_index() > self.get_index()):
				return false # No somos la más alta
	return true # Sí somos la más alta

# Gestión de Inputs
func _input(event):
	if bloqueada: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: 
			# Usamos nuestra nueva función para el clic
			if dentro and soy_la_mas_alta() and (current_state == State.HOVER or current_state == State.IDLE):
				offset_drag = global_position - get_global_mouse_position()
				cambiar_estado(State.CLICKED)
				get_viewport().set_input_as_handled()
				
		else: 
			if current_state == State.CLICKED or current_state == State.DRAG:
				emit_signal("carta_soltada", self)
				# _process se encargará de volver al IDLE o HOVER correcto en el siguiente frame, 
				# así que aquí solo la forzamos a IDLE momentáneamente
				cambiar_estado(State.IDLE) 
					
	elif event is InputEventMouseMotion:
		if current_state == State.CLICKED:
			cambiar_estado(State.DRAG)
			
		if current_state == State.DRAG:
			global_position = get_global_mouse_position() + offset_drag
