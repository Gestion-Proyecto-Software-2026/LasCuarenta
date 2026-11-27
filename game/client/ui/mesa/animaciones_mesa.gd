extends Node
## Animaciones de la mesa (PBI-22): las cartas vuelan del mazo a cada jugador al
## repartir y al robar, y la pinta y el siete se cruzan al cambiar el siete. La
## mesa (tapete_mesa.gd) lo crea y le pide los vuelos; aquí se lanzan, se lleva
## la cuenta de los que están en curso y se pueden saltar.
##
## Son solo visuales: nunca retrasan ni cambian lo que se envía al servidor, ni
## qué cartas hay en la mano o en la mesa. Las cartas de tu mano siguen siendo
## cartas normales mientras vuelan (se pueden pulsar y arrastrar: al cambiar de
## estado la carta para su vuelo), y con las animaciones desactivadas todo
## aparece directamente en su sitio. Con ellas o sin ellas, la mesa acaba igual.
##
## Cualquier clic o toque mientras hay algo volando lo termina al instante (todo
## en su sitio final), sin quedarse el evento: el mismo clic sirve también para
## lo que fuera, p. ej. coger la carta que estaba volando. Por eso es un Node y la
## mesa lo añade después de la mano: recibe el clic antes que las cartas.

## Lo que tarda cada carta en llegar a su sitio.
const DURACION_VUELO := 0.35
## Entre carta y carta de un reparto, como mucho; con muchas cartas, menos, para
## que el reparto entero dure menos de un segundo (ver [method escalonado]).
const ESCALONADO_MAXIMO := 0.05
## Lo que puede durar como mucho el escalonado de un reparto entero.
const ESCALONADO_TOTAL := 0.5
## Por encima de las cartas de la mesa y por debajo de los letreros.
const Z_FANTASMA := 110

## La mesa (tapete_mesa.gd) pone esto desde Ajustes.animaciones y lo cambia si
## el jugador las desactiva; si había algo volando, se salta.
var activadas := true:
	set(valor):
		activadas = valor
		if not valor:
			saltar()
## Cuántos vuelos se han lanzado (para comprobar en los tests que se animan).
var vuelos_lanzados := 0
## Lo que tarda la última tanda en llegar entera, de la primera carta a la última.
var duracion_ultima_tanda := 0.0

## Vuelos en curso: [Tween, nodo que vuela].
var _vuelos: Array = []
## Tanda abierta con [method empezar_tanda]: los vuelos que se piden mientras
## tanto esperan a [method lanzar_tanda], que reparte los retrasos entre todos.
var _tanda_abierta := false
## Cada vuelo de la tanda: { nodo, asiento, carta (si es de tu mano) y, los
## dorsos, destino }. Las cartas van a su pos_base, que se lee al lanzarlas.
var _tanda: Array[Dictionary] = []


## Entre carta y carta de un reparto de [param cartas] cartas: 0,05 s, o menos si
## son tantas que el reparto pasaría de [constant ESCALONADO_TOTAL].
static func escalonado(cartas: int) -> float:
	return minf(ESCALONADO_MAXIMO, ESCALONADO_TOTAL / maxf(1.0, cartas - 1))


## Lo que dura un reparto de [param cartas] cartas, de la primera que sale a la
## última que llega. Siempre menos de un segundo, aunque sean las 40 del Tute.
static func duracion_reparto(cartas: int) -> float:
	return DURACION_VUELO + escalonado(cartas) * maxi(0, cartas - 1)


func _input(event: InputEvent) -> void:
	# No se marca como atendido: el clic sigue sirviendo para lo que fuera.
	if es_pulsacion(event) and en_curso():
		pulsar_en(get_viewport().get_canvas_transform().affine_inverse() * (event as InputEventFromWindow).position)


## Un clic de verdad (izquierdo, derecho o central) o un toque. La rueda del
## ratón también llega como botón pulsado, pero mover la rueda (p. ej. sobre el
## chat) no es pulsar: no salta nada.
static func es_pulsacion(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.pressed \
		and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]


