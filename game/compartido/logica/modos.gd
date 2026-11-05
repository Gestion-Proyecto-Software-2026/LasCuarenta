class_name Modos
extends RefCounted
## Los modos de juego que se pueden elegir en el menú de inicio. Cada modo
## usa su propio puerto, así que un cliente solo puede entrar en un servidor
## del mismo modo (si no, los mensajes de red no encajarían).
##
## [code]juego[/code] dice qué motor de reglas lleva Juego_Motor en la partida
## (ver [code]Juego_Motor._crear_motor()[/code]).

const LISTA: Array[Dictionary] = [
	{"id": "guinote_1v1", "nombre": "Guiñote", "juego": "guinote", "jugadores": 2, "puerto": 8911},
	{"id": "guinote_2v2", "nombre": "Guiñote", "juego": "guinote", "jugadores": 4, "puerto": 8912},
	{"id": "tute_1v1", "nombre": "Tute", "juego": "tute_dos", "jugadores": 2, "puerto": 8913},
	{"id": "tute_2v2", "nombre": "Tute", "juego": "tute", "jugadores": 4, "puerto": 8914},
	{"id": "mus_1v1", "nombre": "Mus", "juego": "mus", "jugadores": 2, "puerto": 8915},
	{"id": "mus_2v2", "nombre": "Mus", "juego": "mus", "jugadores": 4, "puerto": 8916},
]

## El modo elegido en el menú; la escena de partida lo lee al arrancar.
static var elegido: Dictionary = {}
## El nombre con el que se sentó el jugador la última vez ("" = "Jugador N").
static var nombre_jugador := ""


static func buscar(id: String) -> Dictionary:
	for modo in LISTA:
		if modo["id"] == id:
			return modo
	return {}


static func disponible(modo: Dictionary) -> bool:
	return modo.get("disponible", true)


## "Guiñote 1 contra 1", "Tute por parejas"...
static func titulo(modo: Dictionary) -> String:
	return "%s %s" % [modo["nombre"], "1 contra 1" if modo["jugadores"] == 2 else "por parejas"]
