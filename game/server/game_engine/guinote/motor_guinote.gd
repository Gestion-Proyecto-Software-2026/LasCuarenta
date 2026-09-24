class_name MotorGuinote
extends MotorDeJuego
## Motor de reglas del Guiñote (analisis_funcional_app.md §8).
##
## Implementado: reparto, triunfo, las 4 bazas "con robada" (juego libre), el
## robo tras cada baza, las 6 bazas de arrastre con sus obligaciones, los
## cantes (20 y las 40) y el Tute. Pendiente: cambio del siete y tanteo
## completo con vueltas (pbi-03-tanteo-y-fin-partida). Hasta entonces no se
## registra en MOTORES de main_server.gd.

const NUM_JUGADORES := 4
const CARTAS_POR_TANDA := 3
const TANDAS_DE_REPARTO := 2

## Orden de fuerza, de mayor a menor: As, Tres, Rey, Sota, Caballo, 7, 6, 5, 4, 2.
## ⚠️ En Guiñote la Sota va por encima del Caballo, al revés que en el Tute.
const ORDEN_DE_FUERZA: Array[int] = [1, 3, 12, 10, 11, 7, 6, 5, 4, 2]
## Valor en tantos de cada carta; las que no aparecen valen 0.
const PUNTOS := {1: 11, 3: 10, 12: 4, 10: 3, 11: 2}
const PUNTOS_ULTIMA_BAZA := 10
const PUNTOS_CANTE_TRIUNFO := 40
const PUNTOS_CANTE := 20
const SOTA := 10
const REY := 12
## Figuras con las que se canta Tute en Guiñote (en el Tute son caballos o reyes).
const FIGURAS_TUTE := {"sotas": SOTA, "reyes": REY}


func jugadores_admitidos() -> Array[int]:
	return [NUM_JUGADORES]


## Sortea el dador, baraja, reparte 6 cartas a cada uno en dos tandas de 3
## (empezando por la derecha del dador) y vuelve la siguiente como pinta.
## No hay corte: con la baraja ya mezclada al azar no cambia nada.
func _iniciar(_num_jugadores: int) -> EstadoPartida:
	var estado := EstadoGuinote.new()
	estado.dador = rng.randi_range(0, NUM_JUGADORES - 1)
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)

	for jugador in NUM_JUGADORES:
		estado.manos.append([] as Array[Carta])
	for tanda in TANDAS_DE_REPARTO:
		for i in NUM_JUGADORES:
			var jugador := (estado.dador + 1 + i) % NUM_JUGADORES
			for c in CARTAS_POR_TANDA:
				estado.manos[jugador].append(cartas.pop_front())

	estado.pinta = cartas.pop_front()
	estado.palo_triunfo = estado.pinta.palo
	estado.mazo = cartas
	estado.turno = (estado.dador + 1) % NUM_JUGADORES
	return estado


func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	var e := estado as EstadoGuinote
	var validas: Array[Dictionary] = []
	if ha_terminado(e):
		return validas
	if jugador_id == e.turno:
		var permitidas: Array = e.manos[jugador_id]
		if e.fase == EstadoGuinote.Fase.ARRASTRE:
			permitidas = cartas_permitidas_en_arrastre(e.manos[jugador_id], e.baza_actual, e.palo_triunfo, jugador_id)
		# En la fase de robo, cualquier carta de la mano, sin obligación de asistir.
		for carta: Carta in permitidas:
			validas.append({"tipo": MensajesRed.JUGAR_CARTA, "carta_id": carta.id})
	# Cantar no depende del turno: puede hacerlo cualquiera de la pareja que ganó la baza.
	validas.append_array(_cantes_posibles(e, jugador_id))
	return validas


