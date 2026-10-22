class_name MotorMus
extends MotorDeJuego
## Motor de reglas del Mus (analisis_funcional_app.md §9), a 2 o a 4 jugadores.
##
## Implementado: reparto de 4 cartas, la fase de Mus ("mus" / "no hay mus"),
## las rondas de descarte (rebarajando los descartes si se agota el mazo) y los
## lances (Grande, Chica, Pares y Juego o Punto) con sus envites: pasar,
## envidar, reenvidar, órdago, quiero y no quiero, cobrando el "deje" en el acto.
## Pendiente: el cobro al final de la mano y el fin del juego y de la partida.

## Piedras que se pueden envidar (o subir) de una vez; para más, el órdago.
const ENVITE_MINIMO := 2
const ENVITE_MAXIMO := 10


func jugadores_admitidos() -> Array[int]:
	return [2, 4]


## Sortea quién es mano y reparte la primera mano.
func _iniciar(num_jugadores: int) -> EstadoPartida:
	var estado := EstadoMus.new()
	estado.jugador_mano = rng.randi_range(0, num_jugadores - 1)
	_repartir(estado, num_jugadores)
	return estado


## Baraja y da 4 cartas a cada jugador, de una en una, empezando por la mano.
## No hay corte: con la baraja ya mezclada al azar no cambia nada.
func _repartir(e: EstadoMus, num_jugadores: int) -> void:
	e.mazo = Baraja.crear()
	Baraja.barajar(e.mazo, rng)
	e.manos = []
	e.descarte_ronda = []
	e.cartas_pedidas = []
	for jugador in num_jugadores:
		e.manos.append([] as Array[Carta])
		e.descarte_ronda.append([] as Array[Carta])
		e.cartas_pedidas.append(-1)
	for vuelta in EstadoMus.CARTAS_POR_JUGADOR:
		for i in num_jugadores:
			e.manos[(e.jugador_mano + i) % num_jugadores].append(e.mazo.pop_front())
	e.descartes = []
	e.rondas_de_descarte = 0
	e.lances_jugados = []
	e.envite = {}
	e.hablan = []
	_empezar_ronda_de_mus(e)


func _empezar_ronda_de_mus(e: EstadoMus) -> void:
	e.fase = EstadoMus.Fase.MUS
	e.turno = e.jugador_mano
	e.mus_pedidos = 0


## Quien es [param n]-ésimo en hablar empezando por la mano.
static func en_orden(e: EstadoMus, n: int) -> int:
	return (e.jugador_mano + n) % e.manos.size()


## [param jugadores] ordenados por quién habla antes después de [param desde].
static func en_orden_tras(e: EstadoMus, desde: int, jugadores: Array) -> Array[int]:
	var n := e.manos.size()
	var orden: Array[int] = []
	orden.assign(jugadores)
	orden.sort_custom(func(a: int, b: int) -> bool: return (a - desde - 1 + n) % n < (b - desde - 1 + n) % n)
	return orden


func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	var e := estado as EstadoMus
	var validas: Array[Dictionary] = []
	if ha_terminado(e) or jugador_id != e.turno:
		return validas
	match e.fase:
		EstadoMus.Fase.MUS:
			validas.append({"tipo": MensajesRed.MUS})
			validas.append({"tipo": MensajesRed.NO_MUS})
		EstadoMus.Fase.DESCARTE:
			validas.append_array(descartes_posibles(e.manos[jugador_id]))
		EstadoMus.Fase.LANCES:
			validas.append_array(_jugadas_de_lance(e))
	return validas


## Lo que puede decir quien tiene la palabra en un lance: sin envite, pasar o
## envidar; ante un envite rival, quererlo, no quererlo o subirlo; ante un
## órdago, solo quererlo o no.
func _jugadas_de_lance(e: EstadoMus) -> Array[Dictionary]:
	var validas: Array[Dictionary] = []
	if e.envite.is_empty():
		validas.append({"tipo": MensajesRed.PASAR})
	else:
		validas.append({"tipo": MensajesRed.QUIERO})
		validas.append({"tipo": MensajesRed.NO_QUIERO})
		if e.envite["ordago"]:
			return validas
	for cantidad in range(ENVITE_MINIMO, ENVITE_MAXIMO + 1):
		validas.append({"tipo": MensajesRed.ENVIDAR, "cantidad": cantidad})
	validas.append({"tipo": MensajesRed.ORDAGO})
	return validas


## Todos los descartes de 1 a 4 cartas de [param mano], con las cartas en el
## orden en que están en la mano.
static func descartes_posibles(mano: Array) -> Array[Dictionary]:
	var descartes: Array[Dictionary] = []
	for mascara in range(1, 1 << mano.size()):
		var ids := []
		for i in mano.size():
			if mascara & (1 << i):
				ids.append(mano[i].id)
		descartes.append({"tipo": MensajesRed.DESCARTAR, "cartas": ids})
	return descartes


