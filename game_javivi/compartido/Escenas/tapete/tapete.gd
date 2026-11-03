extends Control

const ESCENA_CARTA = preload("res://compartido/Escenas/carta/Carta_escena.tscn") # ¡Cambia esta ruta!

## Fondo de la mesa. Para cambiarlo basta con sustituir esta imagen; si no
## existe, se pinta un tapete verde provisional.
const RUTA_FONDO := "res://data/Misc/tapete.png"
const RUTA_DORSO := "res://data/Cartas/reverse.tres"

# --- Mesa de 4 jugadores (Tute por parejas) ---
# En el Guiñote de 2 no se usa nada de esto: hasta que el servidor llama a
# configurar_mesa(), la mesa se comporta igual que antes (salvo el fondo).

## Escala de todas las cartas de la mesa de 4: mano y baza miden lo mismo.
const ESCALA_MESA_4 := 0.5
const ESCALA_DORSO := 0.28
const ESCALA_PINTA := 0.4
const SEPARACION_DORSOS := 20.0
## Hacia dónde se desplaza cada carta de la baza desde el centro, según quién
## la echa: 0 = tú, 1 = rival de la derecha, 2 = compañero, 3 = rival de la izquierda.
const DESPLAZAMIENTO_BAZA := {0: Vector2(0, 82), 1: Vector2(112, 0), 2: Vector2(0, -82), 3: Vector2(-112, 0)}
## Un color por pareja: tu compañero lleva el tuyo y los rivales el otro.
const COLOR_PAREJA := [Color(0.25, 0.6, 1.0), Color(1.0, 0.45, 0.3)]
const COLOR_TURNO := Color(1.0, 0.85, 0.3)
const COLOR_NO_JUGABLE := Color(0.45, 0.45, 0.45)
## Abre y cierra el panel de depuración (solo en builds de depuración).
const TECLA_DEPURACION := KEY_F3
const LINEAS_DEPURACION := 18

## Se emite al recibir el resultado final de la partida.
signal partida_finalizada(texto: String)

@onready var label_turno: Label = $Label
@onready var nodo_mano:Control = $mano
@onready var area_mano:Area2D = $mano/area_mano
@onready var area_mesa:Area2D = $centro_tapete/area_mesa
@onready var colision_mesa:CollisionShape2D=$centro_tapete/area_mesa/CollisionShape2D
@onready var boton_cantar = $BotonCantar
@onready var boton_cambiar_triunfo = $BotonCambiarTriunfo
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
@onready var boton_pasar = $Pasar
var carta_oponente_en_mesa = null # Útil para luego limpiar la mesa cuando acabe la ronda
var cartas_en_mazo: Array = [] # Guardará las referencias visuales de las cartas del mazo

var asientos: Array = [] # peer_id de cada asiento, en el orden en que se juega
var nombres_por_peer: Dictionary = {}
var cartas_otros_en_mesa: Array = [] # Cartas de los otros tres en la baza
var etiquetas_jugador: Dictionary = {} # peer_id -> etiqueta "J#"
var dorsos: Dictionary = {} # peer_id -> Node2D con los dorsos de su mano
var restantes: Dictionary = {} # peer_id -> cartas que le quedan
## Si es true, este cliente juega solo (para probar la partida sin pantalla).
var autojugar: bool = false
## Con autojugar, si pulsa el botón de cantar cuando le sale (true) o lo ignora.
var autocantar: bool = true

var _textura_dorso: Texture2D
var _tween_turno: Tween
var _marcador := ""
var _info_partida := ""
var _registro := PackedStringArray()
var _panel_depuracion: PanelContainer
var _texto_depuracion: Label
var _aviso_espera: Label
var _panel_resultado: PanelContainer

func _ready():
	#generar_mano_inicial()
	boton_cantar.hide()
	boton_cambiar_triunfo.hide()
	boton_pasar.hide()
	_crear_fondo()
	get_viewport().size_changed.connect(_recolocar_mesa)

