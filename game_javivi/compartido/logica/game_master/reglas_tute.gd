class_name ReglasTute
extends RefCounted
## Reglas del Tute por parejas para 4 jugadores (§10 del análisis funcional del
## repositorio del equipo). Funciones puras: reciben cartas y devuelven
## resultados, sin red ni nodos, para poder probarlas con GUT.
##
## Asientos: 0..3 en el orden en que se juega. Parejas 0-2 contra 1-3.
##
## ⚠️ En el Tute el Caballo va por encima de la Sota y vale 3 frente a 2, al
## revés que en el Guiñote. No reutilizar las tablas de Juego_Guinote.

const JUGADORES := 4
const CARTAS_POR_JUGADOR := 10
const SOTA := 10
const CABALLO := 11
const REY := 12
## Fuerza de cada valor, de mayor a menor: As, Tres, Rey, Caballo, Sota, 7, 6, 5, 4, 2.
const RANGO := {1: 10, 3: 9, 12: 8, 11: 7, 10: 6, 7: 5, 6: 4, 5: 3, 4: 2, 2: 1}
## Tantos de cada carta; las que no aparecen ("blancas") valen 0.
const PUNTOS := {1: 11, 3: 10, 12: 4, 11: 3, 10: 2}
const PUNTOS_ULTIMAS := 10
const PUNTOS_CUARENTA := 40
const PUNTOS_VEINTE := 20
## Figuras con las que se canta Tute (en el Guiñote son sotas o reyes).
const FIGURAS_TUTE := {"reyes": REY, "caballos": CABALLO}
const NOMBRE_PALO := ["oros", "copas", "espadas", "bastos"]
const NOMBRE_PAREJA := ["pareja A", "pareja B"]


static func rango(carta: Carta) -> int:
	return RANGO.get(carta.valor, 0)


static func puntos(carta: Carta) -> int:
	return PUNTOS.get(carta.valor, 0)


static func equipo(asiento: int) -> int:
	return asiento % 2


static func companero(asiento: int) -> int:
	return (asiento + 2) % JUGADORES


static func nombre_palo(palo: int) -> String:
	return NOMBRE_PALO[palo]


## "Caballo_oros" -> "Caballo de oros".
static func nombre_carta(carta: Carta) -> String:
	return carta.id.replace("_", " de ")


## Reparte la baraja de una en una empezando por la derecha del dador. La
## última carta es para el dador: es la que se vuelve como pinta y marca el
## triunfo. Devuelve manos[asiento].
static func repartir(baraja: Array, dador: int, jugadores := JUGADORES) -> Array:
	var manos: Array = []
	for i in jugadores:
		manos.append([])
	for i in baraja.size():
		manos[(dador + 1 + i) % jugadores].append(baraja[i])
	return manos


## Si [param nueva] le gana a [param actual], la carta que va ganando la baza.
static func supera(nueva: Carta, actual: Carta, triunfo: int) -> bool:
	if nueva.palo == actual.palo:
		return rango(nueva) > rango(actual)
	return nueva.palo == triunfo


## Posición dentro de [param baza] de la carta que gana: el triunfo más alto o,
## si no hay triunfo, la más alta del palo de salida.
static func indice_ganador(baza: Array, triunfo: int) -> int:
	var mejor := 0
	for i in range(1, baza.size()):
		if supera(baza[i], baza[mejor], triunfo):
			mejor = i
	return mejor


## Cartas de [param mano] que se pueden echar en la baza en curso. El arrastre
## es obligatorio desde la primera baza, en este orden:
## 1. Asistir al palo de salida y montar (superar a la que gana) si se puede.
##    Si la que gana es un triunfo de otro jugador, basta con asistir.
## 2. Sin palo de salida, fallar con triunfo; y si ya hay un triunfo jugado,
##    pisarlo (echar uno más alto) si se puede.
## 3. Si no se puede pisar, contrafallo: cualquier carta.
## 4. Sin palo de salida ni triunfo, cualquier carta.
static func cartas_permitidas(mano: Array, baza: Array, triunfo: int) -> Array:
	if baza.is_empty():
		return mano.duplicate()
	var salida: int = baza[0].palo
	var ganadora: Carta = baza[indice_ganador(baza, triunfo)]

	var del_palo: Array = mano.filter(func(c): return c.palo == salida)
	if not del_palo.is_empty():
		var montan: Array = del_palo.filter(func(c): return supera(c, ganadora, triunfo))
		return montan if not montan.is_empty() else del_palo

	var triunfos: Array = mano.filter(func(c): return c.palo == triunfo)
	if not triunfos.is_empty():
		var pisan: Array = triunfos.filter(func(c): return supera(c, ganadora, triunfo))
		if not pisan.is_empty():
			return pisan
		return mano.duplicate()

	return mano.duplicate()