## Lo que pasa al pulsar en [param punto] (coordenadas globales del lienzo) con
## algo volando: todo salta a su sitio, salvo la carta de tu mano que esté bajo
## el puntero, que se para donde está. Así el mismo clic la coge justo ahí; si
## saltara a su hueco del abanico, se arrastraría lejos del cursor.
func pulsar_en(punto: Vector2) -> void:
	var pulsada := _carta_volando_en(punto)
	if pulsada:
		for vuelo: Array in _vuelos.filter(_sigue):
			if vuelo[1] == pulsada:
				(vuelo[0] as Tween).kill()
	saltar()


## La carta de tu mano que vuela y está bajo [param punto]; si se solapan
## varias, la de encima. null si no hay ninguna.
func _carta_volando_en(punto: Vector2) -> CartaMesa:
	var encima: CartaMesa = null
	for vuelo: Array in _vuelos.filter(_sigue):
		var carta := vuelo[1] as CartaMesa
		if carta == null or not carta.get_rect().has_point(carta.to_local(punto)):
			continue
		if encima == null or carta.z_index > encima.z_index \
				or (carta.z_index == encima.z_index and carta.get_index() > encima.get_index()):
			encima = carta
	return encima


## Si hay algo volando todavía.
func en_curso() -> bool:
	_vuelos = _vuelos.filter(_sigue)
	return not _vuelos.is_empty()


## Termina al instante todo lo que está volando: cada cosa en su sitio final y
## los fantasmas del cambio del siete, liberados.
func saltar() -> void:
	var vuelos := _vuelos.filter(_sigue)
	_vuelos.clear()
	for vuelo: Array in vuelos:
		(vuelo[0] as Tween).custom_step(99.0)


## A partir de aquí, los vuelos que se pidan salen juntos en [method lanzar_tanda],
## escalonados y repartidos por turnos entre los jugadores (como se reparte de
## verdad). La mesa abre una tanda por cada vista que pinta.
func empezar_tanda() -> void:
	_tanda_abierta = true
	_tanda.clear()


## Lanza los vuelos de la tanda. [param primero]: el asiento al que le llega la
## primera carta (el que es mano al repartir, el que gana la baza al robar).
func lanzar_tanda(primero: int, num_jugadores: int) -> void:
	_tanda_abierta = false
	var pendientes := _tanda.duplicate()
	_tanda.clear()
	if pendientes.is_empty():
		return
	var por_asiento := {}
	for vuelo: Dictionary in pendientes:
		if not por_asiento.has(vuelo["asiento"]):
			por_asiento[vuelo["asiento"]] = []
		por_asiento[vuelo["asiento"]].append(vuelo)
	# Los asientos en el orden en que reciben: desde [param primero] en adelante.
	var asientos: Array = por_asiento.keys()
	var n := maxi(1, num_jugadores)
	asientos.sort_custom(func(a: int, b: int) -> bool:
		return posmod(a - primero, n) < posmod(b - primero, n))
	var vueltas := 0
	for asiento in asientos:
		vueltas = maxi(vueltas, por_asiento[asiento].size())
	var paso := escalonado(vueltas * asientos.size())
	duracion_ultima_tanda = DURACION_VUELO + paso * (vueltas * asientos.size() - 1)
	for i in asientos.size():
		var suyos: Array = por_asiento[asientos[i]]
		for k in suyos.size():
			_lanzar(suyos[k], (k * asientos.size() + i) * paso)


## Una carta nueva de tu mano: está en el mazo y va a su hueco del abanico
## ([member CartaMesa.pos_base]). Devuelve su tween para que la carta lo guarde
## como [member CartaMesa.tween_abanico] y lo pare si la pulsan; dentro de una
## tanda devuelve null y la carta lo recibe al lanzarse la tanda.
func llevar_carta(carta: CartaMesa, asiento: int) -> Tween:
	var vuelo := {"nodo": carta, "asiento": asiento, "carta": true}
	if _tanda_abierta:
		for pendiente: Dictionary in _tanda:
			if pendiente["nodo"] == carta:
				return null
		_tanda.append(vuelo)
		return null
	return _lanzar(vuelo, 0.0)