func generar_mano_desde_array(cartas_ids: Array):
	for id in cartas_ids:
		var nueva_carta = ESCENA_CARTA.instantiate()
		if _modo_mesa_completa():
			nueva_carta.escala_base = ESCALA_MESA_4
		nodo_mano.add_child(nueva_carta)
		nueva_carta.inicializar(id)

		nueva_carta.carta_soltada.connect(_on_carta_soltada)
		cartas_en_mano.append(nueva_carta)

	# En la mesa de 4 todos empiezan con las mismas cartas que tú.
	if _modo_mesa_completa() and restantes.is_empty():
		for peer in asientos:
			if peer != multiplayer.get_unique_id():
				restantes[peer] = cartas_ids.size()
				_dibujar_dorsos(peer)

	reorganizar_mano()

func actualizar_interfaz_turno(peer_id_activo: int):
	if _modo_mesa_completa():
		_marcar_turno(peer_id_activo)
		return
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

	# Con más de 6 cartas (el Tute reparte 10) abrimos el abanico
	var ancho_total = 400.0 + max(0, total - 6) * 45.0
	var altura_curva = 40.0
	var rotacion_max = 15.0

	# Calculamos el punto central basado en el CollisionShape2D
	# position del area + position del collision dentro del area
	var centro_abanico = area_mano.position + colision_mano.position
	# En la mesa de 4 la mano se coloca según el tamaño real de la ventana,
	# para que las cartas se vean enteras.
	if _modo_mesa_completa():
		altura_curva = 24.0
		centro_abanico = global_position + _centro_mano() - nodo_mano.global_position

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
			_jugar_carta_en_mesa(carta_soltada)

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

## Lleva una carta de tu mano al centro de la mesa y se la propone al servidor.
## La usa el arrastre con el ratón y también el modo autojugar.
func _jugar_carta_en_mesa(carta) -> void:
	# 1. Sacamos la carta de la mano
	if cartas_en_mano.has(carta):
		cartas_en_mano.erase(carta)

	# 2. La registramos en la mesa y la bloqueamos
	carta_en_mesa = carta
	carta.bloqueada = true

	# 3. Le decimos cuál es su nueva posición base (el centro exacto de la colisión de la mesa)
	# Usamos to_local para convertir la posición de la pantalla a la de la carta
	var centro_mesa_global = colision_mesa.global_position
	# En la mesa de 4, tu carta va en la baza del centro, desplazada hacia ti.
	if _modo_mesa_completa():
		centro_mesa_global = global_position + _pos_carta_baza(0)
	# Calculamos la posición local restando la posición global del padre (la mano)
	carta.pos_base = centro_mesa_global - carta.get_parent().global_position
	carta.rot_base = 0.0 # Que se quede recta
	carta.z_index_base = 0
	carta.cambiar_estado(CartaEscene.State.IDLE)

	# 4. Reorganizamos la mano para tapar el hueco que ha dejado
	reorganizar_mano()

	# --- NUEVO: AVISAMOS AL SERVIDOR Y DEPURAMOS ---
	print("[CLIENTE ", multiplayer.get_unique_id(), "] Intentando jugar carta: ", carta.id)
	# ¡Esta es la línea clave que faltaba! Avisa al servidor (ID 1)
	_controlador().intentar_jugar_carta.rpc_id(1, carta.id)

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

	# En el Tute no hay mazo: la única carta es la pinta, en su esquina.
	if _modo_mesa_completa():
		_colocar_pinta()
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

	# En la mesa de 4, la carta va a la baza del centro y a ese jugador le queda un dorso menos.
	if _modo_mesa_completa():
		_colocar_carta_de_otro(peer_id_jugador, id_carta)
		restantes[peer_id_jugador] = max(0, restantes.get(peer_id_jugador, 0) - 1)
		_dibujar_dorsos(peer_id_jugador)
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

	# En la mesa de 4, las cartas de los otros tres
	for carta in cartas_otros_en_mesa:
		carta.queue_free()
	cartas_otros_en_mesa.clear()

# El servidor llama a esta función cuando detecta que el jugador puede hacer una acción
@rpc("authority", "call_remote", "reliable")
func activar_acciones_post_baza(puede_cantar: bool, puede_cambiar: bool):
	if puede_cantar:
		boton_cantar.show()
		# Aquí podrías usar la misma lógica de iluminar o un Tween para el botón

	if puede_cambiar:
		boton_cambiar_triunfo.show()

@rpc("authority", "call_remote", "reliable")
func desactivar_acciones_post_baza():
	boton_cantar.hide()
	boton_cambiar_triunfo.hide()
	boton_pasar.hide()

