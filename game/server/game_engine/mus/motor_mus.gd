class_name MotorMus
extends MotorDeJuego
## Motor de reglas del Mus (analisis_funcional_app.md §9), a 2 o a 4 jugadores.
##
## Implementado: reparto de 4 cartas, la fase de Mus ("mus" / "no hay mus"),
## las rondas de descarte (rebarajando los descartes si se agota el mazo), los
## lances (Grande, Chica, Pares y Juego o Punto) con sus envites (pasar,
## envidar, reenvidar, órdago, quiero y no quiero), el cobro de cada mano y el
## fin del juego y de la partida. Es el motor completo de §9.

## Piedras que se pueden envidar (o subir) de una vez; para más, el órdago.
const ENVITE_MINIMO := 2
const ENVITE_MAXIMO := 10
## Un juego se gana al llegar a 40 piedras (8 amarracos); la variante corta es a 30.
const PIEDRAS_POR_JUEGO := 40
const PIEDRAS_POR_AMARRACO := 5
## La partida es al mejor de 3 juegos.
const JUEGOS_PARA_GANAR := 2

var piedras_por_juego: int
var juegos_para_ganar: int


## [param p_piedras_por_juego] y [param p_juegos_para_ganar] permiten jugar la
## variante corta o una partida a un solo juego; RoomManager usa los de §9.
func _init(p_rng: RandomNumberGenerator = null, p_piedras_por_juego := PIEDRAS_POR_JUEGO,
		p_juegos_para_ganar := JUEGOS_PARA_GANAR) -> void:
	super(p_rng)
	piedras_por_juego = p_piedras_por_juego
	juegos_para_ganar = p_juegos_para_ganar


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
	e.cobros = []
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
			_querer(e)
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
		_registrar_lance(e, "sin_jugada" if e.hablan.is_empty() else "paso")
		_siguiente_lance(e)
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
		_registrar_lance(e, "paso")
		_siguiente_lance(e)


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
	var lance := e.lance
	var equipo: int = e.envite["equipo"]
	var deje := piedras_del_deje(e.envite)
	_registrar_lance(e, "no_querido")
	if _cobrar(e, lance, equipo, deje, "deje"):
		_terminar_juego(e, equipo, "piedras")
		return
	_siguiente_lance(e)


## Lo querido se cobra al final de la mano, salvo el órdago: se enseñan las
## cartas y quien tenga la mejor jugada del lance gana el juego en el acto.
func _querer(e: EstadoMus) -> void:
	var ordago: bool = e.envite["ordago"]
	_registrar_lance(e, "querido")
	if ordago:
		_terminar_juego(e, equipo_de(mejor_jugador(e, e.lance)), "ordago")
		return
	_siguiente_lance(e)


static func piedras_del_deje(envite: Dictionary) -> int:
	return maxi(envite["apuesta_previa"], 1)


func _registrar_lance(e: EstadoMus, resultado: String) -> void:
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


# --- Cobro, fin del juego y de la partida (§9) ---

## Quien tiene la mejor jugada del lance entre quienes la tienen; a igualdad,
## el más cercano a la mano. -1 si nadie la tiene.
static func mejor_jugador(e: EstadoMus, lance: EstadoMus.Lance) -> int:
	var mejor := -1
	for n in e.manos.size():
		var jugador := en_orden(e, n)
		if not JugadasMus.tiene_jugada(e.manos[jugador], lance):
			continue
		if mejor == -1 or JugadasMus.comparar(lance, e.manos[jugador], e.manos[mejor]) > 0:
			mejor = jugador
	return mejor


## Lo que vale la jugada de [param equipo] en [param lance], sumando la de los
## dos de la pareja: en Pares y Juego, la de cada uno que la tenga; el Punto, 1.
static func valor_de_equipo(e: EstadoMus, lance: EstadoMus.Lance, equipo: int) -> int:
	if lance == EstadoMus.Lance.PUNTO:
		return 1
	var total := 0
	for jugador in e.manos.size():
		if equipo_de(jugador) == equipo:
			total += JugadasMus.valor(e.manos[jugador], lance)
	return total


## Las piedras que da al final de la mano el lance [param jugado] (de
## [member EstadoMus.lances_jugados]), por orden: [code][{ equipo, piedras, concepto }][/code].
## - Grande y Chica: en paso, 1 piedra a la mejor; querido, lo envidado a la mejor;
##   no querido, nada más (el deje ya se cobró).
## - Pares, Juego y Punto: además de lo envidado, la mejor pareja cobra lo que
##   vale su jugada. Si no se quiso, la cobra la que envidó aunque sus cartas
##   sean peores: quien no quiere pierde el derecho a cobrar ese lance.
static func cobros_del_lance(e: EstadoMus, jugado: Dictionary) -> Array[Dictionary]:
	var lance: EstadoMus.Lance = jugado["lance"]
	var cobros: Array[Dictionary] = []
	if jugado["resultado"] == "sin_jugada":
		return cobros
	var por_jugada := lance in [EstadoMus.Lance.PARES, EstadoMus.Lance.JUEGO, EstadoMus.Lance.PUNTO]
	if jugado["resultado"] == "no_querido":
		if por_jugada:
			cobros.append({"equipo": jugado["equipo"], "concepto": "jugada",
				"piedras": valor_de_equipo(e, lance, jugado["equipo"])})
		return cobros
	var ganador := equipo_de(mejor_jugador(e, lance))
	if jugado["resultado"] == "querido":
		cobros.append({"equipo": ganador, "piedras": jugado["apuesta"], "concepto": "envite"})
	elif not por_jugada:
		cobros.append({"equipo": ganador, "piedras": 1, "concepto": "paso"})
	if por_jugada:
		cobros.append({"equipo": ganador, "piedras": valor_de_equipo(e, lance, ganador), "concepto": "jugada"})
	return cobros


