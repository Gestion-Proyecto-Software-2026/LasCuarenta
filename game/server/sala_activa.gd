class_name SalaActiva
extends RefCounted
## Una sala alojada en el servidor de partida: qué usuario ocupa cada asiento,
## qué conexión (peer de ENet) tiene ahora cada asiento y el estado de su partida.
## El asiento es la posición en la mesa, que es también el jugador_id del motor.

var sala_id: String
var juego: String
var capacidad: int
## Quien puede expulsar y empezar la partida (PBI-09); "" si el backend no lo dice.
var creador_id: String = ""
var motor: MotorDeJuego
## null hasta que se conectan todos los jugadores y empieza la partida.
var estado: EstadoPartida = null

var posicion_de_usuario: Dictionary = {}  # usuario_id -> posicion
var usuario_en_posicion: Dictionary = {}  # posicion -> usuario_id
var peer_en_posicion: Dictionary = {}  # posicion -> peer_id (solo asientos conectados)
var nombre_en_posicion: Dictionary = {}  # posicion -> nombre visible del usuario ("" si no se sabe)
## Lo que todos pueden saber de la última jugada aceptada (ver
## RoomManager._jugada_publica); {} hasta que alguien juega.
var ultima_jugada: Dictionary = {}

## Tiempo límite (PBI-14): posicion -> instante (ms del reloj de RoomManager) en
## que se le acaba el tiempo para decidir. Solo están los jugadores esperados.
var limite_de: Dictionary = {}
## Cuántas veces seguidas se le ha acabado el tiempo a cada jugador (posicion ->
## n); se borra cuando juega él. Con RoomManager.TIEMPOS_AGOTADOS_PARA_AUSENTE
## o más, está ausente.
var agotados_seguidos: Dictionary = {}


## Si se le ha acabado el tiempo tantas veces seguidas que se le da por ido.
func es_ausente(posicion: int) -> bool:
	return agotados_seguidos.get(posicion, 0) >= RoomManager.TIEMPOS_AGOTADOS_PARA_AUSENTE


func empezada() -> bool:
	return estado != null


func todos_conectados() -> bool:
	return peer_en_posicion.size() == capacidad


func posicion_de_peer(peer_id: int) -> int:
	for posicion: int in peer_en_posicion:
		if peer_en_posicion[posicion] == peer_id:
			return posicion
	return -1


## Lo que ve cada jugador en la sala de espera antes de empezar (payload de
## [code]sala_actualizada[/code]): solo los asientos ocupados, ordenados.
func vista_espera() -> Dictionary:
	var lista: Array[Dictionary] = []
	for posicion in range(capacidad):
		if not usuario_en_posicion.has(posicion):
			continue
		lista.append({
			"usuario_id": usuario_en_posicion[posicion],
			"nombre": nombre_en_posicion.get(posicion, ""),
			"posicion": posicion,
			"conectado": peer_en_posicion.has(posicion),
		})
	return {"creador_id": creador_id, "capacidad": capacidad, "jugadores": lista}


## Como [method jugadores], con el nombre visible de cada uno: lo que recibe el
## cliente en [code]partida_iniciada[/code] para rotular la mesa.
func jugadores_con_nombre() -> Array[Dictionary]:
	var lista := jugadores()
	for jugador: Dictionary in lista:
		jugador["nombre"] = nombre_en_posicion.get(jugador["posicion"], "")
	return lista


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
