class_name JugadasMus
extends RefCounted
## Valoración de las jugadas del Mus (analisis_funcional_app.md §9): Grande,
## Chica, Pares, Juego y Punto. Funciones puras sobre una mano de 4 cartas.
##
## Se juega con 8 reyes y 8 ases (la variante por defecto de §9): el Tres
## cuenta como Rey y el Dos como As, para Grande, Chica, Pares y Juego.

## Rango de cada carta, de mayor a menor: Rey = Tres, Caballo, Sota, 7, 6, 5, 4, Dos = As.
const RANGO := {12: 10, 3: 10, 11: 9, 10: 8, 7: 7, 6: 6, 5: 5, 4: 4, 2: 1, 1: 1}
## Puntos para Juego y Punto: figuras y Tres valen 10; Dos y As, 1; el resto, su número.
const PUNTOS := {12: 10, 11: 10, 10: 10, 3: 10, 2: 1, 1: 1}
const MINIMO_JUEGO := 31
## Orden del Juego, de mejor a peor.
const ORDEN_JUEGO: Array[int] = [31, 32, 40, 37, 36, 35, 34, 33]

enum Pares { NINGUNO, PAR, MEDIAS, DUPLES }


## Rangos de la mano, de mayor a menor.
static func rangos(mano: Array) -> Array[int]:
	var lista: Array[int] = []
	for carta: Carta in mano:
		lista.append(RANGO[carta.valor])
	lista.sort()
	lista.reverse()
	return lista


static func puntos(mano: Array) -> int:
	var suma := 0
	for carta: Carta in mano:
		suma += PUNTOS.get(carta.valor, carta.valor)
	return suma


static func tiene_juego(mano: Array) -> bool:
	return puntos(mano) >= MINIMO_JUEGO


## [code]{ "tipo": Pares, "rangos": Array[int] }[/code]: los rangos que forman la
## jugada, para desempatar (el del par o las medias; en duples, el par mayor y
## luego el menor). Cuatro iguales son duples.
static func pares(mano: Array) -> Dictionary:
	var cuantas := {}
	for rango in rangos(mano):
		cuantas[rango] = cuantas.get(rango, 0) + 1
	var repetidos: Array[int] = []  # de mayor a menor, porque rangos() ya va así
	for rango: int in cuantas:
		if cuantas[rango] >= 2:
			repetidos.append(rango)
	if repetidos.is_empty():
		return {"tipo": Pares.NINGUNO, "rangos": [] as Array[int]}
	var r := repetidos[0]
	match cuantas[r]:
		4:
			return {"tipo": Pares.DUPLES, "rangos": [r, r] as Array[int]}
		3:
			return {"tipo": Pares.MEDIAS, "rangos": [r] as Array[int]}
	if repetidos.size() == 2:
		return {"tipo": Pares.DUPLES, "rangos": repetidos}
	return {"tipo": Pares.PAR, "rangos": [r] as Array[int]}


static func tiene_pares(mano: Array) -> bool:
	return pares(mano)["tipo"] != Pares.NINGUNO


## Si [param mano] tiene jugada en [param lance]. En Grande, Chica y Punto, todos.
static func tiene_jugada(mano: Array, lance: EstadoMus.Lance) -> bool:
	match lance:
		EstadoMus.Lance.PARES:
			return tiene_pares(mano)
		EstadoMus.Lance.JUEGO:
			return tiene_juego(mano)
	return true


## Positivo si [param a] gana a [param b] en [param lance], negativo si pierde y
## 0 si empatan (el empate lo deshace quien esté más cerca de la mano).
static func comparar(lance: EstadoMus.Lance, a: Array, b: Array) -> int:
	match lance:
		EstadoMus.Lance.GRANDE:
			return _comparar_listas(rangos(a), rangos(b))
		EstadoMus.Lance.CHICA:
			var ra := rangos(a)
			var rb := rangos(b)
			ra.reverse()
			rb.reverse()
			return -_comparar_listas(ra, rb)
		EstadoMus.Lance.PARES:
			var pa := pares(a)
			var pb := pares(b)
			if pa["tipo"] != pb["tipo"]:
				return pa["tipo"] - pb["tipo"]
			return _comparar_listas(pa["rangos"], pb["rangos"])
		EstadoMus.Lance.JUEGO:
			return _posicion_juego(b) - _posicion_juego(a)
	return puntos(a) - puntos(b)


## Posición del juego de [param mano] en [constant ORDEN_JUEGO]; sin juego, la peor.
static func _posicion_juego(mano: Array) -> int:
	var posicion := ORDEN_JUEGO.find(puntos(mano))
	return posicion if posicion != -1 else ORDEN_JUEGO.size()


static func _comparar_listas(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] - b[i]
	return 0


## Piedras que vale la jugada de [param mano] en Pares (1, 2 o 3) o en Juego
## (3 la de 31, 2 las demás); 0 si no la tiene.
static func valor(mano: Array, lance: EstadoMus.Lance) -> int:
	match lance:
		EstadoMus.Lance.PARES:
			return pares(mano)["tipo"]
		EstadoMus.Lance.JUEGO:
			if not tiene_juego(mano):
				return 0
			return 3 if puntos(mano) == MINIMO_JUEGO else 2
	return 0