## Un dorso nuevo de otro jugador, que ya está en el mazo, va a [param destino]
## (coordenadas de su grupo de dorsos).
func llevar_dorso(dorso: Node2D, asiento: int, destino: Vector2) -> void:
	var vuelo := {"nodo": dorso, "asiento": asiento, "destino": destino, "carta": false}
	if _tanda_abierta:
		_tanda.append(vuelo)
	else:
		_lanzar(vuelo, 0.0)


## Si [param nodo] está volando o esperando a salir en la tanda abierta. La mano
## lo usa para que una carta que aún está llegando, si se recoloca el abanico,
## siga siendo un vuelo (que se puede saltar) y no un movimiento normal.
func vuela(nodo: Node) -> bool:
	for pendiente: Dictionary in _tanda:
		if pendiente["nodo"] == nodo:
			return true
	for vuelo: Array in _vuelos:
		if _sigue(vuelo) and vuelo[1] == nodo:
			return true
	return false


## Una carta suelta (Sprite2D con [param textura]), hija de [param padre], que
## va de [param desde] a [param hasta] (coordenadas de [param padre]) y se libera
## al llegar o al saltar. Es lo que se ve del cambio del siete: el 7 que deja el
## jugador y la pinta que se lleva.
func lanzar_fantasma(padre: Node, textura: Texture2D, escala: float, desde: Vector2, hasta: Vector2,
		rotacion_desde := 0.0, rotacion_hasta := 0.0) -> Sprite2D:
	var fantasma := Sprite2D.new()
	fantasma.name = "Fantasma"
	fantasma.texture = textura
	fantasma.scale = Vector2.ONE * escala
	fantasma.position = desde
	fantasma.rotation_degrees = rotacion_desde
	fantasma.z_index = Z_FANTASMA
	# Con nombre legible ("Fantasma2"...): se cruzan dos a la vez.
	padre.add_child(fantasma, true)
	# El tween va unido al fantasma: si se cierra la mesa a mitad, se van juntos.
	var tween := fantasma.create_tween().set_parallel()
	tween.tween_property(fantasma, "position", hasta, DURACION_VUELO).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(fantasma, "rotation_degrees", rotacion_hasta, DURACION_VUELO)
	tween.chain().tween_callback(fantasma.queue_free)
	_registrar(tween, fantasma)
	return fantasma


func _lanzar(vuelo: Dictionary, retraso: float) -> Tween:
	var nodo: Node2D = vuelo["nodo"]
	if not is_instance_valid(nodo) or nodo.is_queued_for_deletion():
		return null
	var carta: CartaMesa = nodo as CartaMesa if vuelo["carta"] else null
	var destino: Vector2 = carta.pos_base if carta else vuelo["destino"]
	# El tween va unido a lo que vuela: si se quita de la mesa, se para con él.
	var tween := nodo.create_tween()
	if retraso > 0.0:
		tween.tween_interval(retraso)
	tween.tween_property(nodo, "position", destino, DURACION_VUELO).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if carta:
		tween.parallel().tween_property(carta, "rotation_degrees", carta.rot_base, DURACION_VUELO) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		carta.tween_abanico = tween
	_registrar(tween, nodo)
	return tween


func _registrar(tween: Tween, nodo: Node) -> void:
	# De paso se olvidan los que ya acabaron, para que la lista no crezca en toda la partida.
	_vuelos = _vuelos.filter(_sigue)
	_vuelos.append([tween, nodo])
	vuelos_lanzados += 1


## Un vuelo sigue mientras su tween no ha acabado ni lo han parado (p. ej. al
## pulsar la carta) y lo que vuela sigue en la mesa.
func _sigue(vuelo: Array) -> bool:
	# Antes que nada: un fantasma ya liberado no se puede ni asignar a una variable.
	if not is_instance_valid(vuelo[1]):
		return false
	var tween: Tween = vuelo[0]
	var nodo: Node = vuelo[1]
	return tween.is_valid() and tween.is_running() and nodo.is_inside_tree() and not nodo.is_queued_for_deletion()
