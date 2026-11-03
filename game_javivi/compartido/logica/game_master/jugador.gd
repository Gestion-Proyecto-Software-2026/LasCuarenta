extends RefCounted
class_name Jugador

var peer_id : int 
var nombre : String
var mano : Array[Carta] = []
var cartas_ganadas : Array[Carta] = [] # NUEVO: Guardará las cartas de las bazas ganadas
var cantes_pendientes: Array = [] 
var puede_cambiar_triunfo_pendiente: bool = false
var puntos_cantes: int = 0
var esperando_decision_antes_de_robar: bool = false

func _init(_peer_id: int, _nombre: String):
	peer_id = _peer_id
	nombre = _nombre

func recibir_carta(carta: Carta) -> void:
	mano.append(carta)

func quitar_carta(carta: Carta) -> void:
	mano.erase(carta)

func obtener_carta_por_id(id_carta: String) -> Carta:
	for c in mano:
		if c.id == id_carta:
			return c
	return null

func vaciar_mano() -> void:
	mano.clear()
	cartas_ganadas.clear()
	cantes_pendientes.clear()
	puede_cambiar_triunfo_pendiente = false
	puntos_cantes = 0
