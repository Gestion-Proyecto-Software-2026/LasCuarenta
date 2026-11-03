class_name Cartas
extends RefCounted
## Utilidades sobre las cartas de los motores de reglas. En los motores una
## carta es solo su id de texto, el mismo que usan los recursos de
## data/Cartas/ y la mesa: "<Valor>_<palo>", p. ej. "Caballo_oros".
## Así el estado se copia sin problemas y viaja tal cual por la red.

const PALOS: Array[String] = ["oros", "copas", "espadas", "bastos"]
const VALORES := {
	"As": 1, "Dos": 2, "Tres": 3, "Cuatro": 4, "Cinco": 5, "Seis": 6, "Siete": 7,
	"Sota": 10, "Caballo": 11, "Rey": 12,
}

const AS := 1
const DOS := 2
const TRES := 3
const SIETE := 7
const SOTA := 10
const CABALLO := 11
const REY := 12


static func valor(id: String) -> int:
	return VALORES.get(id.get_slice("_", 0), 0)


## Palo como índice de [constant PALOS] (0 = oros ... 3 = bastos).
static func palo(id: String) -> int:
	return PALOS.find(id.get_slice("_", 1))


static func id_de(p_valor: int, p_palo: int) -> String:
	return "%s_%s" % [VALORES.find_key(p_valor), PALOS[p_palo]]


## Las 40 cartas, ordenadas por palo y valor.
static func baraja() -> Array[String]:
	var ids: Array[String] = []
	for p in PALOS.size():
		for v in VALORES.values():
			ids.append(id_de(v, p))
	return ids


## Baraja [param ids] en el sitio (Fisher-Yates) con [param rng].
static func barajar(ids: Array, rng: RandomNumberGenerator) -> void:
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp


static func nombre_palo(p_palo: int) -> String:
	return PALOS[p_palo]


## "Caballo_oros" -> "Caballo de oros".
static func nombre(id: String) -> String:
	return id.replace("_", " de ")
