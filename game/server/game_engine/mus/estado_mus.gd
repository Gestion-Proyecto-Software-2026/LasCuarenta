class_name EstadoMus
extends EstadoPartida
## Estado de una partida de Mus (analisis_funcional_app.md §9).
##
## Los asientos se numeran en el sentido en que se reparte y se habla
## (derecha-izquierda, antihorario), como en el Guiñote: el jugador "a la
## derecha" de [code]p[/code] es [code](p + 1) % n[/code]. En mesas de 4, parejas
## 0-2 contra 1-3; en mesas de 2, cada jugador es su propio equipo.

enum Fase { MUS, DESCARTE, LANCES }
## Los lances, en el orden en que se juegan. Punto sustituye a Juego cuando
## nadie tiene Juego.
enum Lance { GRANDE, CHICA, PARES, JUEGO, PUNTO }

const CARTAS_POR_JUGADOR := 4

var fase: Fase = Fase.MUS
## Equipo que ha ganado la partida; -1 mientras se juega.
var equipo_ganador: int = -1
## Quien es "mano": recibe las cartas el primero y habla el primero en cada fase.
var jugador_mano: int = 0
## Quién tiene que hablar (o descartarse) ahora.
var turno: int = 0
## manos[jugador_id] = Array[Carta]
var manos: Array = []
## Cartas boca abajo por repartir, en el orden en que se darán (la primera, antes).
var mazo: Array[Carta] = []
## Descartes de esta mano que pueden volver al mazo si se agota.
var descartes: Array[Carta] = []
## Descarte de cada jugador en la ronda en curso, hasta que se le dan las cartas
## que le faltan: mientras tanto no se rebaraja, para que no le vuelvan.
var descarte_ronda: Array = []
## Cuántas cartas pidió cada jugador en la última ronda de descarte (-1 si aún no
## ha habido ninguna en esta mano). Es información pública en la mesa.
var cartas_pedidas: Array[int] = []
## Jugadores que ya han dicho "mus" en la ronda en curso.
var mus_pedidos: int = 0
## Rondas de descarte jugadas en esta mano.
var rondas_de_descarte: int = 0

## Lance en curso, durante la fase de lances.
var lance: Lance = Lance.GRANDE
## Quienes hablan en el lance en curso, en orden desde la mano: todos en Grande,
## Chica y Punto; en Pares y Juego, solo quienes los tienen.
var hablan: Array[int] = []
## Envite del lance en curso; {} mientras nadie haya envidado:
## { "equipo": int (quien lo ha hecho), "apuesta": int (piedras si se quiere),
##   "apuesta_previa": int (lo que había antes de este envite, que es lo que
##   se cobra si no se quiere; 0 si es el primero), "ordago": bool,
##   "responden": Array[int] (rivales que aún pueden contestar, en orden) }.
var envite: Dictionary = {}
## Cómo ha quedado cada lance de esta mano, en el orden en que se han jugado:
## { "lance": Lance, "resultado": String, "apuesta": int, "equipo": int,
##   "ordago": bool }. [code]resultado[/code] es "paso" (nadie envidó, o solo
## una pareja tenía la jugada), "querido", "no_querido" (y [code]equipo[/code]
## es el que envidó) o "sin_jugada" (nadie tenía Pares).
var lances_jugados: Array[Dictionary] = []
## Piedras de cada equipo en el juego en curso.
var piedras: Array[int] = [0, 0]
## Piedras cobradas en la mano en curso, en el orden en que se cobran:
## { "lance": Lance, "equipo": int, "piedras": int, "concepto": String }, con
## [code]concepto[/code] "deje", "paso" (Grande o Chica sin envite), "envite"
## (lo querido) o "jugada" (lo que valen los Pares, el Juego o el Punto).
var cobros: Array[Dictionary] = []

## Juegos ganados por cada equipo en la partida.
var juegos: Array[int] = [0, 0]
## Cómo terminó cada juego, en orden: { "equipo": int (el que lo ganó),
## "piedras": Array[int], "motivo": "piedras" | "ordago" }.
var juegos_jugados: Array[Dictionary] = []
## La última mano terminada, con todas las cartas boca arriba como cuando se
## enseñan al final: { "mano": int, "manos": Array[Array[String]],
## "lances": lances_jugados, "cobros": cobros, "juego_para": int (equipo que
## ganó el juego en esa mano, o -1) }. {} hasta que termina la primera.
var ultima_mano: Dictionary = {}
