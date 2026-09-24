class_name ResultadoJugada
extends RefCounted
## Resultado de [method MotorDeJuego.aplicar_jugada]. GDScript no tiene
## excepciones, así que una jugada inválida se devuelve como un valor con
## [member ok] a [code]false[/code] y un [member error] legible, que el servidor
## reenvía tal cual en el mensaje [code]error[/code] del protocolo.

var ok: bool = false
## Estado tras aplicar la jugada. [code]null[/code] si la jugada no era válida.
var estado: EstadoPartida = null
## Motivo del rechazo. Vacío si la jugada era válida.
var error: String = ""


static func valida(p_estado: EstadoPartida) -> ResultadoJugada:
	var resultado := ResultadoJugada.new()
	resultado.ok = true
	resultado.estado = p_estado
	return resultado


static func invalida(p_error: String) -> ResultadoJugada:
	var resultado := ResultadoJugada.new()
	resultado.error = p_error
	return resultado