@rpc("authority", "call_remote", "reliable")
func desactivar_boton_cantar():
	boton_cantar.hide()
# Conecta esto a un botón de "Pasar" o llámalo directamente tras cantar/cambiar

@rpc("authority", "call_remote", "reliable")
func actualizar_mano_cambio_triunfo(id_siete: String, id_nuevo_triunfo: String):
	# Buscamos el 7 en nuestra mano y le cambiamos los datos y textura
	for carta in cartas_en_mano:
		if carta.id == id_siete:
			carta.inicializar(id_nuevo_triunfo)
			# Ocultamos el botón de cambiar ya que ya lo usamos
			boton_cambiar_triunfo.hide()
			break

func _on_continuar_sin_accion():
	boton_cantar.hide()
	boton_cambiar_triunfo.hide()
	var controlador = _controlador()
	controlador.rpc_id(1, "jugador_termina_acciones")

func _on_boton_cantar_pressed() -> void:
	boton_cantar.hide()
	var controlador = _controlador()
	controlador.rpc_id(1, "ejecutar_cantar") # Crearemos esto en el servidor

func _on_boton_cambiar_triunfo_pressed()-> void:
	boton_cambiar_triunfo.hide()
	var controlador = _controlador()
	controlador.rpc_id(1, "ejecutar_cambiar_triunfo")

@rpc("authority", "call_remote", "reliable")
func mostrar_botones_ultimo_robo(puede_cantar: bool, puede_cambiar: bool):
	if puede_cantar:
		boton_cantar.show()
	if puede_cambiar:
		boton_cambiar_triunfo.show()

	# En el último robo, si tienes algo que hacer, te aparece "Pasar" por si no quieres hacerlo
	boton_pasar.show()

@rpc("authority", "call_remote", "reliable")
func ocultar_boton_pasar():
	boton_pasar.hide()

# --- Conectar al pressed del BotonPasar ---
func _on_pasar_pressed():
	boton_pasar.hide()
	boton_cantar.hide()
	boton_cambiar_triunfo.hide()

	var controlador = _controlador()
	controlador.rpc_id(1, "pasar_decision_antes_de_robar")

# En tu función desactivar_acciones_post_baza() asegúrate de ocultar también el BotonPasar


# ==========================================
# MESA DE 4 JUGADORES (TUTE). RPCs que solo manda Juego_Tute.
# En pantalla solo hay cartas, dorsos y etiquetas "J#"; todo el texto de
# seguimiento va a la consola y al panel de depuración (F3).
# ==========================================

## El servidor dice quién se sienta dónde, cuál es la pinta y quién reparte.
@rpc("authority", "call_remote", "reliable")
func configurar_mesa(peer_ids: Array, nombres: Array, id_pinta: String, peer_dador: int) -> void:
	asientos = peer_ids
	nombres_por_peer.clear()
	for i in peer_ids.size():
		nombres_por_peer[peer_ids[i]] = nombres[i]
	restantes.clear()
	label_turno.hide()
	if _aviso_espera:
		_aviso_espera.hide()
	_textura_dorso = (load(RUTA_DORSO) as Carta).imagen
	for peer in peer_ids:
		_crear_etiqueta_jugador(peer)
	_info_partida = "Tú: %s (%s)\nTriunfo: %s · pinta: %s, la tiene %s" % [
		nombres_por_peer.get(multiplayer.get_unique_id(), "?"), ReglasTute.NOMBRE_PAREJA[_mi_asiento() % 2],
		_palo_de(id_pinta), _nombre_carta(id_pinta), nombres_por_peer.get(peer_dador, "?")]
	_depurar("Mesa lista. " + _info_partida.replace("\n", " · "))
	_recolocar_mesa()

## Oscurece las cartas que no puedes echar. Lista vacía = no es tu turno.
@rpc("authority", "call_remote", "reliable")
func marcar_cartas_jugables(ids: Array) -> void:
	for carta in cartas_en_mano:
		carta.self_modulate = Color.WHITE if ids.is_empty() or ids.has(carta.id) else COLOR_NO_JUGABLE
	if autojugar and not ids.is_empty():
		_jugar_solo(ids)

