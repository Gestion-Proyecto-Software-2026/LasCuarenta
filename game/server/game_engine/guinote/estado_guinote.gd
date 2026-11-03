class_name EstadoGuinote
extends EstadoPartida
## Estado de una partida de Guiñote (analisis_funcional_app.md §8).
##
## Los asientos se numeran en el sentido en que se juega (antihorario):
## el jugador "a la derecha" de [code]p[/code] es [code](p + 1) % 4[/code] y el
## de "la izquierda", [code](p + 3) % 4[/code].

enum Fase { ROBO, ARRASTRE }

## Número de bazas "con robada" antes de empezar el arrastre: se reparten 6
## cartas a cada jugador + la pinta, y el resto del mazo se reparte en bazas de
## "num_jugadores" cartas (una por jugador) hasta agotarlo.
static func bazas_con_robo(num_jugadores: int) -> int:
	return (40 - num_jugadores * 6) / num_jugadores


## Total de bazas de una mano: cada una de las 40 cartas se juega una vez.
static func bazas_por_partida(num_jugadores: int) -> int:
	return 40 / num_jugadores

enum Mano { IDAS, VUELTA }

var fase: Fase = Fase.ROBO
## Las idas, y la vuelta si nadie superó los 100 en las idas (§8).
var mano_actual: Mano = Mano.IDAS
## Tanteo con que terminaron las idas, que se arrastra a la vuelta:
## { cartas, cantes, diez_ultimas, total } (cada uno, [equipo 0, equipo 1]). {} durante las idas.
var tanteo_idas: Dictionary = {}
## Equipo que ha ganado la partida; -1 mientras se juega.
var equipo_ganador: int = -1
## Por qué terminó: "tute", "tantos" (al acabar las idas) o "vuelta".
var motivo_fin: String = ""
var dador: int = 0
## Quién tiene que jugar ahora.
var turno: int = 0
var palo_triunfo: Carta.Palo = Carta.Palo.OROS
## La carta que marca el triunfo, boca arriba bajo el mazo. Se roba la última;
## a partir de ahí es null.
var pinta: Carta = null
## Cartas boca abajo del centro, en el orden en que se robarán (la primera, antes).
var mazo: Array[Carta] = []
## manos[jugador_id] = Array[Carta]
var manos: Array = []
## Cartas jugadas en la baza en curso, en orden: [{ "jugador_id": int, "carta": Carta }].
var baza_actual: Array[Dictionary] = []
## La última baza completa, para que el cliente pueda enseñarla:
## { "ganador": int, "cartas": [{ "jugador_id", "carta" }] }, o {} al principio.
var ultima_baza: Dictionary = {}
## Cartas ganadas por cada equipo (boca abajo), para el tanteo.
var cartas_ganadas: Array = [[], []]
var bazas_jugadas: int = 0
## Cantes hechos, en orden:
## [{ "jugador_id": int, "palo": Carta.Palo, "puntos": int, "mano": Mano }].
var cantes: Array[Dictionary] = []
## Valor de bazas_jugadas cuando cantó cada jugador por última vez (-1 si nunca):
## cada miembro de la pareja puede cantar una vez por baza ganada.
## MotorGuinote._repartir lo redimensiona a num_jugadores; el valor por
## defecto solo importa para estados construidos a mano en tests (num_jugadores=4).
var ultimo_cante_de: Array[int] = [-1, -1, -1, -1]
## Si alguien ha cantado Tute: { "jugador_id": int, "figura": "reyes" | "sotas" }.
var tute: Dictionary = {}
## Tras la 4ª baza, si alguien de la pareja ganadora tiene el 7 de triunfo, el
## último robo espera a que decida si lo cambia por la pinta. -1 si no se espera.
var siete_pendiente: int = -1
