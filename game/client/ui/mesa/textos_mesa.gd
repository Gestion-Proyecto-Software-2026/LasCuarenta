extends RefCounted
## Los textos de la mesa común que se sacan de lo que manda el servidor: lo que
## dice un jugador al hacer una jugada ("¡Las 40!", "Envido 2"...) y el panel
## del resultado final. Son los mismos textos del prototipo unificado; allí los
## escribía el servidor y aquí el cliente, porque el servidor de partida solo
## manda datos (estado, última jugada y resultado).

const MOTIVOS := {
	"tantos": "por tantos al acabar las idas",
	"vuelta": "en la vuelta",
	"tute": "cantando Tute",
	"capote": "por capote",
}


## Lo que dice en voz alta quien hace [param jugada] (la `ultima_jugada` del
## estado). [param vista_anterior] es la vista de antes de esa jugada y
## [param vista] la de después. "" si no hay nada que decir (echar una carta).
static func anuncio(jugada: Dictionary, vista_anterior: Dictionary, vista: Dictionary) -> String:
	match jugada.get("tipo", ""):
		MensajesRed.JUGAR_CARTA:
			return ""
		MensajesRed.CANTAR:
			var en_triunfo: bool = jugada.get("palo") == vista.get("palo_triunfo")
			return "¡Las 40!" if en_triunfo else "Las 20 en %s" % jugada.get("palo", "?")
		MensajesRed.CANTAR_TUTE:
			return "¡Tute de %s!" % jugada.get("figura", "?")
		MensajesRed.CAMBIAR_SIETE:
			return "Cambio la pinta"
		MensajesRed.NO_CAMBIAR_SIETE:
			return "No cambio la pinta"
		MensajesRed.CAPOTE:
			return "¡Capote!"
		MensajesRed.MUS:
			return "Mus"
		MensajesRed.NO_MUS:
			return "No hay mus"
		MensajesRed.DESCARTAR:
			var cuantas: int = jugada.get("num_cartas", 0)
			return "Me descarto de %s" % ("una" if cuantas == 1 else str(cuantas))
		MensajesRed.PASAR:
			return "Paso"
		MensajesRed.ENVIDAR:
			var habia_envite: bool = not (vista_anterior.get("envite", {}) as Dictionary).is_empty()
			return ("Subo %d" if habia_envite else "Envido %d") % jugada.get("cantidad", 0)
		MensajesRed.ORDAGO:
			return "¡Órdago!"
		MensajesRed.QUIERO:
			return "Quiero"
		MensajesRed.NO_QUIERO:
			return "No quiero"
	return str(jugada.get("tipo", ""))


## Nadie ha pasado de 100 en las idas: se reparte otra vez y el tanteo sigue.
static func anuncio_vuelta(vista: Dictionary) -> String:
	var total: Array = vista.get("tanteo_idas", [])
	if total.size() != 2:
		return "Nadie pasa de 100: ¡vuelta!"
	return "Nadie pasa de 100: ¡vuelta! Idas %d - %d" % [total[0], total[1]]


## El marcador de las idas, que sale en el resultado final.
static func marcador_idas(vista: Dictionary, nombres: Array) -> String:
	var total: Array = vista.get("tanteo_idas", [])
	if total.size() != 2:
		return ""
	return "Idas: %s %d · %s %d" % [nombre_equipo(0, nombres), total[0], nombre_equipo(1, nombres), total[1]]


## El panel de fin de partida. [param juego] es el de la mesa ("guinote",
## "tute", "tute_dos" o "mus") y [param nombres], el de cada asiento.
static func resultado(juego: String, r: Dictionary, nombres: Array) -> String:
	if r.get("causa") == "renuncio":
		return _resultado_renuncio(juego, r, nombres)
	if juego == "mus":
		return _resultado_mus(r, nombres)
	var ganador: int = r.get("equipo_ganador", -1)
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	var motivo: String = str(r.get("motivo", ""))
	lineas.append("Gana %s %s." % [nombre_equipo(ganador, nombres), MOTIVOS.get(motivo, motivo)])
	var manos: Array = r.get("manos", [])
	for i in manos.size():
		var t: Dictionary = manos[i]
		var titulo := "Tanteo" if juego == "tute" else ("Idas" if i == 0 else "Vuelta")
		lineas.append("%s:" % titulo)
		for equipo in 2:
			lineas.append("  %s: %d = cartas %d + cantes %d + últimas %d" % [
				nombre_equipo(equipo, nombres), t["total"][equipo], t["cartas"][equipo],
				t["cantes"][equipo], t["diez_ultimas"][equipo]])
	var total: Array = r.get("puntos_por_equipo", [])
	if manos.size() > 1 and total.size() == 2:
		lineas.append("Total: %d - %d" % [total[0], total[1]])
	return "\n".join(lineas)


## Partida cortada por un renuncio admitido en el chat (PBI-08): gana la parte
## perjudicada y se enseña el marcador que había en ese momento (en el Mus, los
## juegos ganados; en el resto, los tantos).
static func _resultado_renuncio(juego: String, r: Dictionary, nombres: Array) -> String:
	var ganador: int = r.get("equipo_ganador", -1)
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	if ganador in [0, 1]:
		lineas.append("Gana %s por renuncio: %s admitió haber revelado información por el chat." % [
			nombre_equipo(ganador, nombres), nombre_equipo(1 - ganador, nombres)])
	var puntos: Array = r.get("puntos_por_equipo", [])
	if puntos.size() == 2:
		lineas.append("Marcador en ese momento: %s %d · %s %d%s" % [
			nombre_equipo(0, nombres), puntos[0], nombre_equipo(1, nombres), puntos[1],
			" juegos" if juego == "mus" else ""])
	return "\n".join(lineas)


## Mus: la partida es al mejor de 3 juegos, y cada juego, a 40 piedras.
static func _resultado_mus(r: Dictionary, nombres: Array) -> String:
	var ganador: int = r.get("equipo_ganador", -1)
	var juegos: Array = r.get("puntos_por_equipo", [0, 0])
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	if ganador in [0, 1] and juegos.size() == 2:
		lineas.append("Gana %s, %d juegos a %d." % [nombre_equipo(ganador, nombres), juegos[ganador], juegos[1 - ganador]])
	var jugados: Array = r.get("juegos", [])
	for i in jugados.size():
		var jugado: Dictionary = jugados[i]
		lineas.append("Juego %d: %s (%d - %d piedras%s)" % [
			i + 1, nombre_equipo(jugado["equipo"], nombres), jugado["piedras"][0], jugado["piedras"][1],
			", por órdago" if jugado["motivo"] == "ordago" else ""])
	return "\n".join(lineas)


## "Ana" en la mesa de 2; "la pareja A (Ana y Luis)" en la de 4.
static func nombre_equipo(equipo: int, nombres: Array) -> String:
	if equipo < 0 or equipo > 1:
		return "nadie"
	if nombres.size() == 2:
		return nombre_jugador(equipo, nombres)
	return "la pareja %s (%s y %s)" % ["AB"[equipo], nombre_jugador(equipo, nombres), nombre_jugador(equipo + 2, nombres)]


## El nombre del asiento, o "Jugador N" si no se sabe.
static func nombre_jugador(asiento: int, nombres: Array) -> String:
	var nombre := str(nombres[asiento]) if asiento >= 0 and asiento < nombres.size() else ""
	return nombre if nombre != "" else "Jugador %d" % (asiento + 1)