## Enseña el botón de cantar con lo que puedes cantar ("Cantar las 40 (oros)"...).
@rpc("authority", "call_remote", "reliable")
func ofrecer_cante(texto: String) -> void:
	_depurar("Puedes cantar: " + texto)
	boton_cantar.text = texto
	boton_cantar.show()
	if autojugar and autocantar:
		_on_boton_cantar_pressed()

## Antes de empezar se ve en el centro ("Esperando jugadores 2/4"); durante la
## partida solo va a la consola y al panel de depuración.
@rpc("authority", "call_remote", "reliable")
func mostrar_aviso(texto: String) -> void:
	_depurar(texto)
	if _modo_mesa_completa():
		return
	if _aviso_espera == null:
		_aviso_espera = _crear_texto(30)
		_aviso_espera.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_aviso_espera)
		_aviso_espera.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_aviso_espera.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_aviso_espera.grow_vertical = Control.GROW_DIRECTION_BOTH
	_aviso_espera.text = texto
	_aviso_espera.show()

## El marcador no se ve durante la mano: se guarda y sale en el resultado final.
@rpc("authority", "call_remote", "reliable")
func actualizar_marcador(texto: String) -> void:
	_marcador = texto
	print("[MESA] Marcador: ", texto.replace("\n", " | "))
	_refrescar_depuracion()

@rpc("authority", "call_remote", "reliable")
func mostrar_resultado(texto: String) -> void:
	boton_cantar.hide()
	boton_cambiar_triunfo.hide()
	boton_pasar.hide()
	for carta in cartas_en_mano:
		carta.bloqueada = true
		carta.self_modulate = Color.WHITE
	_marcar_turno(-1)
	_depurar(texto.replace("\n", " · "))
	if _panel_resultado == null:
		_panel_resultado = PanelContainer.new()
		_panel_resultado.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.82)
		estilo.border_color = COLOR_TURNO
		estilo.set_border_width_all(3)
		estilo.set_corner_radius_all(14)
		estilo.set_content_margin_all(24)
		_panel_resultado.add_theme_stylebox_override("panel", estilo)
		var etiqueta := _crear_texto(20)
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_resultado.add_child(etiqueta)
		_panel_resultado.z_index = 150
		add_child(_panel_resultado)
	var completo := texto
	if _marcador != "":
		completo += "\n\n" + _marcador
	(_panel_resultado.get_child(0) as Label).text = completo
	_panel_resultado.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel_resultado.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_resultado.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel_resultado.show()
	partida_finalizada.emit(texto)

# --- Dónde va cada cosa, calculado sobre el tamaño real de la ventana ---

func _tam() -> Vector2:
	return get_viewport_rect().size

func _centro_baza() -> Vector2:
	return Vector2(_tam().x / 2.0, _tam().y * 0.40)

func _pos_carta_baza(relativa: int) -> Vector2:
	return _centro_baza() + DESPLAZAMIENTO_BAZA[relativa]

func _centro_mano() -> Vector2:
	return Vector2(_tam().x / 2.0, _tam().y - 140.0)

func _pos_dorsos(relativa: int) -> Vector2:
	match relativa:
		1: return Vector2(_tam().x - 46.0, _centro_baza().y)
		2: return Vector2(_tam().x / 2.0, 38.0)
		3: return Vector2(46.0, _centro_baza().y)
	return Vector2.ZERO

func _pos_etiqueta(relativa: int) -> Vector2:
	match relativa:
		0: return Vector2(14.0, 12.0)
		1: return Vector2(_tam().x - 74.0, _centro_baza().y + 125.0)
		2: return Vector2(_tam().x / 2.0 + 140.0, 22.0)
		3: return Vector2(14.0, _centro_baza().y + 125.0)
	return Vector2.ZERO

func _pos_pinta() -> Vector2:
	return Vector2(_tam().x - 70.0, 80.0)

## Vuelve a colocar todo; se llama al empezar y cada vez que cambia el tamaño de la ventana.
func _recolocar_mesa() -> void:
	if not _modo_mesa_completa():
		return
	for peer in etiquetas_jugador:
		etiquetas_jugador[peer].position = _pos_etiqueta(_posicion_relativa(peer))
	for peer in dorsos:
		_dibujar_dorsos(peer)
	_colocar_pinta()
	for carta in cartas_otros_en_mesa:
		carta.pos_base = _pos_carta_baza(carta.get_meta("relativa"))
		carta.position = carta.pos_base
	if carta_en_mesa:
		carta_en_mesa.pos_base = global_position + _pos_carta_baza(0) - carta_en_mesa.get_parent().global_position
		carta_en_mesa.position = carta_en_mesa.pos_base
	boton_cantar.position = Vector2(_tam().x / 2.0 + 350.0, _tam().y - 180.0)
	reorganizar_mano()

