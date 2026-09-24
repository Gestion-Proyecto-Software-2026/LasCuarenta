class_name EstadoPartida
extends RefCounted
## Estado de una partida en curso. Cada juego hereda de esta clase y añade sus
## propios campos (manos, mazo, bazas, tanteo...).
##
## Las subclases no pueden tener argumentos obligatorios en [code]_init()[/code]:
## [method duplicar] crea la copia con [code]new()[/code] y luego copia cada variable.

## Lo rellena [method MotorDeJuego.iniciar]; los juegos no necesitan tocarlo.
var num_jugadores: int = 0


## Copia independiente del estado: arrays y diccionarios se copian en
## profundidad. Los objetos que contengan (p. ej. [Carta]) se comparten entre
## copias, por eso deben ser inmutables.
func duplicar() -> EstadoPartida:
	var copia: EstadoPartida = get_script().new()
	for propiedad in get_property_list():
		if not propiedad.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var valor: Variant = get(propiedad.name)
		if valor is Array or valor is Dictionary:
			valor = valor.duplicate(true)
		copia.set(propiedad.name, valor)
	return copia
