class_name MotorGuinote
extends MotorDeJuego
## Motor de reglas del Guiñote (analisis_funcional_app.md §8).
##
## Implementado: reparto, triunfo, las bazas "con robada" (juego libre), el
## robo tras cada baza, las bazas de arrastre con sus obligaciones, los
## cantes (20 y las 40), el Tute, el cambio del siete, el tanteo de las idas
## y la vuelta. Es el motor completo de §8, a 2 o a 4 jugadores.
##
## Lo que cambia de un juego de bazas a otro (cartas por jugador, orden de las
## cartas, figura del cante, obligaciones mientras hay mazo, cambio de la
## pinta...) está en los métodos de la sección "Lo que cambia en cada juego",
## que sobrescriben [MotorTuteDos] y [MotorTuteParejas].
##
## Las funciones estáticas ([method fuerza], [method ganador_de_baza],
## [method cartas_permitidas_en_arrastre]...) son las reglas del Guiñote, para
## quien no tenga un motor a mano; por dentro, el motor usa las versiones de
## instancia, que cada juego puede cambiar.

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
const DOS := 2
const SIETE := 7
const SOTA := 10
const CABALLO := 11
const REY := 12
## Figuras con las que se canta Tute en Guiñote (en el Tute son caballos o reyes).
const FIGURAS_TUTE := {"sotas": SOTA, "reyes": REY}
## Hay que superar esta cifra (101 o más) para ganar por tantos.
const TANTOS_PARA_GANAR := 100
## Mínimo de tantos solo por valor de cartas (sin cantes ni diez últimas) para
## poder ganar por tantos al terminar las idas.
const MINIMO_TANTOS_DE_CARTAS := 30
## Nombre de cada valor para los mensajes al jugador ("Rey de espadas").
const NOMBRE_VALOR := {1: "As", 2: "Dos", 3: "Tres", 4: "Cuatro", 5: "Cinco", 6: "Seis",
	7: "Siete", 10: "Sota", 11: "Caballo", 12: "Rey"}


## 2 jugadores (cada uno su propio equipo, sin pareja) o 4 (2 parejas).
func jugadores_admitidos() -> Array[int]:
	return [2, 4]


# --- Lo que cambia en cada juego (el Tute lo sobrescribe) ---

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
	return SOTA


func figuras_tute() -> Dictionary:
	return FIGURAS_TUTE


## Cartas que se pueden jugar mientras queda mazo. En Guiñote, cualquiera.
func cartas_permitidas_en_robo(mano: Array, _baza: Array[Dictionary], _palo_triunfo: Carta.Palo) -> Array:
	return mano


## Valor de la carta de triunfo que se cambia por [param pinta], o -1 si no se
## puede. En Guiñote, siempre el siete.
func carta_de_cambio(_pinta: Carta) -> int:
	return SIETE


## Si [param jugador_id] está en el momento de poder cambiar la pinta: en
## Guiñote, desde que su pareja gana una baza hasta que se cierra la siguiente.
func momento_de_cambio(e: EstadoGuinote, jugador_id: int) -> bool:
	return not e.ultima_baza.is_empty() and equipo_de(e.ultima_baza["ganador"]) == equipo_de(jugador_id)


## Si [param jugador_id] puede cantar ahora. En Guiñote, desde que su pareja
## gana la baza hasta que un rival echa carta en la siguiente.
func momento_de_cantar(e: EstadoGuinote, jugador_id: int) -> bool:
	return ventana_de_cante_abierta(e, jugador_id)


## Jugadas propias de un juego que no son cartas, cantes ni cambios (el capote
## del Tute de 2). En Guiñote, ninguna.
func jugadas_extra(_e: EstadoGuinote, _jugador_id: int) -> Array[Dictionary]:
	var ninguna: Array[Dictionary] = []
	return ninguna


## Aplica las jugadas de [method jugadas_extra].
func _ejecutar_jugada_extra(_e: EstadoGuinote, _jugador_id: int, _jugada: Dictionary) -> void:
	pass


## Se llama al cerrar cada baza, antes de mirar el fin de la mano.
func al_cerrar_baza(_e: EstadoGuinote, _ganador: int) -> void:
	pass


## Quién gana al terminar las idas, o -1 si hay que jugar la vuelta. En
## Guiñote, [method decidir_idas].
func decidir_fin_de_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	return decidir_idas(tanteo, equipo_ultima_baza)


