class_name MotorTute
extends MotorGuinote
## Tute por parejas para 4 jugadores (analisis_funcional_app.md §10), como motor
## para [Juego_Motor]. Las reglas propias del Tute las sigue decidiendo
## [ReglasTute] (con sus tests): este motor solo las conecta con el contrato de
## [MotorDeJuego]. Del motor del Guiñote aprovecha las bazas, los cantes y el tanteo.
##
## Lo que cambia respecto al Guiñote:
## - Se reparten las 40 cartas, 10 a cada uno de una en una; la última es del
##   dador y es la pinta (se queda en su mano). No hay mazo ni robo.
## - Arrastre desde la primera baza: asistir, montar (también sobre el
##   compañero), fallar y pisar; si no se puede pisar, contrafallo.
## - Cantes de Rey y Caballo. Tras ganar su pareja la baza, cada uno puede
##   cantar uno hasta que echa su siguiente carta. Tute de reyes o de caballos.
## - Una sola mano: gana la pareja con más tantos; si empatan, la de la última baza.

const RUTA_CARTAS := "res://data/Cartas/%s.tres"


func jugadores_admitidos() -> Array[int]:
	return [ReglasTute.JUGADORES]


func cartas_por_jugador() -> int:
	return ReglasTute.CARTAS_POR_JUGADOR


func cartas_por_tanda() -> int:
	return 1


func orden_de_fuerza() -> Array[int]:
	return MotorTuteDos.ORDEN_TUTE


func puntos_por_valor() -> Dictionary:
	return ReglasTute.PUNTOS


func figura_de_cante() -> int:
	return ReglasTute.CABALLO


func figuras_tute() -> Dictionary:
	return ReglasTute.FIGURAS_TUTE


## La pinta se queda en la mano del dador: no hay nada que cambiar.
func carta_de_cambio(_pinta: String) -> int:
	return -1


## Desde que su pareja gana la baza hasta que él echa carta en la siguiente,
## aunque ya hayan jugado los rivales (como en la mesa de siempre del Tute).
func momento_de_cantar(e: EstadoGuinote, jugador_id: int) -> bool:
	if e.ultima_baza.is_empty() or equipo_de(e.ultima_baza["ganador"]) != equipo_de(jugador_id):
		return false
	return not e.baza_actual.any(func(j: Dictionary) -> bool: return j["jugador_id"] == jugador_id)


## Lo decide ReglasTute, que trabaja con los recursos de carta.
func cartas_permitidas_en_arrastre(mano: Array, baza: Array[Dictionary], palo_triunfo: int, _jugador_id: int) -> Array:
	var permitidas := ReglasTute.cartas_permitidas(_recursos(mano), _recursos_de_baza(baza), palo_triunfo)
	return permitidas.map(func(c: Carta) -> String: return c.id)


func motivo_carta_no_valida(e: EstadoGuinote, jugador_id: int, carta_id: String) -> String:
	if jugador_id != e.turno:
		return "Espera tu turno."
	if carta_id not in e.manos[jugador_id]:
		return "No tienes esa carta."
	return ReglasTute.motivo_rechazo(_recursos(e.manos[jugador_id]), _recursos_de_baza(e.baza_actual),
		e.palo_triunfo, _recurso(carta_id))


## Una sola mano: nunca hay vuelta.
func decidir_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	var total: Array = tanteo["total"]
	if total[0] == total[1]:
		return equipo_ultima_baza
	return 0 if total[0] > total[1] else 1


## El mismo orden de preferencia que el botón de siempre: Tute, las 40 y las 20.
func _cantes_posibles(e: EstadoGuinote, jugador_id: int) -> Array[Dictionary]:
	var cantes := super(e, jugador_id)
	var triunfo := Cartas.nombre_palo(e.palo_triunfo)
	cantes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _prioridad(a, triunfo) < _prioridad(b, triunfo))
	return cantes


static func _prioridad(cante: Dictionary, triunfo: String) -> int:
	if cante["tipo"] == CANTAR_TUTE:
		return 0
	return 1 if cante["palo"] == triunfo else 2


## Todas las cartas, de una en una desde la derecha del dador; la última, la
## pinta, es del dador. Empieza el arrastre directamente.
func _repartir(e: EstadoGuinote) -> void:
	var n := e.num_jugadores
	var cartas := Cartas.baraja()
	Cartas.barajar(cartas, rng)
	e.manos = []
	for jugador in n:
		e.manos.append([] as Array[String])
	for i in cartas.size():
		e.manos[(e.dador + 1 + i) % n].append(cartas[i])
	e.pinta = e.manos[e.dador].back()
	e.palo_triunfo = Cartas.palo(e.pinta)
	e.mazo = [] as Array[String]
	e.bazas_con_robo = 0
	e.bazas_por_mano = ReglasTute.CARTAS_POR_JUGADOR
	e.turno = (e.dador + 1) % n
	e.fase = EstadoGuinote.Fase.ARRASTRE
	e.baza_actual = []
	e.ultima_baza = {}
	e.cartas_ganadas = [[], []]
	e.bazas_jugadas = 0
	e.ultimo_cante_de.assign(range(n).map(func(_i: int) -> int: return -1))
	e.siete_pendiente = -1
	e.capote = -1


## Recursos de carta ya cargados (id -> Carta): se piden miles de veces por
## partida. Es de cada motor y no "static": Godot no libera bien al cerrar los
## scripts con variables estáticas que guardan recursos.
var _cartas_cargadas := {}


func _recurso(id: String) -> Carta:
	if not _cartas_cargadas.has(id):
		_cartas_cargadas[id] = load(RUTA_CARTAS % id)
	return _cartas_cargadas[id]


func _recursos(ids: Array) -> Array:
	return ids.map(func(id: String) -> Carta: return _recurso(id))


func _recursos_de_baza(baza: Array) -> Array:
	return baza.map(func(j: Dictionary) -> Carta: return _recurso(j["carta"]))
