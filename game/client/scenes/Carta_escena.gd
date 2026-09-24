extends Sprite2D

var id_carta: String ="reverse"
var valor : int = 0
var palo : Carta.Palo = Carta.Palo.OROS
var imagen : CompressedTexture2D 



# Definimos los posibles estados de la carta
enum State { IDLE, HOVER, CLICKED, DRAG }
var current_state: State = State.IDLE
var crecido : bool = false

@onready var Label_carta: Label = $Label

var dentro: bool = false
var offset_drag: Vector2 = Vector2.ZERO # Guarda la distancia entre el ratón y el centro de la carta al hacer clic

func _ready():
	cambiar_estado(State.IDLE)
func crecer() -> void:
	if !crecido:
		FuncionesGlobales.lanzar_tweens_simultaneos([{
			"prop": "scale", "valor": Vector2(0.8,0.8), "dur": 0.3
		}],self)
		#scale = Vector2(0.8,0.8)
		crecido = true
	else:
		FuncionesGlobales.lanzar_tweens_simultaneos([{
			"prop": "scale", "valor": Vector2(0.72,0.72), "dur": 0.2
		}],self)
		#scale = Vector2(0.72,0.72)
		crecido = false
# Máquina de estados: centraliza qué ocurre cuando entramos en un nuevo estado
func cambiar_estado(nuevo_estado: State):
	current_state = nuevo_estado
	
	match current_state:
		State.IDLE:
			Label_carta.text = "Idle"
			# Aquí puedes devolver el color o la escala a la normalidad
		State.HOVER:
			Label_carta.text = "Hover"
			# Aquí podrías hacer la carta un poco más grande
		State.CLICKED:
			Label_carta.text = "Clicked"
			# Aquí podrías reproducir un sonido o efecto de pulsación
		State.DRAG:
			Label_carta.text = "Drag"
			# Aquí podrías poner la carta por delante de las demás (z_index)

# Eventos de Área
func _on_area_2d_mouse_entered():
	dentro = true
	crecer()
	if current_state == State.IDLE:
		cambiar_estado(State.HOVER)

func _on_area_2d_mouse_exited():
	dentro = false
	crecer()
	if current_state == State.HOVER:
		cambiar_estado(State.IDLE)

# Gestión de Inputs (Clics y Movimiento)
func _input(event):
	# Detección de clics del ratón
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: # Botón presionado
			if dentro and (current_state == State.HOVER or current_state == State.IDLE):
				# Calculamos el offset para que la carta no salte bruscamente al centro del ratón al arrastrar
				offset_drag = global_position - get_global_mouse_position()
				cambiar_estado(State.CLICKED)
		else: # Botón soltado
			if current_state == State.CLICKED or current_state == State.DRAG:
				if dentro:
					cambiar_estado(State.HOVER)
					
				else:
					cambiar_estado(State.IDLE)
					
	# Detección de movimiento del ratón
	elif event is InputEventMouseMotion:
		if current_state == State.CLICKED:
			# Si nos empezamos a mover mientras estábamos "Clicked", pasamos a "Drag"
			cambiar_estado(State.DRAG)
			
		if current_state == State.DRAG:
			# Actualizamos la posición sumando el offset inicial
			global_position = get_global_mouse_position() + offset_drag
