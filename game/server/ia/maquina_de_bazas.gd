class_name MaquinaDeBazas
extends JugadorMaquina
## La máquina del Guiñote y del Tute (a 2 y a 4): los juegos de bazas con triunfo.
##
## - Fácil: una jugada válida al azar.
## - Normal: cambia el siete, canta, gana la baza con la carta más barata que le
##   sirve y, si no puede ganar, se deshace de la carta que menos vale.
## - Difícil: lo de Normal, y además recuerda las cartas que han salido para
##   saber cuáles son las más altas que quedan, no gasta triunfos en bazas que
##   no valen nada y carga puntos cuando su pareja va ganando.

var _reglas: MotorGuinote
## Ids de las cartas que han salido, para el nivel difícil.
var _salidas := {}


func _init(p_reglas: MotorGuinote, p_dificultad: Dificultad = Dificultad.NORMAL,
		p_rng: RandomNumberGenerator = null) -> void:
	super(p_dificultad, p_rng)
	_reglas = p_reglas


func decidir(vista: Dictionary, validas: Array[Dictionary]) -> Dictionary:
	if validas.is_empty():
		return {}
	_observar(vista)
	if dificultad == Dificultad.FACIL:
		return _al_azar(validas)
	# Cambiar el siete y cantar son siempre buenas ideas.
	for tipo: String in [MensajesRed.CAMBIAR_SIETE, MensajesRed.CANTAR_TUTE]:
		var jugada := _primera(validas, tipo)
		if not jugada.is_empty():
			return jugada
	var cante := _mejor_cante(vista, validas)
	if not cante.is_empty():
		return cante
	var cartas: Array[Dictionary] = []
	for jugada: Dictionary in validas:
		if jugada["tipo"] == MensajesRed.JUGAR_CARTA:
			cartas.append(jugada)
	if cartas.is_empty():
		# Solo queda decidir sobre la pinta: no se cambia (no tiene el siete).
		var no_cambiar := _primera(validas, MensajesRed.NO_CAMBIAR_SIETE)
		return no_cambiar if not no_cambiar.is_empty() else _al_azar(validas)
	return _jugar(vista, cartas)


# --- Elegir carta ---------------------------------------------------------

func _jugar(vista: Dictionary, cartas: Array[Dictionary]) -> Dictionary:
	var triunfo := _palo(vista["palo_triunfo"])
	var mano: Array[Carta] = []
	for jugada: Dictionary in cartas:
		mano.append(Carta.desde_id(jugada["carta_id"]))
	var baza: Array = vista["baza_actual"]
	var elegida: Carta
	if baza.is_empty():
		elegida = _salir(mano, triunfo, vista)
	else:
		elegida = _responder(mano, baza, triunfo, vista)
	for jugada: Dictionary in cartas:
		if jugada["carta_id"] == elegida.id:
			return jugada
	return cartas[0]


## Primera carta de la baza: la más barata que no sea triunfo; el nivel difícil
## prefiere una que sea la más alta que queda de su palo.
func _salir(mano: Array[Carta], triunfo: Carta.Palo, vista: Dictionary) -> Carta:
	if dificultad == Dificultad.DIFICIL and vista["fase"] == "arrastre":
		var maestras := mano.filter(func(c: Carta) -> bool:
			return c.palo != triunfo and _puntos(c) > 0 and _es_la_mas_alta_que_queda(c, mano, vista))
		if not maestras.is_empty():
			return _la_mas_barata(maestras, triunfo)
	return _la_mas_barata(mano, triunfo)


