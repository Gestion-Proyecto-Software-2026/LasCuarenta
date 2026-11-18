@abstract
class_name MotorDeJuego
extends RefCounted
## Contrato común de los motores de reglas (analisis_funcional_app.md §7).
##
## Cada juego (Guiñote, Mus, Tute) hereda de esta clase, define su estado
## heredando de [EstadoPartida] e implementa los métodos abstractos.
## [code]RoomManager[/code] solo habla con esta interfaz, nunca con un juego concreto.
##
## [code]jugador_id[/code] es siempre la posición en la mesa
## ([code]0[/code] … [code]num_jugadores - 1[/code]); el motor no sabe nada de
## usuarios ni de conexiones.
##
## Una jugada es un diccionario [code]{ tipo, ...payload }[/code] con los nombres de
## los mensajes del protocolo, p. ej. [code]{ "tipo": "jugar_carta", "carta_id": "oros_1" }[/code].

const ERROR_PARTIDA_TERMINADA := "La partida ha terminado"
const ERROR_JUGADOR_INEXISTENTE := "Ese jugador no está en la partida"
const ERROR_SIN_JUGADAS := "Ahora no puedes hacer ninguna jugada"
const ERROR_JUGADA_NO_VALIDA := "Jugada no válida"

## Fuente de aleatoriedad del reparto. Los tests pasan una con semilla fija
## para que la partida sea reproducible.
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


## Números de jugadores con los que se puede jugar este juego, p. ej. [code][4][/code].
@abstract func jugadores_admitidos() -> Array[int]


## Crea el estado inicial: reparte, decide quién empieza, etc. Devuelve
## [code]null[/code] (y registra un error) si el juego no admite [param num_jugadores].
func iniciar(num_jugadores: int) -> EstadoPartida:
	if num_jugadores not in jugadores_admitidos():
		push_error("%s no admite %d jugadores (admite %s)" % [
			get_script().resource_path.get_file(), num_jugadores, jugadores_admitidos()])
		return null
	var estado := _iniciar(num_jugadores)
	estado.num_jugadores = num_jugadores
	return estado


## Lo que [param jugador_id] puede hacer ahora mismo; [code][][/code] si nada.
## Cada juego expresa aquí el turno: no hay un turno genérico porque hay jugadas
## fuera de turno (cantes en Guiñote, decisiones en Mus).
@abstract func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]


## Valida la jugada y la aplica sobre una copia del estado. [param estado] nunca
## se modifica. La validación está aquí y no en cada juego para que ninguno pueda
## saltársela.
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
## [code]{ "equipo_ganador": int, "puntos_por_equipo": Array[int] }[/code]; cada
## juego puede añadir más detalle.
@abstract func calcular_resultado(estado: EstadoPartida) -> Dictionary


## Resultado de una partida que se corta antes de terminar por algo ajeno a las
## reglas (un renuncio admitido en el chat, PBI-08): el marcador que llevaba cada
## equipo hasta ese momento (HU-016) y el ganador que se decide fuera del motor.
## Sirve para cualquier juego porque [method calcular_resultado] da el tanteo
## acumulado también a mitad de partida.
func resultado_anticipado(estado: EstadoPartida, equipo_ganador: int) -> Dictionary:
	var resultado := calcular_resultado(estado)
	resultado["equipo_ganador"] = equipo_ganador
	return resultado


## Lo que se envía a [param jugador_id] en [code]estado_partida[/code]: nunca
## debe incluir las cartas en mano de los demás jugadores.
@abstract func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary


## Reparte y prepara el estado inicial. [code]num_jugadores[/code] ya está validado.
@abstract func _iniciar(num_jugadores: int) -> EstadoPartida


## Aplica una jugada ya validada sobre [param estado] (que es una copia).
@abstract func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void


## Devuelve el motivo por el que la jugada no es válida, o [code]""[/code] si lo es.
## Por defecto exige que coincida exactamente con una de [method jugadas_validas];
## un juego con jugadas imposibles de enumerar puede sobrescribirlo.
func _validar(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> String:
	var validas := jugadas_validas(estado, jugador_id)
	if validas.is_empty():
		return ERROR_SIN_JUGADAS
	if jugada not in validas:
		return ERROR_JUGADA_NO_VALIDA
	return ""


# --- Tiempo límite para decidir (PBI-14, issue #37) ---------------------------
# RoomManager da a cada jugador del que depende la partida un tiempo para jugar;
# si se le acaba, juega por él lo que diga [method jugada_por_tiempo]. Así nadie
# se queda atascado porque otro se haya ido (AFK) o se haya desconectado.


## Tipos de jugada que se pueden hacer pero que la partida no espera (p. ej.
## cantar en el Guiñote). Quien solo tiene jugadas de estos tipos no tiene
## cuenta atrás. Por defecto, ninguno.
func tipos_de_jugada_opcionales() -> Array[String]:
	return []


## Jugadores de los que depende ahora que la partida avance: los que tienen
## alguna jugada válida que no sea opcional.
func jugadores_esperados(estado: EstadoPartida) -> Array[int]:
	var esperados: Array[int] = []
	if ha_terminado(estado):
		return esperados
	for jugador_id in estado.num_jugadores:
		if not _jugadas_obligatorias(estado, jugador_id).is_empty():
			esperados.append(jugador_id)
	return esperados


## Lo que se juega por [param jugador_id] cuando se le acaba el tiempo, o
## [code]{}[/code] si no tiene nada pendiente. Por defecto, la primera jugada
## obligatoria; cada juego puede elegir una más prudente.
func jugada_por_tiempo(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var obligatorias := _jugadas_obligatorias(estado, jugador_id)
	return {} if obligatorias.is_empty() else obligatorias[0]


func _jugadas_obligatorias(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	var opcionales := tipos_de_jugada_opcionales()
	var obligatorias: Array[Dictionary] = []
	for jugada: Dictionary in jugadas_validas(estado, jugador_id):
		if jugada.get("tipo") not in opcionales:
			obligatorias.append(jugada)
	return obligatorias