## Suma las piedras y dice si con ellas [param equipo] ha ganado el juego.
func _cobrar(e: EstadoMus, lance: EstadoMus.Lance, equipo: int, piedras: int, concepto: String) -> bool:
	e.piedras[equipo] += piedras
	e.cobros.append({"lance": lance, "equipo": equipo, "piedras": piedras, "concepto": concepto})
	return e.piedras[equipo] >= piedras_por_juego


## Al acabar los lances se enseñan las cartas y se cobra lance a lance, en el
## orden en que se jugaron. En cuanto una pareja llega a las piedras del juego,
## lo gana y no se cobra nada más.
func _terminar_mano(e: EstadoMus) -> void:
	for jugado: Dictionary in e.lances_jugados:
		for cobro: Dictionary in cobros_del_lance(e, jugado):
			if cobro["piedras"] > 0 and _cobrar(e, jugado["lance"], cobro["equipo"], cobro["piedras"], cobro["concepto"]):
				_terminar_juego(e, cobro["equipo"], "piedras")
				return
	_guardar_ultima_mano(e, -1)
	_siguiente_mano(e)


## [param equipo] gana el juego; si con él gana la partida, termina. Si no, se
## empieza otro juego desde cero piedras.
func _terminar_juego(e: EstadoMus, equipo: int, motivo: String) -> void:
	e.juegos[equipo] += 1
	e.juegos_jugados.append({"equipo": equipo, "piedras": e.piedras.duplicate(), "motivo": motivo})
	_guardar_ultima_mano(e, equipo)
	if e.juegos[equipo] >= juegos_para_ganar:
		e.equipo_ganador = equipo
		e.hablan = []
		return
	e.piedras = [0, 0] as Array[int]
	_siguiente_mano(e)


func _guardar_ultima_mano(e: EstadoMus, juego_para: int) -> void:
	var manos: Array = []
	for mano: Array in e.manos:
		manos.append(_ids(mano))
	e.ultima_mano = {
		"mano": e.jugador_mano,
		"manos": manos,
		"lances": e.lances_jugados.duplicate(true),
		"cobros": e.cobros.duplicate(true),
		"juego_para": juego_para,
	}


## Es mano el que estaba a la derecha de la mano anterior, y se vuelve a repartir.
func _siguiente_mano(e: EstadoMus) -> void:
	e.jugador_mano = (e.jugador_mano + 1) % e.num_jugadores
	_repartir(e, e.num_jugadores)


func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as EstadoMus).equipo_ganador != -1


## [code]{ equipo_ganador, puntos_por_equipo, juegos, piedras_por_juego }[/code]:
## [code]puntos_por_equipo[/code] son los juegos ganados por cada equipo y
## [code]juegos[/code], cómo terminó cada uno ([member EstadoMus.juegos_jugados]).
## Antes de terminar, [code]equipo_ganador[/code] es -1.
func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as EstadoMus
	return {
		"equipo_ganador": e.equipo_ganador,
		"puntos_por_equipo": e.juegos.duplicate(),
		"juegos": e.juegos_jugados.duplicate(true),
		"piedras_por_juego": piedras_por_juego,
	}


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
		"lances_jugados": _con_nombre_de_lance(e.lances_jugados),
		# En la mesa se dice en voz alta si se tienen pares o juego al llegar a ese lance.
		"tienen_pares": _declaracion(e, EstadoMus.Lance.PARES) if en_lances and e.lance >= EstadoMus.Lance.PARES else null,
		"tienen_juego": _declaracion(e, EstadoMus.Lance.JUEGO) if en_lances and e.lance >= EstadoMus.Lance.JUEGO else null,
		"piedras": e.piedras.duplicate(),
		"amarracos": e.piedras.map(func(p: int) -> int: return amarracos(p)),
		"cobros": _con_nombre_de_lance(e.cobros),
		"juegos": e.juegos.duplicate(),
		"piedras_por_juego": piedras_por_juego,
		"juegos_para_ganar": juegos_para_ganar,
		# Las cartas de la mano anterior ya se enseñaron al terminarla.
		"ultima_mano": {} if e.ultima_mano.is_empty() else {
			"mano": e.ultima_mano["mano"],
			"manos": e.ultima_mano["manos"].duplicate(true),
			"lances": _con_nombre_de_lance(e.ultima_mano["lances"]),
			"cobros": _con_nombre_de_lance(e.ultima_mano["cobros"]),
			"juego_para": e.ultima_mano["juego_para"],
		},
	}


## Amarracos completos (de 5 piedras) que hay en [param piedras].
static func amarracos(piedras: int) -> int:
	@warning_ignore("integer_division")
	return piedras / PIEDRAS_POR_AMARRACO


static func _con_nombre_de_lance(lista: Array) -> Array:
	return lista.map(func(l: Dictionary) -> Dictionary:
		var copia := l.duplicate()
		copia["lance"] = nombre_lance(l["lance"])
		return copia)


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
