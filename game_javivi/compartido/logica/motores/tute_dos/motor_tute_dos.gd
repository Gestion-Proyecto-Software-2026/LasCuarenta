class_name MotorTuteDos
extends MotorGuinote
## Tute para 2 jugadores (analisis_funcional_app.md §10). Se juega con la misma
## mecánica que el Guiñote de 2 (mazo, robo tras cada baza, arrastre al
## acabarse el mazo, cantes, cambio de la pinta, 101 y vuelta), así que hereda
## de [MotorGuinote] y solo cambia esto:
## - 8 cartas por jugador: 12 bazas con robo y 8 de arrastre.
## - Orden y puntos del Tute: el Caballo va por encima de la Sota.
## - Se canta con Rey y Caballo. No existe la jugada de Tute.
## - Mientras queda mazo solo hay que asistir si sale triunfo (sin montar).
## - La pinta se cambia por el 7 de triunfo si es As, Tres o figura, y por el 2
##   si es blanca; igual que los cantes, solo justo después de ganar una baza.
## - Capote: al acabarse el mazo, un jugador puede anunciar que ganará todas las
##   bazas que quedan. Si lo consigue gana la partida; si pierde una, la gana el rival.
## - Para ganar por tantos no se exige el mínimo de 30 del Guiñote: si los dos
##   pasan de 100 gana quien más tiene, y si empatan, quien hizo la última baza.

const CARTAS_POR_JUGADOR := 8
## Orden de fuerza del Tute: As, Tres, Rey, Caballo, Sota, 7, 6, 5, 4, 2.
const ORDEN_TUTE: Array[int] = [1, 3, 12, 11, 10, 7, 6, 5, 4, 2]
const PUNTOS_TUTE := {1: 11, 3: 10, 12: 4, 11: 3, 10: 2}
## Cartas por las que se cambia el 7 de triunfo (el resto, "blancas", por el 2).
const ALTAS := [Cartas.AS, Cartas.TRES, Cartas.REY, Cartas.CABALLO, Cartas.SOTA]


func jugadores_admitidos() -> Array[int]:
	return [2]


func cartas_por_jugador() -> int:
	return CARTAS_POR_JUGADOR


func cartas_por_tanda() -> int:
	return 1


func orden_de_fuerza() -> Array[int]:
	return ORDEN_TUTE


func puntos_por_valor() -> Dictionary:
	return PUNTOS_TUTE


func figura_de_cante() -> int:
	return Cartas.CABALLO


func figuras_tute() -> Dictionary:
	return {}


## Mientras queda mazo, solo es obligatorio asistir si sale triunfo.
func cartas_permitidas_en_robo(mano: Array, baza: Array[Dictionary], palo_triunfo: int) -> Array:
	if baza.is_empty() or Cartas.palo(baza[0]["carta"]) != palo_triunfo:
		return mano
	var triunfos := mano.filter(func(c: String) -> bool: return Cartas.palo(c) == palo_triunfo)
	return triunfos if not triunfos.is_empty() else mano


func carta_de_cambio(pinta: String) -> int:
	var valor := Cartas.valor(pinta)
	if valor in ALTAS:
		return Cartas.SIETE
	return Cartas.DOS if valor != Cartas.DOS else -1


## Solo justo después de ganar una baza, como los cantes.
func momento_de_cambio(e: EstadoGuinote, jugador_id: int) -> bool:
	return ventana_de_cante_abierta(e, jugador_id)


## El capote se anuncia al acabarse el mazo, antes de que empiece el arrastre.
func jugadas_extra(e: EstadoGuinote, _jugador_id: int) -> Array[Dictionary]:
	var extra: Array[Dictionary] = []
	if e.capote == -1 and e.fase == EstadoGuinote.Fase.ARRASTRE \
			and e.bazas_jugadas == e.bazas_con_robo and e.baza_actual.is_empty():
		extra.append({"tipo": CAPOTE})
	return extra


func _ejecutar_jugada_extra(e: EstadoGuinote, jugador_id: int, jugada: Dictionary) -> void:
	if jugada["tipo"] == CAPOTE:
		e.capote = jugador_id


func al_cerrar_baza(e: EstadoGuinote, ganador: int) -> void:
	if e.capote == -1:
		return
	if ganador != e.capote:
		_terminar(e, equipo_de(ganador), "capote")
	elif e.bazas_jugadas == e.bazas_por_mano:
		_terminar(e, equipo_de(e.capote), "capote")


func decidir_idas(tanteo: Dictionary, equipo_ultima_baza: int) -> int:
	var total: Array = tanteo["total"]
	var superan := [0, 1].filter(func(equipo: int) -> bool: return total[equipo] > TANTOS_PARA_GANAR)
	if superan.is_empty():
		return -1
	if superan.size() == 1:
		return superan[0]
	if total[0] == total[1]:
		return equipo_ultima_baza
	return 0 if total[0] > total[1] else 1