# --- Piezas de la mesa de 4 ---

func _crear_fondo() -> void:
	var fondo := TextureRect.new()
	fondo.name = "Fondo"
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fondo.texture = load(RUTA_FONDO) if ResourceLoader.exists(RUTA_FONDO) else _tapete_provisional()
	add_child(fondo)
	move_child(fondo, 0)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Tapete verde con viñeta, para cuando no hay imagen de fondo.
func _tapete_provisional() -> Texture2D:
	var degradado := Gradient.new()
	degradado.set_color(0, Color(0.16, 0.48, 0.26))
	degradado.set_color(1, Color(0.03, 0.16, 0.08))
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(1.1, 1.1)
	textura.width = 512
	textura.height = 288
	return textura

func _crear_etiqueta_jugador(peer_id: int) -> void:
	if etiquetas_jugador.has(peer_id):
		etiquetas_jugador[peer_id].queue_free()
	var color: Color = COLOR_PAREJA[asientos.find(peer_id) % 2]
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color.darkened(0.65), 0.85)
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var activo := normal.duplicate() as StyleBoxFlat
	activo.bg_color = Color(color.darkened(0.25), 0.95)
	activo.border_color = COLOR_TURNO
	activo.set_border_width_all(4)
	activo.shadow_color = Color(COLOR_TURNO, 0.7)
	activo.shadow_size = 6
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", normal)
	panel.set_meta("normal", normal)
	panel.set_meta("activo", activo)
	var texto := _crear_texto(22)
	texto.text = _abreviatura(peer_id)
	panel.add_child(texto)
	add_child(panel)
	etiquetas_jugador[peer_id] = panel

## Resalta la etiqueta de quien juega (borde dorado que late). -1 = nadie.
func _marcar_turno(peer_id_activo: int) -> void:
	if _tween_turno:
		_tween_turno.kill()
	for peer in etiquetas_jugador:
		var panel: PanelContainer = etiquetas_jugador[peer]
		panel.add_theme_stylebox_override("panel", panel.get_meta("activo" if peer == peer_id_activo else "normal"))
	if etiquetas_jugador.has(peer_id_activo):
		var activo: StyleBoxFlat = etiquetas_jugador[peer_id_activo].get_meta("activo")
		_tween_turno = create_tween().set_loops()
		_tween_turno.tween_property(activo, "shadow_size", 16, 0.5)
		_tween_turno.tween_property(activo, "shadow_size", 4, 0.5)

## Pinta boca abajo las cartas que le quedan a otro jugador, en su lado de la mesa.
func _dibujar_dorsos(peer_id: int) -> void:
	var relativa := _posicion_relativa(peer_id)
	var grupo: Node2D = dorsos.get(peer_id)
	if grupo == null:
		grupo = Node2D.new()
		add_child(grupo)
		dorsos[peer_id] = grupo
	for hijo in grupo.get_children():
		hijo.queue_free()
	grupo.position = _pos_dorsos(relativa)
	grupo.rotation_degrees = 180.0 if relativa == 2 else 90.0
	var cuantas: int = restantes.get(peer_id, 0)
	for i in cuantas:
		var dorso := Sprite2D.new()
		dorso.texture = _textura_dorso
		dorso.scale = Vector2.ONE * ESCALA_DORSO
		dorso.position = Vector2((i - (cuantas - 1) / 2.0) * SEPARACION_DORSOS, 0)
		grupo.add_child(dorso)

func _colocar_pinta() -> void:
	if cartas_en_mazo.is_empty():
		return
	var pinta = cartas_en_mazo[0]
	pinta.rot_base = 0.0
	pinta.pos_base = global_position + _pos_pinta() - nodo_mazo.global_position
	pinta.position = pinta.pos_base
	pinta.rotation_degrees = 0.0
	pinta.scale = Vector2.ONE * ESCALA_PINTA

