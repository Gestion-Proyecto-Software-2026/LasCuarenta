class_name SalaActiva
extends RefCounted
## Una sala alojada en el servidor de partida: qué usuario ocupa cada asiento,
## qué conexión (peer de ENet) tiene ahora cada asiento y el estado de su partida.
## El asiento es la posición en la mesa, que es también el jugador_id del motor.

var sala_id: String
var juego: String
var capacidad: int
var motor: MotorDeJuego
## null hasta que se conectan todos los jugadores y empieza la partida.
var estado: EstadoPartida = null

var posicion_de_usuario: Dictionary = {}  # usuario_id -> posicion
var usuario_en_posicion: Dictionary = {}  # posicion -> usuario_id
var peer_en_posicion: Dictionary = {}  # posicion -> peer_id (solo asientos conectados)


func empezada() -> bool:
	return estado != null


func todos_conectados() -> bool:
	return peer_en_posicion.size() == capacidad


func posicion_de_peer(peer_id: int) -> int:
	for posicion: int in peer_en_posicion:
		if peer_en_posicion[posicion] == peer_id:
			return posicion
	return -1


## [code][{ usuario_id, posicion, equipo }][/code] ordenado por asiento.
func jugadores() -> Array[Dictionary]:
	var lista: Array[Dictionary] = []
	for posicion in range(capacidad):
		lista.append({
			"usuario_id": usuario_en_posicion.get(posicion, ""),
			"posicion": posicion,
			"equipo": MotorDeJuego.equipo_de(posicion),
		})
	return lista