## Un descarte vale con las cartas en cualquier orden: se ordenan como en la mano
## antes de compararlo con [method jugadas_validas].
func _validar(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> String:
	var e := estado as EstadoMus
	if jugada.get("tipo") == MensajesRed.DESCARTAR and jugada.get("cartas") is Array:
		var ids := _ids(e.manos[jugador_id])
		var cartas: Array = jugada["cartas"].duplicate()
		cartas.sort_custom(func(a: Variant, b: Variant) -> bool: return ids.find(a) < ids.find(b))
		jugada = jugada.duplicate()
		jugada["cartas"] = cartas
	return super(estado, jugador_id, jugada)


func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	var e := estado as EstadoMus
	match jugada["tipo"]:
		MensajesRed.MUS:
			e.mus_pedidos += 1
			if e.mus_pedidos == e.num_jugadores:
				# Todos quieren mus: se descartan por turno, empezando por la mano.
				e.fase = EstadoMus.Fase.DESCARTE
				e.turno = e.jugador_mano
			else:
				e.turno = (e.turno + 1) % e.num_jugadores
		MensajesRed.NO_MUS:
			# En cuanto uno corta el mus, se juega con las cartas que hay.
			_empezar_lances(e)
		MensajesRed.DESCARTAR:
			_descartar(e, jugador_id, jugada["cartas"])
		MensajesRed.PASAR:
			_pasar(e, jugador_id)
		MensajesRed.ENVIDAR:
			_envidar(e, jugador_id, jugada["cantidad"], false)
		MensajesRed.ORDAGO:
			_envidar(e, jugador_id, 0, true)
		MensajesRed.QUIERO:
			_cerrar_lance(e, "querido")
		MensajesRed.NO_QUIERO:
			_no_querer(e)


func _descartar(e: EstadoMus, jugador_id: int, ids: Array) -> void:
	var mano: Array = e.manos[jugador_id]
	for id: String in ids:
		for i in mano.size():
			if mano[i].id == id:
				e.descarte_ronda[jugador_id].append(mano[i])
				mano.remove_at(i)
				break
	e.cartas_pedidas[jugador_id] = ids.size()
	e.turno = (e.turno + 1) % e.num_jugadores
	if e.turno != e.jugador_mano:
		return
	# Se han descartado todos: el dador da las que faltan, empezando por la mano.
	_completar_manos(e)
	e.rondas_de_descarte += 1
	_empezar_ronda_de_mus(e)


## Da a cada jugador, empezando por la mano, las cartas que se descartó. Si el
## mazo se agota, se barajan los descartes de quienes ya tienen sus cartas (y de
## rondas anteriores), nunca los de quien todavía espera las suyas (§9).
func _completar_manos(e: EstadoMus) -> void:
	for n in e.num_jugadores:
		var jugador := en_orden(e, n)
		while e.manos[jugador].size() < EstadoMus.CARTAS_POR_JUGADOR:
			if e.mazo.is_empty():
				e.mazo = e.descartes
				e.descartes = []
				Baraja.barajar(e.mazo, rng)
			e.manos[jugador].append(e.mazo.pop_front())
		e.descartes.append_array(e.descarte_ronda[jugador])
		e.descarte_ronda[jugador] = [] as Array[Carta]


# --- Lances y envites (§9) ---

func _empezar_lances(e: EstadoMus) -> void:
	e.fase = EstadoMus.Fase.LANCES
	_empezar_lance(e, EstadoMus.Lance.GRANDE)


## Hablan, por orden desde la mano, quienes tienen la jugada del lance. Si no hay
## nadie de las dos parejas no hay a quién envidar: el lance se da por pasado y,
## si alguien tiene la jugada, la cobra al final de la mano.
func _empezar_lance(e: EstadoMus, lance: EstadoMus.Lance) -> void:
	e.lance = lance
	e.envite = {}
	e.hablan = []
	for n in e.num_jugadores:
		var jugador := en_orden(e, n)
		if JugadasMus.tiene_jugada(e.manos[jugador], lance):
			e.hablan.append(jugador)
	var equipos := {}
	for jugador in e.hablan:
		equipos[equipo_de(jugador)] = true
	if equipos.size() < 2:
		_cerrar_lance(e, "sin_jugada" if e.hablan.is_empty() else "paso")
		return
	e.turno = e.hablan[0]


func _siguiente_lance(e: EstadoMus) -> void:
	match e.lance:
		EstadoMus.Lance.GRANDE:
			_empezar_lance(e, EstadoMus.Lance.CHICA)
		EstadoMus.Lance.CHICA:
			_empezar_lance(e, EstadoMus.Lance.PARES)
		EstadoMus.Lance.PARES:
			var alguien_tiene_juego := e.manos.any(func(mano: Array) -> bool: return JugadasMus.tiene_juego(mano))
			_empezar_lance(e, EstadoMus.Lance.JUEGO if alguien_tiene_juego else EstadoMus.Lance.PUNTO)
		_:
			_terminar_mano(e)


## Sin envite, pasar da la palabra al siguiente; si pasan todos, el lance queda
## "en paso".
func _pasar(e: EstadoMus, jugador_id: int) -> void:
	var siguiente := e.hablan.find(jugador_id) + 1
	if siguiente < e.hablan.size():
		e.turno = e.hablan[siguiente]
	else:
		_cerrar_lance(e, "paso")


## Envite, reenvite (sube [param cantidad] sobre lo envidado) u órdago. Contestan
## los rivales que tienen la jugada, por orden a partir de quien envida.
func _envidar(e: EstadoMus, jugador_id: int, cantidad: int, ordago: bool) -> void:
	var previa: int = e.envite.get("apuesta", 0)
	var equipo := equipo_de(jugador_id)
	var rivales := e.hablan.filter(func(j: int) -> bool: return equipo_de(j) != equipo)
	var responden := en_orden_tras(e, jugador_id, rivales)
	e.envite = {
		"equipo": equipo,
		"apuesta": previa + cantidad,
		"apuesta_previa": previa,
		"ordago": ordago,
		"responden": responden,
	}
	e.turno = responden[0]


## Si un rival no lo quiere contesta su compañero; si no lo quiere nadie, quien
## envidó cobra en el acto lo que había antes de su envite, o 1 piedra si era el
## primero (el "deje").
func _no_querer(e: EstadoMus) -> void:
	var responden: Array = e.envite["responden"]
	responden.pop_front()
	if not responden.is_empty():
		e.turno = responden[0]
		return
	e.piedras[e.envite["equipo"]] += piedras_del_deje(e.envite)
	_cerrar_lance(e, "no_querido")


static func piedras_del_deje(envite: Dictionary) -> int:
	return maxi(envite["apuesta_previa"], 1)


func _cerrar_lance(e: EstadoMus, resultado: String) -> void:
	var apuesta := 0
	if resultado == "querido":
		apuesta = e.envite["apuesta"]
	elif resultado == "no_querido":
		apuesta = piedras_del_deje(e.envite)
	e.lances_jugados.append({
		"lance": e.lance,
		"resultado": resultado,
		"apuesta": apuesta,
		"equipo": e.envite.get("equipo", -1),
		"ordago": e.envite.get("ordago", false),
	})
	e.envite = {}
	e.hablan = []
	if resultado == "querido" and e.lances_jugados[-1]["ordago"]:
		# Órdago querido: se enseñan las cartas y no se juega nada más de la mano.
		_terminar_mano(e)
		return
	_siguiente_lance(e)


## Pasa a la mano siguiente: es mano el que estaba a su derecha.
func _terminar_mano(e: EstadoMus) -> void:
	e.jugador_mano = (e.jugador_mano + 1) % e.num_jugadores
	_repartir(e, e.num_jugadores)


func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as EstadoMus).equipo_ganador != -1


