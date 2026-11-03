class_name EstadoGuinote
extends EstadoPartida
## Estado de una partida de Guiñote (analisis_funcional_app.md §8), a 2 o a 4.
## Copia adaptada de game/server/game_engine/guinote/estado_guinote.gd (Carlos).
## También lo usa el Tute de 2 ([MotorTuteDos]), que se juega con la misma mecánica.
##
## Los asientos se numeran en el sentido en que se juega: el siguiente de
## [code]p[/code] es [code](p + 1) % num_jugadores[/code].

enum Fase { ROBO, ARRASTRE }
enum Mano { IDAS, VUELTA }

var fase: Fase = Fase.ROBO
## Bazas "con robada" de cada mano (4 en el Guiñote de 4, 14 en el de 2...);
## después empieza el arrastre. Las fija el motor al repartir.
var bazas_con_robo: int = 0
## Bazas de cada mano: las 40 cartas entre los jugadores.
var bazas_por_mano: int = 0
## Las idas, y la vuelta si nadie superó los 100 en las idas.
var mano_actual: Mano = Mano.IDAS
## Tanteo con que terminaron las idas, que se arrastra a la vuelta:
## { cartas, cantes, diez_ultimas, total } (cada uno, [equipo 0, equipo 1]). {} durante las idas.
var tanteo_idas: Dictionary = {}
## Equipo que ha ganado la partida; -1 mientras se juega.
var equipo_ganador: int = -1
## Por qué terminó: "tute", "tantos", "vuelta" o "capote".
var motivo_fin: String = ""
var dador: int = 0
## Quién tiene que jugar ahora.
var turno: int = 0
var palo_triunfo: int = 0
## La carta que marca el triunfo, boca arriba bajo el mazo. Se roba la última;
## a partir de ahí es "".
var pinta: String = ""
## Cartas boca abajo del centro, en el orden en que se robarán (la primera, antes).
var mazo: Array[String] = []
## manos[jugador_id] = Array[String]
var manos: Array = []
## Cartas jugadas en la baza en curso, en orden: [{ "jugador_id": int, "carta": String }].
var baza_actual: Array[Dictionary] = []
## La última baza completa: { "ganador": int, "cartas": [{ "jugador_id", "carta" }] }, o {} al principio.
var ultima_baza: Dictionary = {}
## Cartas ganadas por cada equipo (boca abajo), para el tanteo.
var cartas_ganadas: Array = [[], []]
var bazas_jugadas: int = 0
## Cantes hechos, en orden: [{ "jugador_id": int, "palo": int, "puntos": int, "mano": Mano }].
var cantes: Array[Dictionary] = []
## Valor de bazas_jugadas cuando cantó cada jugador por última vez (-1 si nunca):
## cada uno puede cantar una vez por baza ganada por su equipo.
var ultimo_cante_de: Array[int] = []
## Si alguien ha cantado Tute: { "jugador_id": int, "figura": String }.
var tute: Dictionary = {}
## En el último robo, si quien puede cambiar el siete tiene que decidir antes de
## que se robe la pinta, el robo espera. -1 si no se espera.
var siete_pendiente: int = -1
## Solo en el Tute de 2: quién ha anunciado capote (-1 si nadie).
var capote: int = -1
