extends Control

const ESCENA_CARTA = preload("res://test/Carta_escena.tscn") # ¡Cambia esta ruta!

@onready var label_turno: Label = $Label 
@onready var nodo_mano:Control = $mano
@onready var area_mano:Area2D = $mano/area_mano
@onready var area_mesa:Area2D = $centro_tapete/area_mesa
@onready var colision_mesa:CollisionShape2D=$centro_tapete/area_mesa/CollisionShape2D
var cartas_en_mano : Array = []
var cartas_sobre_area_mano : Array = [] # Rastrea qué cartas están sobrevolando el área
var cartas_sobre_area_mesa : Array = [] # Rastrea qué cartas están sobrevolando el área
@onready var area_mazo : Area2D =$mazo/area_mazo
#var cartas_area_mazo: Array = []
var ultima_carta_visible : bool = false
var carta_en_mesa = null
@onready var colision_mano = $mano/area_mano/CollisionShape2D
@onready var nodo_mazo: Control = $mazo
@onready var colision_mazo: CollisionShape2D = $mazo/area_mazo/CollisionShape2D
@onready var nodo_centro_oponente: Control = $centro_carta_oponente
var carta_oponente_en_mesa = null # Útil para luego limpiar la mesa cuando acabe la ronda
var cartas_en_mazo: Array = [] # Guardará las referencias visuales de las cartas del mazo

func _ready():
	#generar_mano_inicial()
	pass
func generar_mano_desde_array(cartas_ids: Array):
	for id in cartas_ids:
		var nueva_carta = ESCENA_CARTA.instantiate()
		nodo_mano.add_child(nueva_carta)
		nueva_carta.inicializar(id)
		
		nueva_carta.carta_soltada.connect(_on_carta_soltada)
		cartas_en_mano.append(nueva_carta)
		
	reorganizar_mano()

func actualizar_interfaz_turno(peer_id_activo: int):
	# multiplayer.get_unique_id() nos da la ID del cliente en el que estamos
	if peer_id_activo == multiplayer.get_unique_id():
		label_turno.text = "¡Tu turno!"
		label_turno.modulate = Color.GREEN # Opcional: pintarlo de verde
	else:
		label_turno.text = "Turno del oponente"
		label_turno.modulate = Color.RED # Opcional: pintarlo de rojo

func reorganizar_mano():
	var total = cartas_en_mano.size()
	if total == 0: return
	
	var ancho_total = 400.0 
	var altura_curva = 40.0 
	var rotacion_max = 15.0 
	
	# Calculamos el punto central basado en el CollisionShape2D
	# position del area + position del collision dentro del area
	var centro_abanico = area_mano.position + colision_mano.position
	
	for i in range(total):
		var carta = cartas_en_mano[i]
		
		var t = 0.5 
		if total > 1:
			t = float(i) / float(total - 1)
			
		var pos_x = centro_abanico.x + lerp(-ancho_total/2.0, ancho_total/2.0, t)
		var t_offset = (t - 0.5) * 2.0 
		var pos_y = centro_abanico.y + (t_offset * t_offset) * altura_curva
		var rot = lerp(-rotacion_max, rotacion_max, t)
		
		# ---- NUEVO: GUARDAMOS LAS POSICIONES BASE EN LA CARTA ----
		carta.z_index_base = i
		carta.pos_base = Vector2(pos_x, pos_y)
		carta.rot_base = rot
		
		# Movemos la carta SÓLO si no la estamos arrastrando ni la estamos haciendo Hover
		if carta.current_state == CartaEscene.State.IDLE:
			carta.z_index = i
			FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "position", "valor": carta.pos_base, "dur": 0.4, "trans": Tween.TRANS_CUBIC, "ease": Tween.EASE_OUT},
				{"prop": "rotation_degrees", "valor": carta.rot_base, "dur": 0.4, "trans": Tween.TRANS_CUBIC, "ease": Tween.EASE_OUT}
			], carta)
# --- SISTEMA DE SOLTAR CARTAS ---

# Señal recibida desde la Carta cuando soltamos el clic izquierdo
# --- SISTEMA DE SOLTAR CARTAS EN EL TAPETE ---

