extends RefCounted
## Cuándo suena cada cosa en la mesa (PBI-21): se compara el estado que había
## en la mesa con el que se va a enseñar y se dice qué sonidos tocan. Solo
## funciones estáticas, sin escena, para poder probarlas con estados a mano
## (tests/unit/client/test_sonidos_mesa.gd). Las usa partida_mesa.gd, que es
## quien los hace sonar con el autoload Sonidos.

const Sonido := preload("res://client/autoload/sonidos.gd")

## Jugadas que se ofrecen aunque no te toque (las 20 o las 40 tras ganar la
## baza, el cambio del siete, el capote...): con ellas solas no se avisa.
const JUGADAS_OPCIONALES := [
	MensajesRed.CANTAR, MensajesRed.CANTAR_TUTE, MensajesRed.CAMBIAR_SIETE, MensajesRed.CAPOTE,
]

## Jugadas tuyas tras las que, si te sigue tocando, es el mismo turno y no uno
## nuevo: las opcionales y decidir no cambiar el siete (se decide antes de echar
## carta, sin que la partida pase a otro).
const JUGADAS_SIN_TURNO_NUEVO := JUGADAS_OPCIONALES + [MensajesRed.NO_CAMBIAR_SIETE]


## [param anterior] y [param estado]: vistas de estado_partida ({} si no había).
## Devuelve la lista de nombres de Sonidos, en el orden en que pasan las cosas:
## la carta que cae en la mesa, las que llegan a tu mano y el aviso de turno.
static func sonidos_entre(anterior: Dictionary, estado: Dictionary, mi_asiento: int) -> Array[String]:
	var sonidos: Array[String] = []
	if estado.is_empty():
		return sonidos
	var jugada := jugada_nueva(anterior, estado)
	if jugada.get("tipo") == MensajesRed.JUGAR_CARTA:
		sonidos.append(Sonido.CARTA)
	var nuevas := cartas_nuevas(anterior, estado)
	# Al entrar a mitad de partida (reconexión) la mano ya estaba repartida: el
	# servidor solo deja ultima_jugada vacía hasta la primera jugada, así que con
	# ella rellena no es un reparto ni un robo, como con la carta en jugada_nueva.
	if anterior.is_empty() and not (estado.get("ultima_jugada", {}) as Dictionary).is_empty():
		nuevas = 0
	# Varias de golpe es un reparto (inicio, vuelta, mano nueva, reposición del
	# Mus); una sola, un robo (tras la baza o al cambiar el siete).
	if nuevas >= 2:
		sonidos.append(Sonido.REPARTIR)
	elif nuevas == 1:
		sonidos.append(Sonido.ROBAR)
	# Turno nuevo: antes no te tocaba, o acabas de jugar tú y te vuelve a tocar
	# (cierras la baza, la ganas y sales; en el Mus, la mano contesta un envite
	# y abre el lance siguiente). Seguías esperado en los dos estados, pero tras
	# la pausa de la baza o de la mano hay que avisar igual.
	var repites: bool = int(jugada.get("jugador_id", -1)) == mi_asiento \
		and not JUGADAS_SIN_TURNO_NUEVO.has(jugada.get("tipo", ""))
	if me_toca(estado, mi_asiento) and (repites or not me_toca(anterior, mi_asiento)):
		sonidos.append(Sonido.TURNO)
	return sonidos


## Si en [param estado] se espera algo de [param mi_asiento]. Con tiempo límite
## lo dice [code]tiempos_para_decidir[/code] (una entrada por cada jugador
## esperado). Sin él (desactivado en el servidor) no viene o viene vacío, y
## entonces te toca si puedes hacer algo que no sea opcional.
static func me_toca(estado: Dictionary, mi_asiento: int) -> bool:
	if estado.is_empty() or mi_asiento < 0:
		return false
	var tiempos: Variant = estado.get("tiempos_para_decidir", [])
	if tiempos is Array and not (tiempos as Array).is_empty():
		for tiempo: Variant in tiempos:
			if tiempo is Dictionary and int(tiempo.get("posicion", -1)) == mi_asiento:
				return true
		return false
	for jugada: Variant in estado.get("jugadas_validas", []):
		if jugada is Dictionary and not JUGADAS_OPCIONALES.has(jugada.get("tipo", "")):
			return true
	return false


## La [code]ultima_jugada[/code] de [param estado] si es nueva respecto a
## [param anterior] (otro [code]numero[/code]); si no, {}. Como en la mesa, al
## entrar (sin estado anterior) no se cuenta lo que ya había pasado.
static func jugada_nueva(anterior: Dictionary, estado: Dictionary) -> Dictionary:
	var jugada: Variant = estado.get("ultima_jugada", {})
	if anterior.is_empty() or not jugada is Dictionary or (jugada as Dictionary).is_empty():
		return {}
	var antes: Variant = anterior.get("ultima_jugada", {})
	var numero_antes: Variant = antes.get("numero") if antes is Dictionary else null
	return {} if jugada.get("numero") == numero_antes else jugada


## Cuántas cartas de [code]mi_mano[/code] en [param estado] no estaban en [param anterior].
static func cartas_nuevas(anterior: Dictionary, estado: Dictionary) -> int:
	var antes: Array = anterior.get("mi_mano", [])
	var nuevas := 0
	for carta: Variant in estado.get("mi_mano", []):
		if not antes.has(carta):
			nuevas += 1
	return nuevas
