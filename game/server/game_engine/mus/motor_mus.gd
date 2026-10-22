class_name MotorMus
extends MotorDeJuego
## Motor de reglas del Mus (analisis_funcional_app.md §9), a 2 o a 4 jugadores.
##
## Implementado: reparto de 4 cartas, la fase de Mus ("mus" / "no hay mus") y
## las rondas de descarte, rebarajando los descartes si se agota el mazo.
## Pendiente: los lances con sus envites y el cobro (siguientes subtareas de PBI-04).


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
	_empezar_ronda_de_mus(e)


func _empezar_ronda_de_mus(e: EstadoMus) -> void:
	e.fase = EstadoMus.Fase.MUS
	e.turno = e.jugador_mano
	e.mus_pedidos = 0


## Quien es [param n]-ésimo en hablar empezando por la mano.
static func en_orden(e: EstadoMus, n: int) -> int:
	return (e.jugador_mano + n) % e.manos.size()


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


func _empezar_lances(e: EstadoMus) -> void:
	e.fase = EstadoMus.Fase.LANCES
	e.turno = e.jugador_mano


func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as EstadoMus).equipo_ganador != -1


func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as EstadoMus
	return {"equipo_ganador": e.equipo_ganador, "puntos_por_equipo": [0, 0]}


## Lo que ve [param jugador_id]: su mano y lo público de la mesa (cuántas cartas
## pidió cada uno). Nunca las manos ajenas ni el orden del mazo.
func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var e := estado as EstadoMus
	return {
		"fase": (EstadoMus.Fase.keys()[e.fase] as String).to_lower(),
		"mano": e.jugador_mano,
		"turno": e.turno,
		"mi_mano": _ids(e.manos[jugador_id]),
		"cartas_pedidas": e.cartas_pedidas.duplicate(),
		"rondas_de_descarte": e.rondas_de_descarte,
	}


static func _ids(cartas: Array) -> Array[String]:
	var ids: Array[String] = []
	for carta: Carta in cartas:
		ids.append(carta.id)
	return ids
