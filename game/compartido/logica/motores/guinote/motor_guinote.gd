class_name MotorGuinote
extends MotorDeJuego
## Motor de reglas del Guiñote (analisis_funcional_app.md §8).
## Copia adaptada de game/server/game_engine/guinote/motor_guinote.gd (Carlos):
## - Las cartas son ids de texto ([Cartas]).
## - Admite 2 jugadores además de 4: con 2 hay más bazas con robada (14) antes
##   del arrastre, y cada jugador es su propio equipo.
## - Lo que cambia de un juego a otro (orden de las cartas, figura del cante,
##   obligaciones durante el robo...) está en métodos que [MotorTuteDos] sobrescribe.
##
## Implementado: reparto, triunfo, bazas con robada (juego libre), robo tras cada
## baza, bazas de arrastre con sus obligaciones, cantes (20 y las 40), Tute,
## cambio del siete, tanteo de las idas y vuelta.

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
## Figuras con las que se canta Tute en Guiñote (en el Tute son caballos o reyes).
const FIGURAS_TUTE := {"sotas": Cartas.SOTA, "reyes": Cartas.REY}
## Hay que superar esta cifra (101 o más) para ganar por tantos.
const TANTOS_PARA_GANAR := 100
## Mínimo de tantos solo por valor de cartas (sin cantes ni diez últimas) para
## poder ganar por tantos al terminar las idas.
const MINIMO_TANTOS_DE_CARTAS := 30


func jugadores_admitidos() -> Array[int]:
	return [2, 4]


# --- Lo que cambia en el Tute de 2 (MotorTuteDos lo sobrescribe) ---

func cartas_por_jugador() -> int:
	return CARTAS_POR_TANDA * TANDAS_DE_REPARTO


func cartas_por_tanda() -> int:
	return CARTAS_POR_TANDA


func orden_de_fuerza() -> Array[int]:
	return ORDEN_DE_FUERZA


func puntos_por_valor() -> Dictionary:
	return PUNTOS


## Figura que se canta con el Rey: la Sota en Guiñote, el Caballo en el Tute.
func figura_de_cante() -> int:
	return Cartas.SOTA


func figuras_tute() -> Dictionary:
	return FIGURAS_TUTE


## Cartas que se pueden jugar mientras queda mazo. En Guiñote, cualquiera.
func cartas_permitidas_en_robo(mano: Array, _baza: Array[Dictionary], _palo_triunfo: int) -> Array:
	return mano


## Valor de la carta de triunfo que se cambia por la pinta, o -1 si no se puede.
## En Guiñote, siempre el siete.
func carta_de_cambio(_pinta: String) -> int:
	return Cartas.SIETE


## Si [param jugador_id] está en el momento de poder cambiar la pinta: en Guiñote,
## desde que su pareja gana una baza hasta que se cierra la siguiente.
func momento_de_cambio(e: EstadoGuinote, jugador_id: int) -> bool:
	return not e.ultima_baza.is_empty() and equipo_de(e.ultima_baza["ganador"]) == equipo_de(jugador_id)


## Si [param jugador_id] puede cantar ahora. En Guiñote, desde que su pareja gana
## la baza hasta que un rival echa carta en la siguiente.
func momento_de_cantar(e: EstadoGuinote, jugador_id: int) -> bool:
	return ventana_de_cante_abierta(e, jugador_id)


## Jugadas propias de cada juego que no son cartas, cantes ni cambios (el capote del Tute de 2).
func jugadas_extra(_e: EstadoGuinote, _jugador_id: int) -> Array[Dictionary]:
	var ninguna: Array[Dictionary] = []
	return ninguna


## Se llama al cerrar cada baza, antes de mirar el fin de la mano.
func al_cerrar_baza(_e: EstadoGuinote, _ganador: int) -> void:
	pass


# --- Reparto ---

