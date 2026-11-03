@abstract
class_name MotorDeJuego
extends RefCounted
## Contrato común de los motores de reglas (analisis_funcional_app.md §7).
## Copia de game/server/game_engine/motor_de_juego.gd (Carlos) para el prototipo:
## aquí las cartas son ids de texto (ver [Cartas]).
##
## [code]jugador_id[/code] es siempre la posición en la mesa
## ([code]0[/code] … [code]num_jugadores - 1[/code]); el motor no sabe nada de
## conexiones. Una jugada es un diccionario [code]{ tipo, ...datos }[/code], p. ej.
## [code]{ "tipo": "jugar_carta", "carta_id": "As_oros" }[/code].

const ERROR_PARTIDA_TERMINADA := "La partida ha terminado"
const ERROR_JUGADOR_INEXISTENTE := "Ese jugador no está en la partida"
const ERROR_SIN_JUGADAS := "Ahora no puedes hacer ninguna jugada"
const ERROR_JUGADA_NO_VALIDA := "Jugada no válida"

# Tipos de jugada (los mismos nombres que game/shared/mensajes_red.gd).
const JUGAR_CARTA := "jugar_carta"
const CANTAR := "cantar"
const CANTAR_TUTE := "cantar_tute"
const CAMBIAR_SIETE := "cambiar_siete"
const NO_CAMBIAR_SIETE := "no_cambiar_siete"
const CAPOTE := "capote"
const MUS := "mus"
const NO_MUS := "no_mus"
const DESCARTAR := "descartar"
const PASAR := "pasar"
const ENVIDAR := "envidar"
const ORDAGO := "ordago"
const QUIERO := "quiero"
const NO_QUIERO := "no_quiero"

## Fuente de aleatoriedad del reparto. Con semilla fija la partida es reproducible.
var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	if p_rng == null:
		p_rng = RandomNumberGenerator.new()
		p_rng.randomize()
	rng = p_rng


## Equipo de un jugador según su posición: en mesas de 4, parejas 0-2 contra 1-3;
## en mesas de 2, cada jugador es su propio equipo.
static func equipo_de(jugador_id: int) -> int:
	return jugador_id % 2


## Números de jugadores con los que se puede jugar este juego, p. ej. [code][2, 4][/code].
@abstract func jugadores_admitidos() -> Array[int]


## Crea el estado inicial. Devuelve [code]null[/code] si el juego no admite [param num_jugadores].
func iniciar(num_jugadores: int) -> EstadoPartida:
	if num_jugadores not in jugadores_admitidos():
		push_error("%s no admite %d jugadores (admite %s)" % [
			get_script().resource_path.get_file(), num_jugadores, jugadores_admitidos()])
		return null
	var estado := _iniciar(num_jugadores)
	estado.num_jugadores = num_jugadores
	return estado


## Lo que [param jugador_id] puede hacer ahora mismo; [code][][/code] si nada.
@abstract func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]


## Valida la jugada y la aplica sobre una copia del estado. [param estado] nunca se modifica.
func aplicar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> ResultadoJugada:
	if ha_terminado(estado):
		return ResultadoJugada.invalida(ERROR_PARTIDA_TERMINADA)
	if jugador_id < 0 or jugador_id >= estado.num_jugadores:
		return ResultadoJugada.invalida(ERROR_JUGADOR_INEXISTENTE)
	var error := _validar(estado, jugador_id, jugada)
	if not error.is_empty():
		return ResultadoJugada.invalida(error)
	var nuevo := estado.duplicar()
	_ejecutar_jugada(nuevo, jugador_id, jugada)
	return ResultadoJugada.valida(nuevo)


@abstract func ha_terminado(estado: EstadoPartida) -> bool


## Resultado final. Como mínimo
## [code]{ "equipo_ganador": int, "puntos_por_equipo": Array[int] }[/code].
@abstract func calcular_resultado(estado: EstadoPartida) -> Dictionary


## Lo que se envía a [param jugador_id]: nunca las cartas en mano de los demás.
@abstract func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary


## Reparte y prepara el estado inicial. [code]num_jugadores[/code] ya está validado.
@abstract func _iniciar(num_jugadores: int) -> EstadoPartida


## Aplica una jugada ya validada sobre [param estado] (que es una copia).
@abstract func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void


## Motivo por el que la jugada no es válida, o [code]""[/code] si lo es. Por
## defecto exige que coincida exactamente con una de [method jugadas_validas].
func _validar(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> String:
	var validas := jugadas_validas(estado, jugador_id)
	if validas.is_empty():
		return ERROR_SIN_JUGADAS
	if jugada not in validas:
		return ERROR_JUGADA_NO_VALIDA
	return ""