func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as EstadoMus
	return {"equipo_ganador": e.equipo_ganador, "puntos_por_equipo": [0, 0]}


## Lo que ve [param jugador_id]: su mano y lo público de la mesa (cuántas cartas
## pidió cada uno, lo que se ha envidado y quién ha dicho tener pares o juego al
## llegar a esos lances). Nunca las manos ajenas ni el orden del mazo.
func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var e := estado as EstadoMus
	var en_lances := e.fase == EstadoMus.Fase.LANCES
	var envite := {}
	if not e.envite.is_empty():
		envite = e.envite.duplicate(true)
	return {
		"fase": (EstadoMus.Fase.keys()[e.fase] as String).to_lower(),
		"mano": e.jugador_mano,
		"turno": e.turno,
		"mi_mano": _ids(e.manos[jugador_id]),
		"cartas_pedidas": e.cartas_pedidas.duplicate(),
		"rondas_de_descarte": e.rondas_de_descarte,
		"lance": nombre_lance(e.lance) if en_lances else null,
		"hablan": e.hablan.duplicate(),
		"envite": envite,
		"lances_jugados": e.lances_jugados.map(func(l: Dictionary) -> Dictionary:
			var copia := l.duplicate()
			copia["lance"] = nombre_lance(l["lance"])
			return copia),
		# En la mesa se dice en voz alta si se tienen pares o juego al llegar a ese lance.
		"tienen_pares": _declaracion(e, EstadoMus.Lance.PARES) if en_lances and e.lance >= EstadoMus.Lance.PARES else null,
		"tienen_juego": _declaracion(e, EstadoMus.Lance.JUEGO) if en_lances and e.lance >= EstadoMus.Lance.JUEGO else null,
		"piedras": e.piedras.duplicate(),
	}


func _declaracion(e: EstadoMus, lance: EstadoMus.Lance) -> Array[bool]:
	var tienen: Array[bool] = []
	for mano: Array in e.manos:
		tienen.append(JugadasMus.tiene_jugada(mano, lance))
	return tienen


static func nombre_lance(lance: EstadoMus.Lance) -> String:
	return (EstadoMus.Lance.keys()[lance] as String).to_lower()


static func _ids(cartas: Array) -> Array[String]:
	var ids: Array[String] = []
	for carta: Carta in cartas:
		ids.append(carta.id)
	return ids
