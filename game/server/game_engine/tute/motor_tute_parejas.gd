class_name MotorTuteParejas
extends MotorGuinote
## Tute por parejas para 4 jugadores (analisis_funcional_app.md §10). Del motor
## del Guiñote aprovecha las bazas, los cantes y el tanteo; cambia esto:
## - Se reparten las 40 cartas, 10 a cada uno de una en una; la última es del
##   dador y es la pinta (se queda en su mano). No hay mazo ni robo.
## - Arrastre desde la primera baza: asistir y montar sobre la carta que gana
##   (también si es del compañero); fallar y pisar; si no se puede pisar,
##   contrafallo.
## - Cantes de Rey y Caballo. Tras ganar su pareja la baza, cada uno puede
##   cantar uno hasta que echa su siguiente carta. Tute de reyes o de caballos.
## - Una sola mano: gana la pareja con más tantos; si empatan, la de la última baza.

const CARTAS_POR_JUGADOR := 10
const FIGURAS_TUTE_PAREJAS := {"reyes": REY, "caballos": CABALLO}


func jugadores_admitidos() -> Array[int]:
	return [4]


func cartas_por_jugador() -> int:
	return CARTAS_POR_JUGADOR


func cartas_por_tanda() -> int:
	return 1


func orden_de_fuerza() -> Array[int]:
	return MotorTuteDos.ORDEN_TUTE


func puntos_por_valor() -> Dictionary:
	return MotorTuteDos.PUNTOS_TUTE


func figura_de_cante() -> int:
	return CABALLO


func figuras_tute() -> Dictionary:
	return FIGURAS_TUTE_PAREJAS


## La pinta se queda en la mano del dador: no hay nada que cambiar.
func carta_de_cambio(_pinta: Carta) -> int:
	return -1


## Desde que su pareja gana la baza hasta que él echa carta en la siguiente,
## aunque ya hayan jugado los rivales (como en la mesa de siempre del Tute).
func momento_de_cantar(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.ultima_baza.is_empty() or equipo_de(e.ultima_baza["ganador"]) != equipo_de(jugador_id):
		return false
	return not e.baza_actual.any(func(j: Dictionary) -> bool: return j["jugador_id"] == jugador_id)


## Obligaciones del arrastre del Tute, en este orden:
## 1. Asistir al palo de salida y montar (superar a la que gana) si se puede.
##    Si la que gana es un triunfo de otro jugador, basta con asistir.
## 2. Sin palo de salida, fallar con triunfo; y si ya hay un triunfo jugado,
##    pisarlo (echar uno más alto) si se puede.
## 3. Si no se puede pisar, contrafallo: cualquier carta.
## 4. Sin palo de salida ni triunfo, cualquier carta.
func permitidas_en_arrastre(mano: Array, baza: Array[Dictionary],
		palo_triunfo: Carta.Palo, _jugador_id: int) -> Array:
	if baza.is_empty():
		return mano
	var salida: Carta.Palo = baza[0]["carta"].palo
	var ganadora := _carta_ganadora(baza, palo_triunfo)

	var del_palo := mano.filter(func(c: Carta) -> bool: return c.palo == salida)
	if not del_palo.is_empty():
		var montan := del_palo.filter(func(c: Carta) -> bool: return _gana(c, ganadora, palo_triunfo))
		return montan if not montan.is_empty() else del_palo

	var triunfos := mano.filter(func(c: Carta) -> bool: return c.palo == palo_triunfo)
	if not triunfos.is_empty():
		var pisan := triunfos.filter(func(c: Carta) -> bool: return _gana(c, ganadora, palo_triunfo))
		if not pisan.is_empty():
			return pisan
	return mano


func _motivo_en_baza(e: EstadoGuinote, jugador_id: int, carta: Carta) -> String:
	var mano: Array = e.manos[jugador_id]
	var salida: Carta.Palo = e.baza_actual[0]["carta"].palo
	var ganadora := _carta_ganadora(e.baza_actual, e.palo_triunfo)
	if mano.any(func(c: Carta) -> bool: return c.palo == salida):
		if carta.palo != salida:
			return "Tienes que asistir: echa una carta de %s." % nombre_palo(salida)
		return "Tienes que montar: echa una carta de %s más alta que el %s." % [
			nombre_palo(salida), nombre_carta(ganadora)]
	if ganadora.palo == e.palo_triunfo:
		return "Tienes que pisar: echa un triunfo más alto que el %s." % nombre_carta(ganadora)
	return "No tienes %s: tienes que fallar con un triunfo (%s)." % [
		nombre_palo(salida), nombre_palo(e.palo_triunfo)]


## La carta que va ganando [param baza].
func _carta_ganadora(baza: Array[Dictionary], palo_triunfo: Carta.Palo) -> Carta:
	var ganador := ganador_en(baza, palo_triunfo)
	for jugada: Dictionary in baza:
		if jugada["jugador_id"] == ganador:
			return jugada["carta"]
	return null


## Una sola mano: nunca hay vuelta.
func decidir_fin_de_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	var total: Array = tanteo["total"]
	if total[0] == total[1]:
		return equipo_ultima_baza
	return 0 if total[0] > total[1] else 1


## El mismo orden de preferencia que en la mesa de siempre: Tute, las 40 y las 20.
func _cantes_posibles(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	var cantes := super(e, jugador_id)
	var triunfo := nombre_palo(e.palo_triunfo)
	cantes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _prioridad(a, triunfo) < _prioridad(b, triunfo))
	return cantes


static func _prioridad(cante: Dictionary, triunfo: String) -> int:
	if cante["tipo"] == MensajesRed.CANTAR_TUTE:
		return 0
	return 1 if cante["palo"] == triunfo else 2


## Todas las cartas, de una en una desde la derecha del dador; la última, la
## pinta, es del dador. Empieza el arrastre directamente.
func _repartir(e: EstadoGuinote) -> void:
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)
	e.manos = []
	for jugador in e.num_jugadores:
		e.manos.append([] as Array[Carta])
	for i in cartas.size():
		e.manos[(e.dador + 1 + i) % e.num_jugadores].append(cartas[i])
	e.pinta = e.manos[e.dador].back()
	e.palo_triunfo = e.pinta.palo
	e.mazo = [] as Array[Carta]
	_preparar_mano(e, EstadoGuinote.Fase.ARRASTRE)