## Por qué no se puede echar [param carta] ahora, o "" si se puede.
static func motivo_rechazo(mano: Array, baza: Array, triunfo: int, carta: Carta) -> String:
	if not mano.has(carta):
		return "No tienes esa carta."
	if cartas_permitidas(mano, baza, triunfo).has(carta):
		return ""
	var salida: int = baza[0].palo
	var ganadora: Carta = baza[indice_ganador(baza, triunfo)]
	if mano.any(func(c): return c.palo == salida):
		if carta.palo != salida:
			return "Tienes que asistir: echa una carta de %s." % nombre_palo(salida)
		return "Tienes que montar: echa una carta de %s más alta que el %s." % [
			nombre_palo(salida), nombre_carta(ganadora)]
	if ganadora.palo == triunfo:
		return "Tienes que pisar: echa un triunfo más alto que el %s." % nombre_carta(ganadora)
	return "No tienes %s: tienes que fallar con un triunfo (%s)." % [
		nombre_palo(salida), nombre_palo(triunfo)]


## "reyes" o "caballos" si [param mano] tiene las cuatro, o "".
static func tute_en_mano(mano: Array) -> String:
	for figura in FIGURAS_TUTE:
		var valor: int = FIGURAS_TUTE[figura]
		if mano.filter(func(c): return c.valor == valor).size() == 4:
			return figura
	return ""


## Palos en los que [param mano] tiene Rey y Caballo y que aún no se han
## cantado. El de triunfo (las cuarenta) va el primero.
static func palos_para_cantar(mano: Array, triunfo: int, cantados: Array) -> Array:
	var palos: Array = []
	for palo in NOMBRE_PALO.size():
		if cantados.has(palo):
			continue
		var tiene_rey := mano.any(func(c): return c.palo == palo and c.valor == REY)
		var tiene_caballo := mano.any(func(c): return c.palo == palo and c.valor == CABALLO)
		if tiene_rey and tiene_caballo:
			palos.append(palo)
	if palos.has(triunfo):
		palos.erase(triunfo)
		palos.push_front(triunfo)
	return palos


## Lo mejor que puede cantar [param mano] tras ganar su pareja una baza: el Tute
## (gana la partida), luego las cuarenta, luego las veinte. {} si nada.
## Cada jugador canta un solo acuse por baza ganada.
static func mejor_cante(mano: Array, triunfo: int, cantados: Array) -> Dictionary:
	var figura := tute_en_mano(mano)
	if figura != "":
		return {"tipo": "tute", "figura": figura}
	var palos := palos_para_cantar(mano, triunfo, cantados)
	if palos.is_empty():
		return {}
	var palo: int = palos[0]
	return {
		"tipo": "cante",
		"palo": palo,
		"puntos": PUNTOS_CUARENTA if palo == triunfo else PUNTOS_VEINTE,
	}


## Texto del botón para [param opcion] (lo que devuelve [method mejor_cante]).
static func texto_cante(opcion: Dictionary) -> String:
	if opcion["tipo"] == "tute":
		return "Cantar TUTE de %s" % opcion["figura"]
	if opcion["puntos"] == PUNTOS_CUARENTA:
		return "Cantar las 40 (%s)" % nombre_palo(opcion["palo"])
	return "Cantar las 20 en %s" % nombre_palo(opcion["palo"])


## Tanteo final por parejas: valor de las cartas ganadas + cantes + diez de
## últimas. Gana la pareja con más tantos; si empatan, la que hizo la última
## baza. [param cartas_por_asiento] y [param cantes_por_asiento] van por asiento.
static func tanteo(cartas_por_asiento: Array, cantes_por_asiento: Array, asiento_ultima: int) -> Dictionary:
	var cartas := [0, 0]
	var cantes := [0, 0]
	var ultimas := [0, 0]
	for asiento in cartas_por_asiento.size():
		for carta in cartas_por_asiento[asiento]:
			cartas[equipo(asiento)] += puntos(carta)
		cantes[equipo(asiento)] += cantes_por_asiento[asiento]
	ultimas[equipo(asiento_ultima)] = PUNTOS_ULTIMAS
	var total := [cartas[0] + cantes[0] + ultimas[0], cartas[1] + cantes[1] + ultimas[1]]
	var ganador := equipo(asiento_ultima)
	if total[0] != total[1]:
		ganador = 0 if total[0] > total[1] else 1
	return {"cartas": cartas, "cantes": cantes, "ultimas": ultimas, "total": total, "ganador": ganador}
