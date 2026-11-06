extends Control
## Mesa visual de Guiñote a 2 jugadores: abanico de mano con arrastre, zona de
## mesa, mazo y la carta central del rival. Puerto de game_javivi/compartido/
## Escenas/tapete/tapete.gd: a diferencia del original (RPCs de Godot hacia un
## controlador de juego local), aquí la única fuente de verdad es el
## `estado_partida` que manda el servidor de partida real — `actualizar(estado)`
## redibuja la mesa entera en cada `estado_actualizado` (la llama
## partida_guinote_2p.gd), así que una jugada rechazada por el servidor
## simplemente no cambia nada al redibujar, sin necesitar un mensaje aparte de
## "jugada rechazada" como tenía el original.

const ESCENA_CARTA := preload("res://client/ui/partida_guinote_2p/carta_guinote.tscn")

## Emitida al soltar sobre la mesa una carta que está en jugadas_validas.
signal jugar_carta_solicitada(carta_id: String)

@onready var nodo_mano: Control = %Mano
@onready var colision_mano: CollisionShape2D = %ColisionMano
@onready var nodo_mesa: Control = %Mesa
@onready var colision_mesa: CollisionShape2D = %ColisionMesa
@onready var nodo_mazo: Control = %Mazo
@onready var colision_mazo: CollisionShape2D = %ColisionMazo
@onready var nodo_centro_oponente: Control = %CentroOponente
@onready var etiqueta_turno: Label = %EtiquetaTurno

var cartas_en_mano: Array = []
var _cartas_sobre_area_mano: Array = []
var _cartas_sobre_area_mesa: Array = []
var _carta_en_mesa: Variant = null
var _carta_oponente_en_mesa: Variant = null
var _cartas_en_mazo: Array = []
## carta_id -> true para las jugadas de tipo jugar_carta de la última actualización.
var _ids_jugables: Dictionary = {}


## game_javivi tenía un lienzo de tamaño fijo (stretch_mode="canvas_items" en
## su project.godot), así que podía dar por buena la posición de las formas de
## colisión tal y como se guardaron en la escena. Aquí "Mano"/"Mesa"/"Mazo" son
## controles anclados y responsivos (ocupan todo el ancho/alto disponible), así
## que hay que recentrar esas formas según el tamaño real en cada actualización
## — no sirve hacerlo solo una vez en _ready(): en ese momento el motor de
## layout todavía no ha terminado de resolver los anchors (el tamaño del
## control es 0 o un valor provisional) y las formas se quedan mal colocadas
## para siempre.
func _centrar_zonas() -> void:
	colision_mano.position = nodo_mano.size / 2.0
	colision_mesa.position = nodo_mesa.size / 2.0
	colision_mazo.position = nodo_mazo.size / 2.0
	# El tamaño fijo original (160x120, heredado de game_javivi) deja un área de
	# soltado mucho más pequeña que la zona "Mesa" que se ve en pantalla —al ser
	# "Mesa" un control anclado y responsivo, su tamaño real varía con la
	# ventana—, así que cuesta atinar al soltar la carta. Usar el tamaño real
	# del control como área de colisión hace que toda la zona visible de la
	# mesa admita soltar la carta.
	colision_mesa.shape.size = nodo_mesa.size


func actualizar(estado: Dictionary, tu_posicion: int) -> void:
	_centrar_zonas()
	etiqueta_turno.text = "Tu turno" if estado.get("turno", -1) == tu_posicion else "Turno del rival"
	_ids_jugables.clear()
	for jugada: Dictionary in estado.get("jugadas_validas", []):
		if jugada.get("tipo") == MensajesRed.JUGAR_CARTA:
			_ids_jugables[jugada.get("carta_id")] = true
	_actualizar_mano(estado.get("mi_mano", []))
	_actualizar_mesa(estado.get("baza_actual", []), tu_posicion)
	_actualizar_mazo(estado.get("cartas_en_mazo", 0), estado.get("pinta"))


func _actualizar_mano(mi_mano: Array) -> void:
	for carta: Variant in cartas_en_mano:
		carta.queue_free()
	cartas_en_mano.clear()
	_cartas_sobre_area_mano.clear()
	_cartas_sobre_area_mesa.clear()
	for id: String in mi_mano:
		var carta := ESCENA_CARTA.instantiate()
		nodo_mano.add_child(carta)
		carta.inicializar(id)
		carta.bloqueada = not _ids_jugables.has(id)
		carta.carta_soltada.connect(_on_carta_soltada)
		# _actualizar_mano() recrea toda la mano en cada estado_actualizado (más
		# simple que diferenciar qué carta es nueva); sin este fundido aparecían
		# todas de golpe en cada turno, incluidas las que ya estaban en la mano.
		carta.modulate.a = 0.0
		create_tween().tween_property(carta, "modulate:a", 1.0, 0.25)
		cartas_en_mano.append(carta)
	reorganizar_mano()