func _responder(mano: Array[Carta], baza: Array, triunfo: Carta.Palo, vista: Dictionary) -> Carta:
	var jugadas: Array[Dictionary] = []
	var puntos_en_baza := 0
	for b: Dictionary in baza:
		var carta := Carta.desde_id(b["carta_id"])
		jugadas.append({"jugador_id": b["jugador_id"], "carta": carta})
		puntos_en_baza += _puntos(carta)
	var yo: int = vista["turno"]
	var ganador := _reglas.ganador_en(jugadas, triunfo)
	var mejor: Carta
	for jugada: Dictionary in jugadas:
		if jugada["jugador_id"] == ganador:
			mejor = jugada["carta"]
	var jugadores: int = (vista["cartas_por_jugador"] as Array).size()
	var soy_el_ultimo := baza.size() == jugadores - 1
	if MotorDeJuego.equipo_de(ganador) == MotorDeJuego.equipo_de(yo):
		# Va ganando mi pareja: no se la quito; si soy el último, le cargo puntos.
		if dificultad == Dificultad.DIFICIL and soy_el_ultimo:
			return _la_que_mas_puntos_da(mano, triunfo)
		return _la_mas_barata(mano, triunfo)
	var ganadoras := mano.filter(func(c: Carta) -> bool: return MotorGuinote.gana_a(c, mejor, triunfo))
	if ganadoras.is_empty():
		return _la_mas_barata(mano, triunfo)
	var sin_triunfo := ganadoras.filter(func(c: Carta) -> bool: return c.palo != triunfo)
	if not sin_triunfo.is_empty():
		return _la_mas_barata(sin_triunfo, triunfo)
	# Solo ganaría con un triunfo: depende de lo que valga la baza.
	var baza_sin_valor: bool = puntos_en_baza == 0 and vista["fase"] == "robo" and vista["cartas_en_mazo"] > 2
	if dificultad == Dificultad.DIFICIL and baza_sin_valor:
		return _la_mas_barata(mano, triunfo)
	return _la_mas_barata(ganadoras, triunfo)


# --- Criterios sobre cartas -----------------------------------------------

func _mejor_cante(vista: Dictionary, validas: Array[Dictionary]) -> Dictionary:
	var elegido := {}
	for jugada: Dictionary in validas:
		if jugada["tipo"] != MensajesRed.CANTAR:
			continue
		if jugada["palo"] == vista["palo_triunfo"]:
			return jugada
		elegido = jugada
	return elegido


## La carta que menos cuesta tirar: primero las que no son triunfo, luego las que
## menos puntos valen y, a igualdad, las más flojas.
func _la_mas_barata(cartas: Array, triunfo: Carta.Palo) -> Carta:
	var mejor: Carta = cartas[0]
	for carta: Carta in cartas:
		if _coste(carta, triunfo) < _coste(mejor, triunfo):
			mejor = carta
	return mejor


func _la_que_mas_puntos_da(cartas: Array, triunfo: Carta.Palo) -> Carta:
	var mejor: Carta = cartas[0]
	for carta: Carta in cartas:
		var mas_puntos := _puntos(carta) > _puntos(mejor)
		var iguales_y_no_triunfo := _puntos(carta) == _puntos(mejor) and carta.palo != triunfo and mejor.palo == triunfo
		if mas_puntos or iguales_y_no_triunfo:
			mejor = carta
	return mejor


func _coste(carta: Carta, triunfo: Carta.Palo) -> int:
	return (1000 if carta.palo == triunfo else 0) + _puntos(carta) * 10 + _fuerza(carta)


func _puntos(carta: Carta) -> int:
	return _reglas.puntos_por_valor().get(carta.valor, 0)


func _fuerza(carta: Carta) -> int:
	var orden := _reglas.orden_de_fuerza()
	return orden.size() - orden.find(carta.valor)


## Si [param carta] es la más alta de su palo entre las que aún no han salido ni
## están en mi mano (así que ninguna otra puede ganármela en ese palo).
func _es_la_mas_alta_que_queda(carta: Carta, mi_mano: Array[Carta], vista: Dictionary) -> bool:
	var propias := {}
	for c: Carta in mi_mano:
		propias[c.id] = true
	for id: String in vista["mi_mano"]:
		propias[id] = true
	for valor: int in Carta.VALORES:
		var otra := Carta.new(carta.palo, valor)
		if _fuerza(otra) > _fuerza(carta) and not _salidas.has(otra.id) and not propias.has(otra.id):
			return false
	return true


## Anota las cartas que han salido, para recordarlas.
func _observar(vista: Dictionary) -> void:
	for b: Dictionary in vista.get("baza_actual", []):
		_salidas[b["carta_id"]] = true
	var ultima: Dictionary = vista.get("ultima_baza", {})
	for b: Dictionary in ultima.get("cartas", []):
		_salidas[b["carta_id"]] = true


static func _palo(nombre: Variant) -> Carta.Palo:
	return Carta.Palo.keys().find(String(nombre).to_upper()) as Carta.Palo