## Sortea el dador, baraja, reparte y vuelve la siguiente carta como pinta.
func _iniciar(num_jugadores: int) -> EstadoPartida:
	var estado := EstadoGuinote.new()
	estado.num_jugadores = num_jugadores
	estado.dador = rng.randi_range(0, num_jugadores - 1)
	_repartir(estado)
	return estado


## Baraja y reparte para una mano nueva (las idas o la vuelta) con el dador ya
## decidido. Deja la mesa limpia: sin bazas, cantes pendientes ni pinta cambiada.
func _repartir(e: EstadoGuinote) -> void:
	var n := e.num_jugadores
	var cartas := Cartas.baraja()
	Cartas.barajar(cartas, rng)

	e.manos = []
	for jugador in n:
		e.manos.append([] as Array[String])
	@warning_ignore("integer_division")
	var tandas := cartas_por_jugador() / cartas_por_tanda()
	for tanda in tandas:
		for i in n:
			var jugador := (e.dador + 1 + i) % n
			for c in cartas_por_tanda():
				e.manos[jugador].append(cartas.pop_front())

	e.pinta = cartas.pop_front()
	e.palo_triunfo = Cartas.palo(e.pinta)
	e.mazo = cartas
	@warning_ignore("integer_division")
	e.bazas_con_robo = (Cartas.VALORES.size() * Cartas.PALOS.size() - cartas_por_jugador() * n) / n
	@warning_ignore("integer_division")
	e.bazas_por_mano = Cartas.VALORES.size() * Cartas.PALOS.size() / n
	e.turno = (e.dador + 1) % n
	e.fase = EstadoGuinote.Fase.ROBO
	e.baza_actual = []
	e.ultima_baza = {}
	e.cartas_ganadas = [[], []]
	e.bazas_jugadas = 0
	e.ultimo_cante_de.assign(range(n).map(func(_i: int) -> int: return -1))
	e.siete_pendiente = -1
	e.capote = -1


# --- Qué se puede hacer ---

func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	var e := estado as EstadoGuinote
	var validas: Array[Dictionary] = []
	if ha_terminado(e):
		return validas
	if e.siete_pendiente != -1:
		# El último robo espera a que decida quien puede cambiar la pinta; mientras,
		# no se juega carta (sí se puede cantar).
		if jugador_id == e.siete_pendiente:
			validas.append({"tipo": CAMBIAR_SIETE})
			validas.append({"tipo": NO_CAMBIAR_SIETE})
		validas.append_array(_cantes_posibles(e, jugador_id))
		return validas
	if jugador_id == e.turno:
		var permitidas: Array = e.manos[jugador_id]
		if e.fase == EstadoGuinote.Fase.ARRASTRE:
			permitidas = cartas_permitidas_en_arrastre(e.manos[jugador_id], e.baza_actual, e.palo_triunfo, jugador_id)
		else:
			permitidas = cartas_permitidas_en_robo(e.manos[jugador_id], e.baza_actual, e.palo_triunfo)
		for carta: String in permitidas:
			validas.append({"tipo": JUGAR_CARTA, "carta_id": carta})
	# Cambiar la pinta y cantar no dependen del turno: puede hacerlo cualquiera de
	# la pareja que ganó la última baza.
	if puede_cambiar_siete(e, jugador_id):
		validas.append({"tipo": CAMBIAR_SIETE})
	validas.append_array(_cantes_posibles(e, jugador_id))
	validas.append_array(jugadas_extra(e, jugador_id))
	return validas