func _on_carta_soltada(carta_soltada):
	
	# CASO 1: Se ha soltado en la MESA (Le damos prioridad poniéndolo el primero)
	if cartas_sobre_area_mesa.has(carta_soltada):
		
		# Comprobamos si la mesa está libre
		if carta_en_mesa == null:
			
			# 1. Sacamos la carta de la mano
			if cartas_en_mano.has(carta_soltada):
				cartas_en_mano.erase(carta_soltada)
				
			# 2. La registramos en la mesa y la bloqueamos
			carta_en_mesa = carta_soltada
			carta_soltada.bloqueada = true 
			
			# 3. Le decimos cuál es su nueva posición base (el centro exacto de la colisión de la mesa)
			# Usamos to_local para convertir la posición de la pantalla a la de la carta
			var centro_mesa_global = colision_mesa.global_position
			# Calculamos la posición local restando la posición global del padre (la mano)
			carta_soltada.pos_base = centro_mesa_global - carta_soltada.get_parent().global_position
			carta_soltada.rot_base = 0.0 # Que se quede recta
			carta_soltada.z_index_base = 0 
			
			# 4. Reorganizamos la mano para tapar el hueco que ha dejado
			reorganizar_mano()
			
			# --- NUEVO: AVISAMOS AL SERVIDOR Y DEPURAMOS ---
			print("[CLIENTE ", multiplayer.get_unique_id(), "] Intentando jugar carta: ", carta_soltada.id)
			var controlador = get_node("../juego_guiñote")
			# ¡Esta es la línea clave que faltaba! Avisa al servidor (ID 1)
			controlador.intentar_jugar_carta.rpc_id(1, carta_soltada.id)
			
		else:
			# Si ya hay una carta en la mesa, no se puede jugar.
			# Simplemente reorganizamos y la carta volverá a la mano de donde salió.
			reorganizar_mano()
			
			
	# CASO 2: Se ha soltado DENTRO de la MANO (Reordenar)
	elif cartas_sobre_area_mano.has(carta_soltada):
		if not cartas_en_mano.has(carta_soltada):
			cartas_en_mano.append(carta_soltada)
			
		var nuevo_indice = 0
		for otra_carta in cartas_en_mano:
			if otra_carta != carta_soltada:
				if carta_soltada.global_position.x > otra_carta.global_position.x:
					nuevo_indice += 1
		
		cartas_en_mano.erase(carta_soltada)
		cartas_en_mano.insert(nuevo_indice, carta_soltada)
		reorganizar_mano()
		
		
	# CASO 3: Se ha soltado FUERA de las zonas válidas (Tierra de nadie)
	else:
		reorganizar_mano()

# Conectado a la señal "area_entered" del nodo area_mano
func _on_area_mano_area_entered(area):
	var carta = area.get_parent()
	if carta is CartaEscene and not cartas_sobre_area_mano.has(carta):
		cartas_sobre_area_mano.append(carta)

# Conectado a la señal "area_exited" del nodo area_mano
func _on_area_mano_area_exited(area):
	var carta = area.get_parent()
	if carta is CartaEscene and cartas_sobre_area_mano.has(carta):
		cartas_sobre_area_mano.erase(carta)


func _on_area_mesa_area_entered(area):
	var carta = area.get_parent()
	if carta is CartaEscene and not cartas_sobre_area_mesa.has(carta):
		cartas_sobre_area_mesa.append(carta)


func _on_area_mesa_area_exited(area):
	var carta = area.get_parent()
	if carta is CartaEscene and cartas_sobre_area_mesa.has(carta):
		cartas_sobre_area_mesa.erase(carta)

# --- SISTEMA DEL MAZO ---