## Cantes que puede hacer [param jugador_id] ahora mismo. Hace falta que su
## pareja haya ganado la última baza y que ningún rival haya jugado todavía en
## la baza siguiente (§8).
func _cantes_posibles(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	var cantes: Array[Dictionary] = []
	if not ventana_de_cante_abierta(e, jugador_id):
		return cantes
	var mano: Array = e.manos[jugador_id]
	if e.ultimo_cante_de[jugador_id] != e.bazas_jugadas:
		var cantados := e.cantes.map(func(c: Dictionary) -> Carta.Palo: return c["palo"])
		for palo: Carta.Palo in Carta.Palo.values():
			if palo not in cantados and _tiene(mano, palo, SOTA) and _tiene(mano, palo, REY):
				cantes.append({"tipo": MensajesRed.CANTAR, "palo": nombre_palo(palo)})
	for figura: String in FIGURAS_TUTE:
		if mano.filter(func(c: Carta) -> bool: return c.valor == FIGURAS_TUTE[figura]).size() == 4:
			cantes.append({"tipo": MensajesRed.CANTAR_TUTE, "figura": figura})
	return cantes


## Si [param jugador_id] está en el momento de poder cantar: su pareja acaba de
## ganar la última baza y en la baza en curso solo ha jugado, como mucho, su
## propia pareja (quien ganó sale primero; en cuanto juega un rival, se cierra).
static func ventana_de_cante_abierta(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.ultima_baza.is_empty() or equipo_de(e.ultima_baza["ganador"]) != equipo_de(jugador_id):
		return false
	return e.baza_actual.all(func(j: Dictionary) -> bool:
		return equipo_de(j["jugador_id"]) == equipo_de(jugador_id))


static func _tiene(mano: Array, palo: Carta.Palo, valor: int) -> bool:
	return mano.any(func(c: Carta) -> bool: return c.palo == palo and c.valor == valor)


static func nombre_palo(palo: Carta.Palo) -> String:
	return (Carta.Palo.keys()[palo] as String).to_lower()


## Cartas de [param mano] que [param jugador_id] puede jugar en una baza de
## arrastre, según las obligaciones de §8, en este orden:
## 1. Asistir al palo de salida y, si puede, montar (superar la más alta de
##    ese palo ya jugada, la haya echado quien la haya echado).
## 2. Si no tiene el palo de salida, fallar (jugar triunfo) si tiene triunfo:
##    con cualquiera si ningún rival ha fallado, o con uno que supere al triunfo
##    más alto de los rivales. Si no puede superarlo, juega libremente.
## 3. Si el palo de salida no es triunfo y alguien ya ha fallado, basta con
##    asistir, sin montar.
## 4. En cualquier otro caso, juega libremente. Quien abre la baza, también.
static func cartas_permitidas_en_arrastre(mano: Array, baza: Array[Dictionary],
		palo_triunfo: Carta.Palo, jugador_id: int) -> Array:
	if baza.is_empty():
		return mano
	var palo_salida: Carta.Palo = baza[0]["carta"].palo

	var del_palo := mano.filter(func(c: Carta) -> bool: return c.palo == palo_salida)
	if not del_palo.is_empty():
		var alguien_ha_fallado := palo_salida != palo_triunfo \
			and baza.any(func(j: Dictionary) -> bool: return j["carta"].palo == palo_triunfo)
		if alguien_ha_fallado:
			return del_palo
		var mas_alta := _mas_alta(baza, func(j: Dictionary) -> bool: return j["carta"].palo == palo_salida)
		return _las_que_superan(del_palo, mas_alta, del_palo)

	var triunfos := mano.filter(func(c: Carta) -> bool: return c.palo == palo_triunfo)
	if triunfos.is_empty():
		return mano
	var triunfo_rival := _mas_alta(baza, func(j: Dictionary) -> bool:
		return j["carta"].palo == palo_triunfo and equipo_de(j["jugador_id"]) != equipo_de(jugador_id))
	if triunfo_rival == null:
		return triunfos
	return _las_que_superan(triunfos, triunfo_rival, mano)


## La carta más fuerte de las jugadas de [param baza] que cumplen [param filtro],
## o null si ninguna lo cumple. Todas las que cumplen el filtro son del mismo palo.
static func _mas_alta(baza: Array[Dictionary], filtro: Callable) -> Carta:
	var mejor: Carta = null
	for jugada: Dictionary in baza.filter(filtro):
		if mejor == null or fuerza(jugada["carta"]) > fuerza(mejor):
			mejor = jugada["carta"]
	return mejor


## Las cartas de [param candidatas] que superan a [param rival]; si ninguna la
## supera, [param si_ninguna].
static func _las_que_superan(candidatas: Array, rival: Carta, si_ninguna: Array) -> Array:
	var superan := candidatas.filter(func(c: Carta) -> bool: return fuerza(c) > fuerza(rival))
	return superan if not superan.is_empty() else si_ninguna


func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	var e := estado as EstadoGuinote
	match jugada["tipo"]:
		MensajesRed.CANTAR:
			var palo := Carta.Palo.keys().find((jugada["palo"] as String).to_upper()) as Carta.Palo
			var puntos := PUNTOS_CANTE_TRIUNFO if palo == e.palo_triunfo else PUNTOS_CANTE
			e.cantes.append({"jugador_id": jugador_id, "palo": palo, "puntos": puntos})
			e.ultimo_cante_de[jugador_id] = e.bazas_jugadas
		MensajesRed.CANTAR_TUTE:
			e.tute = {"jugador_id": jugador_id, "figura": jugada["figura"]}
		MensajesRed.JUGAR_CARTA:
			_jugar_carta(e, jugador_id, jugada["carta_id"])


func _jugar_carta(e: EstadoGuinote, jugador_id: int, carta_id: String) -> void:
	var mano: Array = e.manos[jugador_id]
	var carta: Carta = null
	for i in mano.size():
		if mano[i].id == carta_id:
			carta = mano[i]
			mano.remove_at(i)
			break
	e.baza_actual.append({"jugador_id": jugador_id, "carta": carta})

	if e.baza_actual.size() < NUM_JUGADORES:
		e.turno = (e.turno + 1) % NUM_JUGADORES
		return
	_cerrar_baza(e)


func _cerrar_baza(e: EstadoGuinote) -> void:
	var ganador := ganador_de_baza(e.baza_actual, e.palo_triunfo)
	for jugada: Dictionary in e.baza_actual:
		e.cartas_ganadas[equipo_de(ganador)].append(jugada["carta"])
	e.ultima_baza = {"ganador": ganador, "cartas": e.baza_actual.duplicate()}
	e.baza_actual.clear()
	e.bazas_jugadas += 1
	e.turno = ganador  # quien gana la baza sale en la siguiente

	if e.fase == EstadoGuinote.Fase.ROBO:
		_robar(e, ganador)
		if e.bazas_jugadas == EstadoGuinote.BAZAS_CON_ROBO:
			e.fase = EstadoGuinote.Fase.ARRASTRE


## Cada jugador roba una carta, empezando por el ganador de la baza y en el
## sentido del juego. La pinta se roba la última.
func _robar(e: EstadoGuinote, ganador: int) -> void:
	for i in NUM_JUGADORES:
		var jugador := (ganador + i) % NUM_JUGADORES
		if not e.mazo.is_empty():
			e.manos[jugador].append(e.mazo.pop_front())
		elif e.pinta != null:
			e.manos[jugador].append(e.pinta)
			e.pinta = null


## Quién gana una baza: el triunfo más alto; si nadie jugó triunfo, la carta más
## alta del palo de salida (las de los otros palos no cuentan).
## [param baza] es [code][{ "jugador_id", "carta" }][/code] en orden de juego.
static func ganador_de_baza(baza: Array[Dictionary], palo_triunfo: Carta.Palo) -> int:
	var mejor: Dictionary = baza[0]
	for jugada: Dictionary in baza.slice(1):
		if gana_a(jugada["carta"], mejor["carta"], palo_triunfo):
			mejor = jugada
	return mejor["jugador_id"]


## Si [param retadora], jugada después, supera a [param mejor] (la que va
## ganando la baza).
static func gana_a(retadora: Carta, mejor: Carta, palo_triunfo: Carta.Palo) -> bool:
	if retadora.palo == mejor.palo:
		return fuerza(retadora) > fuerza(mejor)
	# De distinto palo, solo gana si es triunfo (y entonces la otra no lo es).
	return retadora.palo == palo_triunfo


## Fuerza de una carta dentro de su palo: mayor número, más fuerte.
static func fuerza(carta: Carta) -> int:
	return ORDEN_DE_FUERZA.size() - ORDEN_DE_FUERZA.find(carta.valor)


static func puntos_de(carta: Carta) -> int:
	return PUNTOS.get(carta.valor, 0)


## Termina al cantar Tute o al jugarse las 10 bazas. Provisional: las vueltas
## llegan con pbi-03-tanteo-y-fin-partida.
func ha_terminado(estado: EstadoPartida) -> bool:
	var e := estado as EstadoGuinote
	return not e.tute.is_empty() or e.bazas_jugadas >= EstadoGuinote.BAZAS_POR_PARTIDA


## Si alguien cantó Tute, gana su pareja. Si no, provisional hasta
## pbi-03-tanteo-y-fin-partida: gana quien más tantos tenga, sin las reglas de
## superar 100, el mínimo de 30 sin cantes ni las vueltas (§8).
## Además de los campos del contrato devuelve el desglose, que el tanteo necesita:
## [code]puntos_cartas[/code] (con las diez últimas), [code]puntos_cantes[/code]
## y [code]motivo[/code] ("tute" o "tantos").
func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as EstadoGuinote
	var cartas: Array[int] = [0, 0]
	for equipo in 2:
		for carta: Carta in e.cartas_ganadas[equipo]:
			cartas[equipo] += puntos_de(carta)
	if e.bazas_jugadas == EstadoGuinote.BAZAS_POR_PARTIDA and not e.ultima_baza.is_empty():
		cartas[equipo_de(e.ultima_baza["ganador"])] += PUNTOS_ULTIMA_BAZA
	var cantes: Array[int] = [0, 0]
	for cante: Dictionary in e.cantes:
		cantes[equipo_de(cante["jugador_id"])] += cante["puntos"]
	var total: Array[int] = [cartas[0] + cantes[0], cartas[1] + cantes[1]]

	var ganador := 0 if total[0] >= total[1] else 1
	if not e.tute.is_empty():
		ganador = equipo_de(e.tute["jugador_id"])
	return {
		"equipo_ganador": ganador,
		"puntos_por_equipo": total,
		"puntos_cartas": cartas,
		"puntos_cantes": cantes,
		"motivo": "tute" if not e.tute.is_empty() else "tantos",
	}


## Lo que ve [param jugador_id]: su mano, lo que está boca arriba en la mesa y
## cuántas cartas tiene cada uno. Nunca las manos ajenas ni el orden del mazo.
func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var e := estado as EstadoGuinote
	var cartas_por_jugador: Array[int] = []
	for mano: Array in e.manos:
		cartas_por_jugador.append(mano.size())
	var bazas_por_equipo: Array[int] = []
	for cartas: Array in e.cartas_ganadas:
		@warning_ignore("integer_division")
		bazas_por_equipo.append(cartas.size() / NUM_JUGADORES)
	var pinta: Variant = null
	if e.pinta != null:
		pinta = e.pinta.id
	return {
		"fase": "robo" if e.fase == EstadoGuinote.Fase.ROBO else "arrastre",
		"dador": e.dador,
		"turno": e.turno,
		"palo_triunfo": nombre_palo(e.palo_triunfo),
		"pinta": pinta,
		"cartas_en_mazo": e.mazo.size() + (1 if e.pinta != null else 0),
		"mi_mano": _ids(e.manos[jugador_id]),
		"cartas_por_jugador": cartas_por_jugador,
		"baza_actual": _jugadas_a_ids(e.baza_actual),
		"ultima_baza": {} if e.ultima_baza.is_empty() else {
			"ganador": e.ultima_baza["ganador"],
			"cartas": _jugadas_a_ids(e.ultima_baza["cartas"]),
		},
		"bazas_por_equipo": bazas_por_equipo,
		"bazas_jugadas": e.bazas_jugadas,
		"cantes": e.cantes.map(func(c: Dictionary) -> Dictionary: return {
			"jugador_id": c["jugador_id"], "palo": nombre_palo(c["palo"]), "puntos": c["puntos"]}),
		"tute": e.tute.duplicate(),
	}


static func _ids(cartas: Array) -> Array[String]:
	var ids: Array[String] = []
	for carta: Carta in cartas:
		ids.append(carta.id)
	return ids


static func _jugadas_a_ids(jugadas: Array) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for jugada: Dictionary in jugadas:
		resultado.append({"jugador_id": jugada["jugador_id"], "carta_id": jugada["carta"].id})
	return resultado
