extends MotorDeJuego
## Juego mínimo, solo para probar la clase base: cada jugador recibe 2 cartas y,
## por turnos, las va jugando. Cada carta suma su valor a su equipo.


class Estado:
	extends EstadoPartida
	var manos: Array = []  # manos[jugador_id] = Array[Carta]
	var turno: int = 0
	var puntos: Array[int] = [0, 0]


const CARTAS_POR_JUGADOR := 2


func jugadores_admitidos() -> Array[int]:
	return [2, 4]


func _iniciar(num_jugadores: int) -> EstadoPartida:
	var cartas := Baraja.crear()
	Baraja.barajar(cartas, rng)
	var estado := Estado.new()
	for i in num_jugadores:
		estado.manos.append(cartas.slice(i * CARTAS_POR_JUGADOR, (i + 1) * CARTAS_POR_JUGADOR))
	return estado


func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]:
	var e := estado as Estado
	var validas: Array[Dictionary] = []
	if ha_terminado(e) or jugador_id != e.turno:
		return validas
	for carta: Carta in e.manos[jugador_id]:
		validas.append({"tipo": "jugar_carta", "carta_id": carta.id})
	return validas


func _ejecutar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> void:
	var e := estado as Estado
	var mano: Array = e.manos[jugador_id]
	for i in mano.size():
		if mano[i].id == jugada["carta_id"]:
			e.puntos[equipo_de(jugador_id)] += mano[i].valor
			mano.remove_at(i)
			break
	e.turno = (e.turno + 1) % e.num_jugadores


func ha_terminado(estado: EstadoPartida) -> bool:
	return (estado as Estado).manos.all(func(mano: Array) -> bool: return mano.is_empty())


func calcular_resultado(estado: EstadoPartida) -> Dictionary:
	var e := estado as Estado
	return {
		"equipo_ganador": 0 if e.puntos[0] >= e.puntos[1] else 1,
		"puntos_por_equipo": e.puntos.duplicate(),
	}


func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
	var e := estado as Estado
	var mi_mano: Array[String] = []
	for carta: Carta in e.manos[jugador_id]:
		mi_mano.append(carta.id)
	var cartas_por_jugador: Array[int] = []
	for mano: Array in e.manos:
		cartas_por_jugador.append(mano.size())
	return {"turno": e.turno, "mi_mano": mi_mano, "cartas_por_jugador": cartas_por_jugador}