## Pinta la carta propia (en la mesa) y la del rival (en su centro) que haya
## en la baza en curso; a 2 jugadores nunca hay más de una de cada a la vez.
func _actualizar_mesa(baza_actual: Array, tu_posicion: int) -> void:
	if _carta_en_mesa:
		_carta_en_mesa.queue_free()
		_carta_en_mesa = null
	if _carta_oponente_en_mesa:
		_carta_oponente_en_mesa.queue_free()
		_carta_oponente_en_mesa = null
	for jugada: Dictionary in baza_actual:
		var es_mia: bool = jugada.get("jugador_id") == tu_posicion
		var carta := ESCENA_CARTA.instantiate()
		var padre: Control = nodo_mesa if es_mia else nodo_centro_oponente
		padre.add_child(carta)
		carta.inicializar(jugada.get("carta_id", ""))
		carta.bloqueada = true
		var centro_local: Vector2 = colision_mesa.global_position - padre.global_position if es_mia \
			else Vector2.ZERO
		carta.pos_base = centro_local
		carta.position = centro_local
		carta.rot_base = 0.0
		if carta.tween_actual:
			carta.tween_actual.kill()
		# Pequeño "golpe" al caer la carta sobre la mesa en vez de aparecer de
		# golpe a tamaño completo, para que se note que se acaba de jugar.
		carta.modulate.a = 0.0
		carta.scale = Vector2(0.85, 0.85)
		var tween_entrada := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween_entrada.tween_property(carta, "scale", Vector2.ONE, 0.2)
		tween_entrada.parallel().tween_property(carta, "modulate:a", 1.0, 0.15)
		if es_mia:
			_carta_en_mesa = carta
		else:
			_carta_oponente_en_mesa = carta


func _actualizar_mazo(cantidad_cartas: int, id_pinta: Variant) -> void:
	for carta: Variant in _cartas_en_mazo:
		carta.queue_free()
	_cartas_en_mazo.clear()
	if cantidad_cartas <= 0:
		return
	var centro_mazo_local: Vector2 = colision_mazo.global_position - nodo_mazo.global_position
	for i in cantidad_cartas:
		var carta := ESCENA_CARTA.instantiate()
		nodo_mazo.add_child(carta)
		if i == 0 and id_pinta != null:
			carta.inicializar(id_pinta)
			carta.rot_base = 90.0
			carta.pos_base = centro_mazo_local + Vector2(50, 0)
		else:
			carta.inicializar("reverso")
			carta.rot_base = 0.0
			carta.pos_base = centro_mazo_local + Vector2(-i, -i)
		if carta.tween_actual:
			carta.tween_actual.kill()
		carta.position = carta.pos_base
		carta.rotation_degrees = carta.rot_base
		carta.scale = Vector2(0.72, 0.72)
		carta.z_index_base = i
		carta.z_index = i
		carta.bloqueada = true
		_cartas_en_mazo.append(carta)


func reorganizar_mano() -> void:
	var total := cartas_en_mano.size()
	if total == 0:
		return
	var ancho_total := 400.0
	var altura_curva := 40.0
	var rotacion_max := 15.0
	var centro_abanico: Vector2 = colision_mano.global_position - nodo_mano.global_position

	for i in total:
		var carta: Variant = cartas_en_mano[i]
		var t: float = 0.5 if total <= 1 else float(i) / float(total - 1)
		var pos_x: float = centro_abanico.x + lerpf(-ancho_total / 2.0, ancho_total / 2.0, t)
		var t_offset: float = (t - 0.5) * 2.0
		var pos_y: float = centro_abanico.y + (t_offset * t_offset) * altura_curva
		var rot: float = lerpf(-rotacion_max, rotacion_max, t)

		carta.z_index_base = i
		carta.pos_base = Vector2(pos_x, pos_y)
		carta.rot_base = rot
		if carta.current_state == carta.State.IDLE:
			# Una carta recién creada dispara en su _ready() un tween hacia el
			# pos_base que tuviera en ESE momento (Vector2.ZERO, el valor por
			# defecto, porque to llega más tarde con el pos_base real de más
			# arriba): sin matarlo aquí, ese tween viejo sigue corriendo y
			# devuelve la carta a (0,0) unos frames después de fijar la
			# posición correcta.
			if carta.tween_actual:
				carta.tween_actual.kill()
			carta.z_index = i
			carta.position = carta.pos_base
			carta.rotation_degrees = carta.rot_base


func _on_carta_soltada(carta_soltada: Variant) -> void:
	if _cartas_sobre_area_mesa.has(carta_soltada):
		if _carta_en_mesa == null and not carta_soltada.bloqueada:
			# Al jugarla queda fuera de cartas_en_mano, así que _actualizar_mano()
			# ya no la recorre para liberarla cuando llegue el siguiente estado
			# (mi_mano sin esta carta): sin este queue_free() se queda huérfana,
			# visible sobre la mano y sin poder usarse (bug reportado en #34).
			carta_soltada.queue_free()
			cartas_en_mano.erase(carta_soltada)
			jugar_carta_solicitada.emit(carta_soltada.id)
		reorganizar_mano()
	elif _cartas_sobre_area_mano.has(carta_soltada):
		if not cartas_en_mano.has(carta_soltada):
			cartas_en_mano.append(carta_soltada)
		var nuevo_indice := 0
		for otra: Variant in cartas_en_mano:
			if otra != carta_soltada and carta_soltada.global_position.x > otra.global_position.x:
				nuevo_indice += 1
		cartas_en_mano.erase(carta_soltada)
		cartas_en_mano.insert(nuevo_indice, carta_soltada)
		reorganizar_mano()
	else:
		reorganizar_mano()


func _on_area_mano_area_entered(area: Area2D) -> void:
	var carta := area.get_parent()
	if not _cartas_sobre_area_mano.has(carta):
		_cartas_sobre_area_mano.append(carta)


func _on_area_mano_area_exited(area: Area2D) -> void:
	var carta := area.get_parent()
	_cartas_sobre_area_mano.erase(carta)


func _on_area_mesa_area_entered(area: Area2D) -> void:
	var carta := area.get_parent()
	if not _cartas_sobre_area_mesa.has(carta):
		_cartas_sobre_area_mesa.append(carta)


func _on_area_mesa_area_exited(area: Area2D) -> void:
	var carta := area.get_parent()
	_cartas_sobre_area_mesa.erase(carta)
