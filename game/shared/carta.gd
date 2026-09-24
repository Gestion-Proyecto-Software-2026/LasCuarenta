class_name Carta
extends RefCounted
## Una carta de la baraja española de 40 cartas.
##
## Es un valor puro, compartido por cliente y servidor de partida: no conoce
## texturas ni nodos. Por la red viaja solo su [member id] (p. ej. "oros_1"),
## que es también el nombre de su imagen en client/assets/cartas/.

enum Palo { OROS, COPAS, ESPADAS, BASTOS }

## Valores de la baraja de 40: del 1 (as) al 7, 10 (sota), 11 (caballo) y 12 (rey).
const VALORES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12]

var palo: Palo:
	get:
		return _palo
var valor: int:
	get:
		return _valor
## Identificador estable "<palo>_<valor>", p. ej. "espadas_12".
var id: String:
	get:
		return "%s_%d" % [(Palo.keys()[_palo] as String).to_lower(), _valor]

var _palo: Palo
var _valor: int


func _init(p_palo: Palo, p_valor: int) -> void:
	assert(p_valor in VALORES, "Valor de carta no válido en la baraja de 40: %d" % p_valor)
	_palo = p_palo
	_valor = p_valor


## Reconstruye una carta a partir de su [member id]. Devuelve [code]null[/code]
## si el id no corresponde a ninguna carta de la baraja (p. ej. un mensaje de red
## malformado), para que quien lo recibe pueda rechazarlo sin romper.
static func desde_id(p_id: String) -> Carta:
	var partes := p_id.split("_")
	if partes.size() != 2 or not partes[1].is_valid_int():
		return null
	var indice_palo := Palo.keys().find(partes[0].to_upper())
	var p_valor := partes[1].to_int()
	if indice_palo == -1 or p_valor not in VALORES:
		return null
	return Carta.new(indice_palo as Palo, p_valor)


func es_igual(otra: Carta) -> bool:
	return otra != null and otra.palo == _palo and otra.valor == _valor


func _to_string() -> String:
	return id
