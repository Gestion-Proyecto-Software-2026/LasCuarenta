class_name Baraja
extends RefCounted
## Baraja española de 40 cartas: creación y barajado.
##
## El barajado recibe el RandomNumberGenerator desde fuera para que los tests
## (y la reproducción de una partida) puedan fijar la semilla.

const TOTAL_CARTAS := 40


## Devuelve las 40 cartas ordenadas por palo y valor.
static func crear() -> Array[Carta]:
	var cartas: Array[Carta] = []
	for palo in Carta.Palo.values():
		for valor in Carta.VALORES:
			cartas.append(Carta.new(palo, valor))
	return cartas


## Baraja [param cartas] en el sitio (Fisher-Yates) usando [param rng].
static func barajar(cartas: Array[Carta], rng: RandomNumberGenerator) -> void:
	for i in range(cartas.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cartas[i]
		cartas[i] = cartas[j]
		cartas[j] = tmp