# Esta función la llamará el servidor mediante RPC
@rpc("authority", "call_remote", "reliable")
func sincronizar_mazo(cantidad_cartas: int, id_triunfo: String = ""):
	
	# 1. Limpiamos el mazo visual anterior si existía (por si se actualiza a mitad de partida)
	for carta in cartas_en_mazo:
		carta.queue_free()
	cartas_en_mazo.clear()
	
	if cantidad_cartas <= 0: return
	
	# Calculamos el centro local del mazo
	var centro_mazo_global = colision_mazo.global_position
	var centro_mazo_local = centro_mazo_global - nodo_mazo.global_position
	
	# 2. Generamos las cartas una a una de abajo hacia arriba
	for i in range(cantidad_cartas):
		var nueva_carta = ESCENA_CARTA.instantiate()
		nodo_mazo.add_child(nueva_carta)
		
		# SI ES LA PRIMERA CARTA (El fondo) y hay un triunfo definido
		# SI ES LA PRIMERA CARTA (El fondo) y hay un triunfo definido
		if i == 0 and id_triunfo != "":
			nueva_carta.inicializar(id_triunfo)
			nueva_carta.rot_base = 90.0 # Perpendicular
			nueva_carta.pos_base = centro_mazo_local + Vector2(50, 0) 
		
		# EL RESTO DE CARTAS DEL MAZO
		else:
			nueva_carta.inicializar("reverse") # Todas boca abajo
			nueva_carta.rot_base = 0.0
			nueva_carta.pos_base = centro_mazo_local + Vector2(-1 * i, -1 * i)
		
		# --- SOLUCIÓN AL BUG ---
		# Matamos el Tween que se generó automáticamente al hacer add_child()
		if nueva_carta.tween_actual:
			nueva_carta.tween_actual.kill()
		
		# Ahora sí, aplicamos las posiciones iniciales de forma instantánea
		nueva_carta.position = nueva_carta.pos_base
		nueva_carta.rotation_degrees = nueva_carta.rot_base
		nueva_carta.scale = Vector2(0.72, 0.72) # Forzamos la escala base por si el tween la dejó a medias
		
		nueva_carta.z_index_base = i
		nueva_carta.z_index = i
		nueva_carta.bloqueada = true
		nueva_carta.current_state = CartaEscene.State.IDLE 
		
		cartas_en_mazo.append(nueva_carta)
func devolver_carta_rechazada(id_carta: String):
	# Si intentamos jugar fuera de turno, el servidor nos rechaza
	if carta_en_mesa and carta_en_mesa.id == id_carta:
		carta_en_mesa.bloqueada = false
		
		# Al usar append(), la carta se coloca automáticamente en el último hueco del array (a la derecha del todo)
		cartas_en_mano.append(carta_en_mesa)
		carta_en_mesa = null
		
		# Recalculamos el abanico. La carta viajará sola al nuevo hueco de la derecha.
		reorganizar_mano()


func mostrar_carta_jugada_por_rival(peer_id_jugador: int, id_carta: String):
	print("[CLIENTE ", multiplayer.get_unique_id(), "] Ejecutando mostrar_carta_jugada_por_rival para la carta: ", id_carta)
	
	# Si la ID que llega es la nuestra, la ignoramos.
	if peer_id_jugador == multiplayer.get_unique_id():
		print("[CLIENTE ", multiplayer.get_unique_id(), "] Soy yo mismo, ignoro instanciarla de nuevo.")
		return
		
	print("[CLIENTE ", multiplayer.get_unique_id(), "] Instanciando la carta del oponente visualmente.")
	
	# Instanciamos la carta y la hacemos hija del nuevo nodo específico
	var nueva_carta = ESCENA_CARTA.instantiate()
	nodo_centro_oponente.add_child(nueva_carta) 
	nueva_carta.inicializar(id_carta)
	
	var centro_mesa_global = nodo_centro_oponente.global_position
	nueva_carta.pos_base = centro_mesa_global - nodo_centro_oponente.global_position
	
	nueva_carta.rot_base = 0.0 
	nueva_carta.z_index_base = 0 
	
	nueva_carta.position = nueva_carta.pos_base
	if nueva_carta.tween_actual:
		nueva_carta.tween_actual.kill()
		
	nueva_carta.bloqueada = true
	nueva_carta.current_state = CartaEscene.State.IDLE
	
	carta_oponente_en_mesa = nueva_carta

func limpiar_mesa():
	# Eliminamos la carta que jugaste tú
	if carta_en_mesa:
		carta_en_mesa.queue_free()
		carta_en_mesa = null
		
	# Eliminamos la carta que jugó el rival
	if carta_oponente_en_mesa:
		carta_oponente_en_mesa.queue_free()
		carta_oponente_en_mesa = null
