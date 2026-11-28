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
## Cuándo empezó la partida (ISO 8601 en UTC, "" hasta que empieza): se manda
## al backend con el resultado para el historial (PBI-06).
var fecha_inicio: String = ""

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

## Chat de la sala (PBI-08): sus mensajes y la denuncia pendiente, si la hay.
var chat := ChatSala.new()
## La partida ha terminado. La sala sigue viva solo para el chat mientras quede
## alguien conectado (RoomManager la borra al irse el último).
var terminada := false
## Instante (ms del reloj de RoomManager) en que se pausó la partida por una
## denuncia del chat; -1 si no está en pausa.
var pausada_desde := -1

## posicion -> JugadorMaquina: las plazas que juega el propio servidor (PBI-20).
var maquinas: Dictionary = {}
## Cuándo, según el reloj del servidor, puede jugar la siguiente máquina: así
## tardan un poco en responder, como una persona.
var maquina_lista_en := 0


## Si se le ha acabado el tiempo tantas veces seguidas que se le da por ido.
func es_ausente(posicion: int) -> bool:
	return agotados_seguidos.get(posicion, 0) >= RoomManager.TIEMPOS_AGOTADOS_PARA_AUSENTE


func empezada() -> bool:
	return estado != null


## Si se está jugando: empezada, sin terminar.
func en_curso() -> bool:
	return empezada() and not terminada


func en_pausa() -> bool:
	return pausada_desde >= 0


## Para la partida (denuncia del chat): mientras dure, nadie juega y los relojes
## para decidir (PBI-14) no corren.
func pausar(ahora: int) -> void:
	if not en_pausa():
		pausada_desde = ahora


## Sigue la partida: a cada uno le queda el mismo tiempo para decidir que cuando
## se pausó, así que sus límites se retrasan lo que ha durado la pausa.
func reanudar(ahora: int) -> void:
	if not en_pausa():
		return
	var pausa := ahora - pausada_desde
	for posicion: int in limite_de:
		limite_de[posicion] += pausa
	pausada_desde = -1


func es_maquina(posicion: int) -> bool:
	return maquinas.has(posicion)


## Todas las plazas están ocupadas: por una persona conectada o por una máquina.
func todos_conectados() -> bool:
	return peer_en_posicion.size() + maquinas.size() == capacidad


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
		if maquinas.has(posicion):
			var maquina: JugadorMaquina = maquinas[posicion]
			lista.append({
				"usuario_id": "",
				"nombre": nombre_en_posicion.get(posicion, ""),
				"posicion": posicion,
				"conectado": true,
				"maquina": true,
				"dificultad": JugadorMaquina.nombre_de(maquina.dificultad),
			})
			continue
		if not usuario_en_posicion.has(posicion):
			continue
		lista.append({
			"usuario_id": usuario_en_posicion[posicion],
			"nombre": nombre_en_posicion.get(posicion, ""),
			"posicion": posicion,
			"conectado": peer_en_posicion.has(posicion),
			"maquina": false,
		})
	return {"creador_id": creador_id, "capacidad": capacidad, "jugadores": lista}


## Como [method jugadores], con el nombre visible de cada uno: lo que recibe el
## cliente en [code]partida_iniciada[/code] para rotular la mesa.
func jugadores_con_nombre() -> Array[Dictionary]:
	var lista := jugadores()
	for jugador: Dictionary in lista:
		jugador["nombre"] = nombre_en_posicion.get(jugador["posicion"], "")
		jugador["maquina"] = maquinas.has(jugador["posicion"])
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