func _colocar_carta_de_otro(peer_id_jugador: int, id_carta: String) -> void:
	var relativa := _posicion_relativa(peer_id_jugador)
	var nueva_carta = ESCENA_CARTA.instantiate()
	nueva_carta.escala_base = ESCALA_MESA_4
	nueva_carta.pos_base = _pos_carta_baza(relativa)
	nueva_carta.rot_base = 0.0
	nueva_carta.set_meta("relativa", relativa)
	add_child(nueva_carta)
	nueva_carta.inicializar(id_carta)
	if nueva_carta.tween_actual:
		nueva_carta.tween_actual.kill()
	nueva_carta.position = nueva_carta.pos_base
	nueva_carta.rotation_degrees = 0.0
	nueva_carta.scale = Vector2.ONE * ESCALA_MESA_4
	nueva_carta.bloqueada = true
	nueva_carta.current_state = CartaEscene.State.IDLE
	nueva_carta.z_index = 1
	cartas_otros_en_mesa.append(nueva_carta)

func _jugar_solo(ids: Array) -> void:
	await get_tree().create_timer(0.15).timeout
	if carta_en_mesa != null:
		return
	for carta in cartas_en_mano:
		if ids.has(carta.id):
			_jugar_carta_en_mesa(carta)
			return

func _crear_texto(tam_fuente: int) -> Label:
	var etiqueta := Label.new()
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ajustes := LabelSettings.new()
	ajustes.font_size = tam_fuente
	ajustes.outline_size = 6
	ajustes.outline_color = Color.BLACK
	etiqueta.label_settings = ajustes
	return etiqueta

# --- Depuración: consola y panel oculto (F3, solo en builds de depuración) ---

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TECLA_DEPURACION:
		var panel := _obtener_panel_depuracion()
		panel.visible = not panel.visible
		_refrescar_depuracion()

func _obtener_panel_depuracion() -> PanelContainer:
	if _panel_depuracion == null:
		_panel_depuracion = PanelContainer.new()
		_panel_depuracion.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.8)
		estilo.set_content_margin_all(10)
		_panel_depuracion.add_theme_stylebox_override("panel", estilo)
		_panel_depuracion.position = Vector2(10, 60)
		_texto_depuracion = Label.new()
		_texto_depuracion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_texto_depuracion.custom_minimum_size = Vector2(560, 0)
		_panel_depuracion.add_child(_texto_depuracion)
		_panel_depuracion.z_index = 200
		_panel_depuracion.visible = false
		add_child(_panel_depuracion)
	return _panel_depuracion

func _refrescar_depuracion() -> void:
	if _panel_depuracion == null or not _panel_depuracion.visible:
		return
	_texto_depuracion.text = "DEPURACIÓN (F3)\n%s\n%s\n--- últimos avisos ---\n%s" % [
		_info_partida, _marcador, "\n".join(_registro)]

func _depurar(texto: String) -> void:
	print("[MESA ", multiplayer.get_unique_id(), "] ", texto)
	_registro.append(texto)
	if _registro.size() > LINEAS_DEPURACION:
		_registro.remove_at(0)
	_refrescar_depuracion()

# --- Utilidades ---

## El nodo que lleva la partida (Juego_Guinote, Juego_Tute...), hermano de la mesa.
func _controlador() -> Node:
	for hermano in get_parent().get_children():
		if hermano is Controlador_juego_Base:
			return hermano
	return get_node("../juego_guiñote")

func _modo_mesa_completa() -> bool:
	return asientos.size() > 2

func _mi_asiento() -> int:
	return asientos.find(multiplayer.get_unique_id())

func _posicion_relativa(peer_id: int) -> int:
	return (asientos.find(peer_id) - _mi_asiento() + asientos.size()) % asientos.size()

## "Jugador 3" -> "J3".
func _abreviatura(peer_id: int) -> String:
	var nombre: String = nombres_por_peer.get(peer_id, "?")
	return "J" + nombre.get_slice(" ", nombre.get_slice_count(" ") - 1)

func _palo_de(id_carta: String) -> String:
	var partes := id_carta.split("_")
	return partes[1] if partes.size() > 1 else "?"

func _nombre_carta(id_carta: String) -> String:
	return id_carta.replace("_", " de ")
