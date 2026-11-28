class_name JugadorMaquina
extends RefCounted
## Un jugador controlado por el servidor de partida (PBI-20).
##
## Juega limpio: solo recibe lo que vería una persona sentada en su sitio (la vista
## de [method MotorDeJuego.vista_para_jugador] y sus jugadas válidas), nunca las
## cartas de los demás. Esta clase base juega al azar (nivel fácil); cada juego
## hereda de ella y aplica su criterio.

enum Dificultad { FACIL, NORMAL, DIFICIL }

const NOMBRES := {Dificultad.FACIL: "facil", Dificultad.NORMAL: "normal", Dificultad.DIFICIL: "dificil"}

var dificultad: Dificultad
var _rng: RandomNumberGenerator


func _init(p_dificultad: Dificultad = Dificultad.NORMAL, p_rng: RandomNumberGenerator = null) -> void:
	dificultad = p_dificultad
	_rng = p_rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()


## Elige una de [param validas]; [code]{}[/code] si no hay ninguna. [param vista]
## es lo que el servidor enviaría a ese jugador.
func decidir(_vista: Dictionary, validas: Array[Dictionary]) -> Dictionary:
	return _al_azar(validas)


## Nombre de una dificultad tal como viaja por la red y se guarda en la sala.
static func nombre_de(p_dificultad: Dificultad) -> String:
	return NOMBRES[p_dificultad]


## Cómo se escribe una dificultad en pantalla ("Máquina · Fácil").
static func etiqueta_de(p_dificultad: Dificultad) -> String:
	return {Dificultad.FACIL: "Fácil", Dificultad.NORMAL: "Normal", Dificultad.DIFICIL: "Difícil"}[p_dificultad]


## La dificultad que corresponde a [param nombre], o [code]-1[/code] si no existe.
static func desde_nombre(nombre: String) -> int:
	for dificultad_: int in NOMBRES:
		if NOMBRES[dificultad_] == nombre:
			return dificultad_
	return -1


func _al_azar(validas: Array[Dictionary]) -> Dictionary:
	if validas.is_empty():
		return {}
	return validas[_rng.randi_range(0, validas.size() - 1)]


static func _primera(validas: Array[Dictionary], tipo: String) -> Dictionary:
	for jugada: Dictionary in validas:
		if jugada.get("tipo") == tipo:
			return jugada
	return {}
