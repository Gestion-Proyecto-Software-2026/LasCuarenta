class_name EstadoGuinote
extends EstadoPartida
## Estado de una partida de Guiñote (analisis_funcional_app.md §8).
##
## Los asientos se numeran en el sentido en que se juega (antihorario):
## el jugador "a la derecha" de [code]p[/code] es [code](p + 1) % 4[/code] y el
## de "la izquierda", [code](p + 3) % 4[/code].

enum Fase { ROBO, ARRASTRE }

## Número de bazas "con robada"; después empieza el arrastre.
const BAZAS_CON_ROBO := 4
const BAZAS_POR_PARTIDA := 10

var fase: Fase = Fase.ROBO
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
## Cantes hechos, en orden: [{ "jugador_id": int, "palo": Carta.Palo, "puntos": int }].
var cantes: Array[Dictionary] = []
## Valor de bazas_jugadas cuando cantó cada jugador por última vez (-1 si nunca):
## cada miembro de la pareja puede cantar una vez por baza ganada.
var ultimo_cante_de: Array[int] = [-1, -1, -1, -1]
## Si alguien ha cantado Tute: { "jugador_id": int, "figura": "reyes" | "sotas" }.
var tute: Dictionary = {}