## Bazas "con robada" antes del arrastre: el mazo que queda tras repartir, de
## una carta por jugador y baza (0 si se reparten todas, como en el Tute de 4).
func bazas_con_robo(e: EstadoGuinote) -> int:
	@warning_ignore("integer_division")
	return (Baraja.TOTAL_CARTAS - cartas_por_jugador() * e.num_jugadores) / e.num_jugadores


## Bazas de una mano: cada una de las 40 cartas se juega una vez.
func bazas_por_mano(e: EstadoGuinote) -> int:
	@warning_ignore("integer_division")
	return Baraja.TOTAL_CARTAS / e.num_jugadores


# --- Reparto ---

## Sortea el dador, baraja, reparte 6 cartas a cada uno en dos tandas de 3
## (empezando por la derecha del dador) y vuelve la siguiente como pinta.
## No hay corte: con la baraja ya mezclada al azar no cambia nada.
func _iniciar(num_jugadores: int) -> EstadoPartida:
	var estado := EstadoGuinote.new()
	estado.num_jugadores = num_jugadores
	estado.dador = rng.randi_range(0, num_jugadores - 1)
	_repartir(estado)
	return estado


## Baraja y reparte para una mano nueva (las idas o la vuelta) con el dador ya
## decidido. Deja la mesa limpia: sin bazas, cantes pendientes ni pinta cambiada.
func _repartir(e: EstadoGuinote) -> void:
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)

	e.manos = []
	for jugador in e.num_jugadores:
		e.manos.append([] as Array[Carta])
	@warning_ignore("integer_division")
	var tandas := cartas_por_jugador() / cartas_por_tanda()
	for tanda in tandas:
		for i in e.num_jugadores:
			var jugador := (e.dador + 1 + i) % e.num_jugadores
			for c in cartas_por_tanda():
				e.manos[jugador].append(cartas.pop_front())

	e.pinta = cartas.pop_front()
	e.palo_triunfo = e.pinta.palo
	e.mazo = cartas
	_preparar_mano(e, EstadoGuinote.Fase.ROBO)


## Deja la mesa lista para empezar una mano ya repartida.
func _preparar_mano(e: EstadoGuinote, fase: EstadoGuinote.Fase) -> void:
	e.turno = (e.dador + 1) % e.num_jugadores
	e.fase = fase
	e.baza_actual = []
	e.ultima_baza = {}
	e.cartas_ganadas = [[], []]
	e.bazas_jugadas = 0
	var ultimo_cante: Array[int] = []
	ultimo_cante.resize(e.num_jugadores)
	ultimo_cante.fill(-1)
	e.ultimo_cante_de = ultimo_cante
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
			validas.append({"tipo": MensajesRed.CAMBIAR_SIETE})
			validas.append({"tipo": MensajesRed.NO_CAMBIAR_SIETE})
		validas.append_array(_cantes_posibles(e, jugador_id))
		return validas
	if jugador_id == e.turno:
		for carta: Carta in _cartas_permitidas(e, jugador_id):
			validas.append({"tipo": MensajesRed.JUGAR_CARTA, "carta_id": carta.id})
	# Cambiar la pinta y cantar no dependen del turno: puede hacerlo cualquiera de
	# la pareja que ganó la última baza.
	if _puede_cambiar(e, jugador_id):
		validas.append({"tipo": MensajesRed.CAMBIAR_SIETE})
	validas.append_array(_cantes_posibles(e, jugador_id))
	validas.append_array(jugadas_extra(e, jugador_id))
	return validas


## Las cartas que puede echar [param jugador_id] en la baza en curso.
func _cartas_permitidas(e: EstadoGuinote, jugador_id: int) -> Array:
	var mano: Array = e.manos[jugador_id]
	if e.fase == EstadoGuinote.Fase.ARRASTRE:
		return permitidas_en_arrastre(mano, e.baza_actual, e.palo_triunfo, jugador_id)
	return cartas_permitidas_en_robo(mano, e.baza_actual, e.palo_triunfo)


## Si [param jugador_id] puede cambiar el 7 de triunfo por la pinta: la pinta
## sigue en la mesa, tiene el 7 y su pareja ganó la última baza. El derecho dura
## hasta que se cierra la baza siguiente (§8).
static func puede_cambiar_siete(e: EstadoGuinote, jugador_id: int) -> bool:
	return MotorGuinote.new()._puede_cambiar(e, jugador_id)


