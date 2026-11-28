class_name FabricaDeMaquinas
extends RefCounted
## Crea el jugador máquina que corresponde a cada juego (PBI-20).
##
## El Guiñote y el Tute (a 2 y a 4) son juegos de bazas con triunfo y comparten la
## misma máquina. Para el Mus, de momento, juega al azar.


## [param juego] es el nombre del juego en la sala ([code]guinote[/code], [code]mus[/code]
## o [code]tute[/code]).
static func para_juego(juego: String, num_jugadores: int, dificultad: JugadorMaquina.Dificultad,
		rng: RandomNumberGenerator = null) -> JugadorMaquina:
	match juego:
		"guinote":
			return MaquinaDeBazas.new(MotorGuinote.new(), dificultad, rng)
		"tute":
			var reglas: MotorGuinote = MotorTuteDos.new() if num_jugadores == 2 else MotorTuteParejas.new()
			return MaquinaDeBazas.new(reglas, dificultad, rng)
		_:
			return JugadorMaquina.new(dificultad, rng)