## Si [param jugador_id] puede cambiar la carta de triunfo que toque por la
## pinta: la pinta sigue en la mesa, tiene esa carta y es su momento.
func puede_cambiar_siete(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.pinta == "" or not momento_de_cambio(e, jugador_id):
		return false
	var valor := carta_de_cambio(e.pinta)
	return valor != -1 and _tiene(e.manos[jugador_id], e.palo_triunfo, valor)


## Cantes que puede hacer [param jugador_id] ahora mismo. Hace falta que su
## equipo haya ganado la última baza y que ningún rival haya jugado todavía en
## la baza siguiente.
func _cantes_posibles(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	var cantes: Array[Dictionary] = []
	if not momento_de_cantar(e, jugador_id):
		return cantes
	var mano: Array = e.manos[jugador_id]
	if e.ultimo_cante_de[jugador_id] != e.bazas_jugadas:
		# Cada palo se canta una vez por mano: en la vuelta se puede volver a cantar.
		var cantados := e.cantes.filter(func(c: Dictionary) -> bool: return c["mano"] == e.mano_actual) \
			.map(func(c: Dictionary) -> int: return c["palo"])
		for palo in Cartas.PALOS.size():
			if palo not in cantados and _tiene(mano, palo, figura_de_cante()) and _tiene(mano, palo, Cartas.REY):
				cantes.append({"tipo": CANTAR, "palo": Cartas.nombre_palo(palo)})
	var tute := figuras_tute()
	for figura: String in tute:
		if mano.filter(func(c: String) -> bool: return Cartas.valor(c) == tute[figura]).size() == 4:
			cantes.append({"tipo": CANTAR_TUTE, "figura": figura})
	return cantes


## Si [param jugador_id] está en el momento de poder cantar: su equipo acaba de
## ganar la última baza y en la baza en curso solo ha jugado, como mucho, su
## propio equipo (quien ganó sale primero; en cuanto juega un rival, se cierra).
static func ventana_de_cante_abierta(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.ultima_baza.is_empty() or equipo_de(e.ultima_baza["ganador"]) != equipo_de(jugador_id):
		return false
	return e.baza_actual.all(func(j: Dictionary) -> bool:
		return equipo_de(j["jugador_id"]) == equipo_de(jugador_id))


static func _tiene(mano: Array, palo: int, valor: int) -> bool:
	return mano.any(func(c: String) -> bool: return Cartas.palo(c) == palo and Cartas.valor(c) == valor)


## Cartas de [param mano] que [param jugador_id] puede jugar en una baza de
## arrastre, en este orden:
## 1. Asistir al palo de salida y, si puede, montar (superar la más alta de
##    ese palo ya jugada, la haya echado quien la haya echado).
## 2. Si no tiene el palo de salida, fallar (jugar triunfo) si tiene triunfo:
##    con cualquiera si ningún rival ha fallado, o con uno que supere al triunfo
##    más alto de los rivales. Si no puede superarlo, juega libremente.
## 3. Si el palo de salida no es triunfo y alguien ya ha fallado, basta con
##    asistir, sin montar.
## 4. En cualquier otro caso, juega libremente. Quien abre la baza, también.
func cartas_permitidas_en_arrastre(mano: Array, baza: Array[Dictionary], palo_triunfo: int, jugador_id: int) -> Array:
	if baza.is_empty():
		return mano
	var palo_salida := Cartas.palo(baza[0]["carta"])

	var del_palo := mano.filter(func(c: String) -> bool: return Cartas.palo(c) == palo_salida)
	if not del_palo.is_empty():
		var alguien_ha_fallado := palo_salida != palo_triunfo \
			and baza.any(func(j: Dictionary) -> bool: return Cartas.palo(j["carta"]) == palo_triunfo)
		if alguien_ha_fallado:
			return del_palo
		var mas_alta := _mas_alta(baza, func(j: Dictionary) -> bool: return Cartas.palo(j["carta"]) == palo_salida)
		return _las_que_superan(del_palo, mas_alta, del_palo)

	var triunfos := mano.filter(func(c: String) -> bool: return Cartas.palo(c) == palo_triunfo)
	if triunfos.is_empty():
		return mano
	var triunfo_rival := _mas_alta(baza, func(j: Dictionary) -> bool:
		return Cartas.palo(j["carta"]) == palo_triunfo and equipo_de(j["jugador_id"]) != equipo_de(jugador_id))
	if triunfo_rival == "":
		return triunfos
	return _las_que_superan(triunfos, triunfo_rival, mano)


## Por qué [param jugador_id] no puede echar [param carta_id] ahora, para
## decírselo en la mesa; [code]""[/code] si sí puede.
func motivo_carta_no_valida(e: EstadoGuinote, jugador_id: int, carta_id: String) -> String:
	if e.siete_pendiente != -1:
		return "Espera: hay que decidir si se cambia la pinta."
	if jugador_id != e.turno:
		return "Espera tu turno."
	var mano: Array = e.manos[jugador_id]
	if carta_id not in mano:
		return "No tienes esa carta."
	var permitidas := cartas_permitidas_en_robo(mano, e.baza_actual, e.palo_triunfo)
	if e.fase == EstadoGuinote.Fase.ARRASTRE:
		permitidas = cartas_permitidas_en_arrastre(mano, e.baza_actual, e.palo_triunfo, jugador_id)
	if carta_id in permitidas or e.baza_actual.is_empty():
		return ""
	var salida := Cartas.palo(e.baza_actual[0]["carta"])
	if mano.any(func(c: String) -> bool: return Cartas.palo(c) == salida):
		if Cartas.palo(carta_id) != salida:
			return "Tienes que asistir: echa una carta de %s." % Cartas.nombre_palo(salida)
		var mas_alta := _mas_alta(e.baza_actual, func(j: Dictionary) -> bool: return Cartas.palo(j["carta"]) == salida)
		return "Tienes que montar: echa una carta de %s más alta que el %s." % [
			Cartas.nombre_palo(salida), Cartas.nombre(mas_alta)]
	var triunfo_rival := _mas_alta(e.baza_actual, func(j: Dictionary) -> bool:
		return Cartas.palo(j["carta"]) == e.palo_triunfo and equipo_de(j["jugador_id"]) != equipo_de(jugador_id))
	if triunfo_rival != "":
		return "Tienes que fallar con un triunfo más alto que el %s." % Cartas.nombre(triunfo_rival)
	return "No tienes %s: tienes que fallar con un triunfo (%s)." % [
		Cartas.nombre_palo(salida), Cartas.nombre_palo(e.palo_triunfo)]


## La carta más fuerte de las jugadas de [param baza] que cumplen [param filtro],
## o "" si ninguna lo cumple. Todas las que cumplen el filtro son del mismo palo.
func _mas_alta(baza: Array[Dictionary], filtro: Callable) -> String:
	var mejor := ""
	for jugada: Dictionary in baza.filter(filtro):
		if mejor == "" or fuerza(jugada["carta"]) > fuerza(mejor):
			mejor = jugada["carta"]
	return mejor


## Las cartas de [param candidatas] que superan a [param rival]; si ninguna la
## supera, [param si_ninguna].
func _las_que_superan(candidatas: Array, rival: String, si_ninguna: Array) -> Array:
	var superan := candidatas.filter(func(c: String) -> bool: return fuerza(c) > fuerza(rival))
	return superan if not superan.is_empty() else si_ninguna


# --- Jugadas ---

func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	var e := estado as EstadoGuinote
	match jugada["tipo"]:
		CANTAR:
			var palo := Cartas.PALOS.find(jugada["palo"])
			var puntos := PUNTOS_CANTE_TRIUNFO if palo == e.palo_triunfo else PUNTOS_CANTE
			e.cantes.append({"jugador_id": jugador_id, "palo": palo, "puntos": puntos, "mano": e.mano_actual})
			e.ultimo_cante_de[jugador_id] = e.bazas_jugadas
			_comprobar_fin_de_vuelta(e)
		CANTAR_TUTE:
			e.tute = {"jugador_id": jugador_id, "figura": jugada["figura"]}
			_terminar(e, equipo_de(jugador_id), "tute")
		JUGAR_CARTA:
			_jugar_carta(e, jugador_id, jugada["carta_id"])
		CAMBIAR_SIETE:
			_cambiar_siete(e, jugador_id)
			if e.siete_pendiente == jugador_id:
				_terminar_robo(e)
		NO_CAMBIAR_SIETE:
			_terminar_robo(e)
		_:
			_ejecutar_jugada_extra(e, jugador_id, jugada)


## Jugadas de [method jugadas_extra]; las aplica el juego que las define.
func _ejecutar_jugada_extra(_e: EstadoGuinote, _jugador_id: int, _jugada: Dictionary) -> void:
	pass


## La carta de cambio pasa a ser la pinta (y se robará la última) y el jugador
## se queda la que había.
func _cambiar_siete(e: EstadoGuinote, jugador_id: int) -> void:
	var mano: Array = e.manos[jugador_id]
	var valor := carta_de_cambio(e.pinta)
	for i in mano.size():
		if Cartas.palo(mano[i]) == e.palo_triunfo and Cartas.valor(mano[i]) == valor:
			var cambiada: String = mano[i]
			mano[i] = e.pinta
			e.pinta = cambiada
			return


func _jugar_carta(e: EstadoGuinote, jugador_id: int, carta_id: String) -> void:
	var mano: Array = e.manos[jugador_id]
	mano.erase(carta_id)
	e.baza_actual.append({"jugador_id": jugador_id, "carta": carta_id})

	if e.baza_actual.size() < e.num_jugadores:
		e.turno = (e.turno + 1) % e.num_jugadores
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

	al_cerrar_baza(e, ganador)
	if ha_terminado(e):
		return
	if e.mano_actual == EstadoGuinote.Mano.VUELTA:
		_comprobar_fin_de_vuelta(e)
		if ha_terminado(e):
			return
	elif e.bazas_jugadas == e.bazas_por_mano:
		_cerrar_idas(e)
		return
	if e.fase != EstadoGuinote.Fase.ROBO:
		return
	if e.bazas_jugadas == e.bazas_con_robo:
		# Último robo: la pinta se la llevará un rival del ganador. Antes, quien
		# pueda cambiarla en el equipo ganador decide si lo hace.
		for jugador in companeros(ganador, e.num_jugadores):
			if puede_cambiar_siete(e, jugador):
				e.siete_pendiente = jugador
				return
	_terminar_robo(e)


## El ganador y, en la mesa de 4, su compañero.
static func companeros(jugador_id: int, num_jugadores: int) -> Array[int]:
	var equipo: Array[int] = [jugador_id]
	if num_jugadores == 4:
		equipo.append((jugador_id + 2) % num_jugadores)
	return equipo


## Roba todo el mundo tras la baza que se acaba de cerrar y, si era la última
## con robada, empieza el arrastre.
func _terminar_robo(e: EstadoGuinote) -> void:
	e.siete_pendiente = -1
	_robar(e, e.ultima_baza["ganador"])
	if e.bazas_jugadas == e.bazas_con_robo:
		e.fase = EstadoGuinote.Fase.ARRASTRE


## Cada jugador roba una carta, empezando por el ganador de la baza y en el
## sentido del juego. La pinta se roba la última.
func _robar(e: EstadoGuinote, ganador: int) -> void:
	for i in e.num_jugadores:
		var jugador := (ganador + i) % e.num_jugadores
		if not e.mazo.is_empty():
			e.manos[jugador].append(e.mazo.pop_front())
		elif e.pinta != "":
			e.manos[jugador].append(e.pinta)
			e.pinta = ""


## Quién gana una baza: el triunfo más alto; si nadie jugó triunfo, la carta más
## alta del palo de salida (las de los otros palos no cuentan).
## [param baza] es [code][{ "jugador_id", "carta" }][/code] en orden de juego.
func ganador_de_baza(baza: Array[Dictionary], palo_triunfo: int) -> int:
	var mejor: Dictionary = baza[0]
	for jugada: Dictionary in baza.slice(1):
		if gana_a(jugada["carta"], mejor["carta"], palo_triunfo):
			mejor = jugada
	return mejor["jugador_id"]


## Si [param retadora], jugada después, supera a [param mejor] (la que va ganando la baza).
func gana_a(retadora: String, mejor: String, palo_triunfo: int) -> bool:
	if Cartas.palo(retadora) == Cartas.palo(mejor):
		return fuerza(retadora) > fuerza(mejor)
	# De distinto palo, solo gana si es triunfo (y entonces la otra no lo es).
	return Cartas.palo(retadora) == palo_triunfo


## Fuerza de una carta dentro de su palo: mayor número, más fuerte.
func fuerza(carta: String) -> int:
	var orden := orden_de_fuerza()
	return orden.size() - orden.find(Cartas.valor(carta))


func puntos_de(carta: String) -> int:
	return puntos_por_valor().get(Cartas.valor(carta), 0)


# --- Tanteo y fin de partida ---

func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as EstadoGuinote).equipo_ganador != -1


func _terminar(e: EstadoGuinote, equipo: int, motivo: String) -> void:
	e.equipo_ganador = equipo
	e.motivo_fin = motivo


## Al acabar las bazas de las idas: gana quien supere los 100 (con las reglas
## de desempate) o, si nadie los supera, se juega la vuelta.
func _cerrar_idas(e: EstadoGuinote) -> void:
	var tanteo := tanteo_de_la_mano(e)
	var ganador := decidir_idas(tanteo, equipo_de(e.ultima_baza["ganador"]))
	if ganador != -1:
		_terminar(e, ganador, "tantos")
		return
	# Vuelta: misma partida, el tanteo se arrastra. Reparte quien ganó la última baza.
	e.tanteo_idas = tanteo
	e.mano_actual = EstadoGuinote.Mano.VUELTA
	e.dador = e.ultima_baza["ganador"]
	_repartir(e)


## Quién gana al terminar las idas, o -1 si hay que jugar la vuelta.
## - Si solo un equipo supera los 100, gana ese; si los dos, el de la última baza.
## - Pero un equipo con menos de 30 tantos solo de cartas (sin cantes ni diez
##   últimas) no puede ganar por tantos: pierde, y gana el otro.
func decidir_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	var total: Array = tanteo["total"]
	var superan := [0, 1].filter(func(equipo: int) -> bool: return total[equipo] > TANTOS_PARA_GANAR)
	if superan.is_empty():
		return -1
	var ganador: int = superan[0] if superan.size() == 1 else equipo_ultima_baza
	if tanteo["cartas"][ganador] < MINIMO_TANTOS_DE_CARTAS:
		ganador = 1 - ganador
	return ganador


## En la vuelta, la partida termina en cuanto el equipo que acaba de ganar una
## baza (o de cantar tras ganarla) supera los 100 tantos sumando los de las idas.
func _comprobar_fin_de_vuelta(e: EstadoGuinote) -> void:
	if e.mano_actual != EstadoGuinote.Mano.VUELTA or e.ultima_baza.is_empty():
		return
	var equipo := equipo_de(e.ultima_baza["ganador"])
	if tanteo_acumulado(e)[equipo] > TANTOS_PARA_GANAR:
		_terminar(e, equipo, "vuelta")


## Tantos de la mano en curso, por equipo: [code]cartas[/code] (solo valor de
## cartas), [code]cantes[/code], [code]diez_ultimas[/code] y [code]total[/code].
func tanteo_de_la_mano(e: EstadoGuinote) -> Dictionary:
	var cartas: Array[int] = [0, 0]
	for equipo in 2:
		for carta: String in e.cartas_ganadas[equipo]:
			cartas[equipo] += puntos_de(carta)
	var cantes: Array[int] = [0, 0]
	for cante: Dictionary in e.cantes:
		if cante["mano"] == e.mano_actual:
			cantes[equipo_de(cante["jugador_id"])] += cante["puntos"]
	var diez_ultimas: Array[int] = [0, 0]
	if e.bazas_jugadas == e.bazas_por_mano:
		diez_ultimas[equipo_de(e.ultima_baza["ganador"])] = PUNTOS_ULTIMA_BAZA
	var total: Array[int] = []
	for equipo in 2:
		total.append(cartas[equipo] + cantes[equipo] + diez_ultimas[equipo])
	return {"cartas": cartas, "cantes": cantes, "diez_ultimas": diez_ultimas, "total": total}


## Tantos de toda la partida: los de las idas más los de la vuelta, si la hay.
func tanteo_acumulado(e: EstadoGuinote) -> Array[int]:
	var total: Array[int] = []
	total.assign(tanteo_de_la_mano(e)["total"])
	if not e.tanteo_idas.is_empty():
		for equipo in 2:
			total[equipo] += e.tanteo_idas["total"][equipo]
	return total


## [code]{ equipo_ganador, puntos_por_equipo, motivo, manos }[/code]:
## [code]puntos_por_equipo[/code] son los tantos de toda la partida y
## [code]manos[/code] el desglose de las idas y, si se jugó, de la vuelta.
func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as EstadoGuinote
	var manos: Array[Dictionary] = []
	if not e.tanteo_idas.is_empty():
		manos.append(e.tanteo_idas)
	manos.append(tanteo_de_la_mano(e))
	return {
		"equipo_ganador": e.equipo_ganador,
		"puntos_por_equipo": tanteo_acumulado(e),
		"motivo": e.motivo_fin,
		"manos": manos,
	}


## Lo que ve [param jugador_id]: su mano, lo que está boca arriba en la mesa y
## cuántas cartas tiene cada uno. Nunca las manos ajenas ni el orden del mazo.
func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var e := estado as EstadoGuinote
	var cartas_por_jugador_: Array[int] = []
	for mano: Array in e.manos:
		cartas_por_jugador_.append(mano.size())
	return {
		"fase": "robo" if e.fase == EstadoGuinote.Fase.ROBO else "arrastre",
		"dador": e.dador,
		"turno": e.turno,
		"palo_triunfo": Cartas.nombre_palo(e.palo_triunfo),
		"pinta": e.pinta,
		"cartas_en_mazo": e.mazo.size() + (1 if e.pinta != "" else 0),
		"mi_mano": e.manos[jugador_id].duplicate(),
		"cartas_por_jugador": cartas_por_jugador_,
		"baza_actual": _jugadas_a_ids(e.baza_actual),
		"ultima_baza": {} if e.ultima_baza.is_empty() else {
			"ganador": e.ultima_baza["ganador"],
			"cartas": _jugadas_a_ids(e.ultima_baza["cartas"]),
		},
		"bazas_jugadas": e.bazas_jugadas,
		"cantes": e.cantes.map(func(c: Dictionary) -> Dictionary: return {
			"jugador_id": c["jugador_id"], "palo": Cartas.nombre_palo(c["palo"]), "puntos": c["puntos"],
			"mano": "idas" if c["mano"] == EstadoGuinote.Mano.IDAS else "vuelta"}),
		"tute": e.tute.duplicate(),
		"esperando_cambio_siete": e.siete_pendiente,
		"capote": e.capote,
		"mano": "idas" if e.mano_actual == EstadoGuinote.Mano.IDAS else "vuelta",
		"tanteo_idas": e.tanteo_idas.get("total", []),
	}


## Jugadas de una baza como las manda el protocolo del equipo (§6):
## [code][{ "jugador_id", "carta_id" }][/code].
static func _jugadas_a_ids(jugadas: Array) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for jugada: Dictionary in jugadas:
		resultado.append({"jugador_id": jugada["jugador_id"], "carta_id": jugada["carta"]})
	return resultado