## Como [method puede_cambiar_siete], con la carta de cambio y el momento de
## cada juego.
func _puede_cambiar(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.pinta == null or not momento_de_cambio(e, jugador_id):
		return false
	var valor := carta_de_cambio(e.pinta)
	return valor != -1 and _tiene(e.manos[jugador_id], e.palo_triunfo, valor)


## Cantes que puede hacer [param jugador_id] ahora mismo. Hace falta que su
## pareja haya ganado la última baza y que ningún rival haya jugado todavía en
## la baza siguiente (§8).
func _cantes_posibles(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	var cantes: Array[Dictionary] = []
	if not momento_de_cantar(e, jugador_id):
		return cantes
	var mano: Array = e.manos[jugador_id]
	if e.ultimo_cante_de[jugador_id] != e.bazas_jugadas:
		# Cada palo se canta una vez por mano: en la vuelta se puede volver a cantar.
		var cantados := e.cantes.filter(func(c: Dictionary) -> bool: return c["mano"] == e.mano_actual) \
			.map(func(c: Dictionary) -> Carta.Palo: return c["palo"])
		for palo: Carta.Palo in Carta.Palo.values():
			if palo not in cantados and _tiene(mano, palo, figura_de_cante()) and _tiene(mano, palo, REY):
				cantes.append({"tipo": MensajesRed.CANTAR, "palo": nombre_palo(palo)})
	var tute := figuras_tute()
	for figura: String in tute:
		if mano.filter(func(c: Carta) -> bool: return c.valor == tute[figura]).size() == 4:
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


## "Rey de espadas", para los mensajes al jugador.
static func nombre_carta(carta: Carta) -> String:
	return "%s de %s" % [NOMBRE_VALOR[carta.valor], nombre_palo(carta.palo)]


## Cartas de [param mano] que [param jugador_id] puede jugar en una baza de
## arrastre del Guiñote, según las obligaciones de §8, en este orden:
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
	return MotorGuinote.new().permitidas_en_arrastre(mano, baza, palo_triunfo, jugador_id)


## Las obligaciones del arrastre de cada juego; en Guiñote, las de
## [method cartas_permitidas_en_arrastre].
func permitidas_en_arrastre(mano: Array, baza: Array[Dictionary],
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


## Por qué [param jugador_id] no puede hacer [param jugada] ahora, para
## decírselo en la mesa; [code]""[/code] si no hay nada mejor que el error
## genérico. [RoomManager] lo usa cuando [method aplicar_jugada] la rechaza.
func explicar_rechazo(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> String:
	var carta_id: Variant = jugada.get("carta_id")
	match jugada.get("tipo"):
		MensajesRed.JUGAR_CARTA:
			if carta_id is String:
				return motivo_carta_no_valida(estado as EstadoGuinote, jugador_id, carta_id)
		# Cantar y cambiar la pinta no van por turno: se puede llegar tarde porque
		# otro jugador ha hecho algo a la vez (p. ej. un rival ya ha echado carta).
		MensajesRed.CANTAR, MensajesRed.CANTAR_TUTE:
			return "Ya no se puede cantar: solo justo después de ganar una baza, antes de que juegue un rival."
		MensajesRed.CAMBIAR_SIETE, MensajesRed.NO_CAMBIAR_SIETE:
			return "Ya no se puede cambiar la pinta."
		MensajesRed.CAPOTE:
			return "Ya no se puede anunciar capote."
	return ""


## Por qué [param jugador_id] no puede echar [param carta_id] ahora;
## [code]""[/code] si sí puede.
func motivo_carta_no_valida(e: EstadoGuinote, jugador_id: int, carta_id: String) -> String:
	if e.siete_pendiente != -1:
		return "Espera: hay que decidir si se cambia la pinta."
	if jugador_id != e.turno:
		return "Espera tu turno."
	var carta := _en_mano(e.manos[jugador_id], carta_id)
	if carta == null:
		return "No tienes esa carta."
	if carta in _cartas_permitidas(e, jugador_id) or e.baza_actual.is_empty():
		return ""
	return _motivo_en_baza(e, jugador_id, carta)


## Qué obligación de la baza incumple [param carta], que no está permitida.
func _motivo_en_baza(e: EstadoGuinote, jugador_id: int, carta: Carta) -> String:
	var mano: Array = e.manos[jugador_id]
	var salida: Carta.Palo = e.baza_actual[0]["carta"].palo
	if e.fase == EstadoGuinote.Fase.ROBO:
		return "Ha salido triunfo: tienes que echar un triunfo (%s)." % nombre_palo(e.palo_triunfo)
	if mano.any(func(c: Carta) -> bool: return c.palo == salida):
		if carta.palo != salida:
			return "Tienes que asistir: echa una carta de %s." % nombre_palo(salida)
		var mas_alta := _mas_alta(e.baza_actual, func(j: Dictionary) -> bool: return j["carta"].palo == salida)
		return "Tienes que montar: echa una carta de %s más alta que el %s." % [
			nombre_palo(salida), nombre_carta(mas_alta)]
	var triunfo_rival := _mas_alta(e.baza_actual, func(j: Dictionary) -> bool:
		return j["carta"].palo == e.palo_triunfo and equipo_de(j["jugador_id"]) != equipo_de(jugador_id))
	if triunfo_rival != null:
		return "Tienes que fallar con un triunfo más alto que el %s." % nombre_carta(triunfo_rival)
	return "No tienes %s: tienes que fallar con un triunfo (%s)." % [
		nombre_palo(salida), nombre_palo(e.palo_triunfo)]


static func _en_mano(mano: Array, carta_id: String) -> Carta:
	for carta: Carta in mano:
		if carta.id == carta_id:
			return carta
	return null


## La carta más fuerte de las jugadas de [param baza] que cumplen [param filtro],
## o null si ninguna lo cumple. Todas las que cumplen el filtro son del mismo palo.
func _mas_alta(baza: Array[Dictionary], filtro: Callable) -> Carta:
	var mejor: Carta = null
	for jugada: Dictionary in baza.filter(filtro):
		if mejor == null or _fuerza(jugada["carta"]) > _fuerza(mejor):
			mejor = jugada["carta"]
	return mejor


## Las cartas de [param candidatas] que superan a [param rival]; si ninguna la
## supera, [param si_ninguna].
func _las_que_superan(candidatas: Array, rival: Carta, si_ninguna: Array) -> Array:
	var superan := candidatas.filter(func(c: Carta) -> bool: return _fuerza(c) > _fuerza(rival))
	return superan if not superan.is_empty() else si_ninguna


# --- Jugadas ---

func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	var e := estado as EstadoGuinote
	match jugada["tipo"]:
		MensajesRed.CANTAR:
			var palo := Carta.Palo.keys().find((jugada["palo"] as String).to_upper()) as Carta.Palo
			var puntos := PUNTOS_CANTE_TRIUNFO if palo == e.palo_triunfo else PUNTOS_CANTE
			e.cantes.append({"jugador_id": jugador_id, "palo": palo, "puntos": puntos, "mano": e.mano_actual})
			e.ultimo_cante_de[jugador_id] = e.bazas_jugadas
			_comprobar_fin_de_vuelta(e)
		MensajesRed.CANTAR_TUTE:
			e.tute = {"jugador_id": jugador_id, "figura": jugada["figura"]}
			_terminar(e, equipo_de(jugador_id), "tute")
		MensajesRed.JUGAR_CARTA:
			_jugar_carta(e, jugador_id, jugada["carta_id"])
		MensajesRed.CAMBIAR_SIETE:
			_cambiar_siete(e, jugador_id)
			if e.siete_pendiente == jugador_id:
				_terminar_robo(e)
		MensajesRed.NO_CAMBIAR_SIETE:
			_terminar_robo(e)
		_:
			_ejecutar_jugada_extra(e, jugador_id, jugada)


## La carta de cambio (en Guiñote, el 7 de triunfo) pasa a ser la pinta (y se
## robará la última) y el jugador se queda la que había.
func _cambiar_siete(e: EstadoGuinote, jugador_id: int) -> void:
	var mano: Array = e.manos[jugador_id]
	var valor := carta_de_cambio(e.pinta)
	for i in mano.size():
		if mano[i].palo == e.palo_triunfo and mano[i].valor == valor:
			var cambiada: Carta = mano[i]
			mano[i] = e.pinta
			e.pinta = cambiada
			return


func _jugar_carta(e: EstadoGuinote, jugador_id: int, carta_id: String) -> void:
	var mano: Array = e.manos[jugador_id]
	var carta: Carta = null
	for i in mano.size():
		if mano[i].id == carta_id:
			carta = mano[i]
			mano.remove_at(i)
			break
	e.baza_actual.append({"jugador_id": jugador_id, "carta": carta})

	if e.baza_actual.size() < e.num_jugadores:
		e.turno = (e.turno + 1) % e.num_jugadores
		return
	_cerrar_baza(e)


func _cerrar_baza(e: EstadoGuinote) -> void:
	var ganador := ganador_en(e.baza_actual, e.palo_triunfo)
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
	elif e.bazas_jugadas == bazas_por_mano(e):
		_cerrar_idas(e)
		return
	if e.fase != EstadoGuinote.Fase.ROBO:
		return
	if e.bazas_jugadas == bazas_con_robo(e):
		# Último robo: la pinta se la llevará un rival del ganador. Antes, quien
		# pueda cambiarla en el equipo ganador (su pareja a 4, él mismo a 2)
		# decide si lo hace.
		for jugador in e.num_jugadores:
			if equipo_de(jugador) == equipo_de(ganador) and _puede_cambiar(e, jugador):
				e.siete_pendiente = jugador
				return
	_terminar_robo(e)


## Roba todo el mundo tras la baza que se acaba de cerrar y, si era la última
## con robada, empieza el arrastre.
func _terminar_robo(e: EstadoGuinote) -> void:
	e.siete_pendiente = -1
	_robar(e, e.ultima_baza["ganador"])
	if e.bazas_jugadas == bazas_con_robo(e):
		e.fase = EstadoGuinote.Fase.ARRASTRE


## Cada jugador roba una carta, empezando por el ganador de la baza y en el
## sentido del juego. La pinta se roba la última.
func _robar(e: EstadoGuinote, ganador: int) -> void:
	for i in e.num_jugadores:
		var jugador := (ganador + i) % e.num_jugadores
		if not e.mazo.is_empty():
			e.manos[jugador].append(e.mazo.pop_front())
		elif e.pinta != null:
			e.manos[jugador].append(e.pinta)
			e.pinta = null


## Quién gana una baza de Guiñote: el triunfo más alto; si nadie jugó triunfo,
## la carta más alta del palo de salida (las de los otros palos no cuentan).
## [param baza] es [code][{ "jugador_id", "carta" }][/code] en orden de juego.
static func ganador_de_baza(baza: Array[Dictionary], palo_triunfo: Carta.Palo) -> int:
	return MotorGuinote.new().ganador_en(baza, palo_triunfo)


## Como [method ganador_de_baza], con el orden de las cartas de cada juego.
func ganador_en(baza: Array[Dictionary], palo_triunfo: Carta.Palo) -> int:
	var mejor: Dictionary = baza[0]
	for jugada: Dictionary in baza.slice(1):
		if _gana(jugada["carta"], mejor["carta"], palo_triunfo):
			mejor = jugada
	return mejor["jugador_id"]


## Si [param retadora], jugada después, supera a [param mejor] (la que va
## ganando la baza), en Guiñote.
static func gana_a(retadora: Carta, mejor: Carta, palo_triunfo: Carta.Palo) -> bool:
	return MotorGuinote.new()._gana(retadora, mejor, palo_triunfo)


func _gana(retadora: Carta, mejor: Carta, palo_triunfo: Carta.Palo) -> bool:
	if retadora.palo == mejor.palo:
		return _fuerza(retadora) > _fuerza(mejor)
	# De distinto palo, solo gana si es triunfo (y entonces la otra no lo es).
	return retadora.palo == palo_triunfo


## Fuerza de una carta dentro de su palo en Guiñote: mayor número, más fuerte.
static func fuerza(carta: Carta) -> int:
	return ORDEN_DE_FUERZA.size() - ORDEN_DE_FUERZA.find(carta.valor)


func _fuerza(carta: Carta) -> int:
	var orden := orden_de_fuerza()
	return orden.size() - orden.find(carta.valor)


## Tantos de una carta en Guiñote.
static func puntos_de(carta: Carta) -> int:
	return PUNTOS.get(carta.valor, 0)


func _puntos(carta: Carta) -> int:
	return puntos_por_valor().get(carta.valor, 0)


# --- Tanteo y fin de partida (§8) ---

func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as EstadoGuinote).equipo_ganador != -1


func _terminar(e: EstadoGuinote, equipo: int, motivo: String) -> void:
	e.equipo_ganador = equipo
	e.motivo_fin = motivo


## Al acabar las bazas de las idas: gana quien supere los 100 (con las reglas
## de desempate y del mínimo de cartas) o, si nadie los supera, se juega la vuelta.
func _cerrar_idas(e: EstadoGuinote) -> void:
	var tanteo := tanteo_de_la_mano(e)
	var ganador := decidir_fin_de_idas(tanteo, equipo_de(e.ultima_baza["ganador"]))
	if ganador != -1:
		_terminar(e, ganador, "tantos")
		return
	# Vuelta: misma partida, el tanteo se arrastra. Reparte quien ganó la última baza.
	e.tanteo_idas = tanteo
	e.mano_actual = EstadoGuinote.Mano.VUELTA
	e.dador = e.ultima_baza["ganador"]
	_repartir(e)


## Quién gana al terminar las idas del Guiñote, o -1 si hay que jugar la vuelta.
## [param tanteo] es el de [method tanteo_de_la_mano]; [param equipo_ultima_baza],
## el que hizo la última baza de las idas.
## - Si solo una pareja supera los 100, gana esa; si las dos, la de la última baza.
## - Pero una pareja con menos de 30 tantos solo de cartas (sin cantes ni diez
##   últimas) no puede ganar por tantos: pierde, y gana la otra.
static func decidir_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	var total: Array = tanteo["total"]
	var superan := [0, 1].filter(func(equipo: int) -> bool: return total[equipo] > TANTOS_PARA_GANAR)
	if superan.is_empty():
		return -1
	var ganador: int = superan[0] if superan.size() == 1 else equipo_ultima_baza
	if tanteo["cartas"][ganador] < MINIMO_TANTOS_DE_CARTAS:
		ganador = 1 - ganador
	return ganador


## En la vuelta, la partida termina en cuanto la pareja que acaba de ganar una
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
		for carta: Carta in e.cartas_ganadas[equipo]:
			cartas[equipo] += _puntos(carta)
	var cantes: Array[int] = [0, 0]
	for cante: Dictionary in e.cantes:
		if cante["mano"] == e.mano_actual:
			cantes[equipo_de(cante["jugador_id"])] += cante["puntos"]
	var diez_ultimas: Array[int] = [0, 0]
	if e.bazas_jugadas == bazas_por_mano(e):
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
## [code]puntos_por_equipo[/code] son los tantos de toda la partida,
## [code]motivo[/code] "tute", "tantos", "vuelta" o "capote", y [code]manos[/code]
## el desglose de las idas y, si se jugó, de la vuelta. Antes de terminar,
## [code]equipo_ganador[/code] es -1.
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
	var bazas_por_equipo: Array[int] = []
	for cartas: Array in e.cartas_ganadas:
		@warning_ignore("integer_division")
		bazas_por_equipo.append(cartas.size() / e.num_jugadores)
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
		"cartas_por_jugador": cartas_por_jugador_,
		"baza_actual": _jugadas_a_ids(e.baza_actual),
		"ultima_baza": {} if e.ultima_baza.is_empty() else {
			"ganador": e.ultima_baza["ganador"],
			"cartas": _jugadas_a_ids(e.ultima_baza["cartas"]),
		},
		"bazas_por_equipo": bazas_por_equipo,
		"bazas_jugadas": e.bazas_jugadas,
		"cantes": e.cantes.map(func(c: Dictionary) -> Dictionary: return {
			"jugador_id": c["jugador_id"], "palo": nombre_palo(c["palo"]), "puntos": c["puntos"],
			"mano": "idas" if c["mano"] == EstadoGuinote.Mano.IDAS else "vuelta"}),
		"tute": e.tute.duplicate(),
		"esperando_cambio_siete": e.siete_pendiente,
		"capote": e.capote,
		"mano": "idas" if e.mano_actual == EstadoGuinote.Mano.IDAS else "vuelta",
		# El tanteo de las idas se conoce al terminarlas; el de la mano en curso,
		# cada jugador lo lleva "de memoria" como en la mesa.
		"tanteo_idas": e.tanteo_idas.get("total", []),
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


## Cantar y cambiar el siete por la pinta son derechos, no obligaciones: la
## partida no espera a nadie por ellos (PBI-14); tampoco por anunciar capote en
## el Tute de 2. Cuando el último robo espera a que se decida el cambio, sigue
## habiendo cuenta atrás por no_cambiar_siete.
func tipos_de_jugada_opcionales() -> Array[String]:
	return [MensajesRed.CANTAR, MensajesRed.CANTAR_TUTE, MensajesRed.CAMBIAR_SIETE, MensajesRed.CAPOTE]
