extends RefCounted
## Jugadas especiales de Guiñote (cantar, cantar_tute, cambiar_siete...),
## compartido entre la pantalla de 4 jugadores (partida.gd) y la de 2
## (partida_guinote_2p/partida_guinote_2p.gd): agrupa `jugadas_validas` por
## tipo+campos para no repetir un botón por cada carta de la mano que permite
## el mismo cante, y da el texto de cada una.
## Sin `class_name` a propósito: se referencia con `preload()` (ver partida.gd)
## para no depender de que el caché de clases globales de Godot se haya
## regenerado (p. ej. en GUT headless, que no pasa por el editor).

static func jugadas_especiales(jugadas_validas: Array) -> Array[Dictionary]:
	var vistas: Array[Dictionary] = []
	for jugada: Dictionary in jugadas_validas:
		if jugada.get("tipo") == MensajesRed.JUGAR_CARTA or jugada in vistas:
			continue
		vistas.append(jugada)
	return vistas


static func texto(jugada: Dictionary) -> String:
	match jugada.get("tipo"):
		MensajesRed.CANTAR:
			return "Cantar %s" % jugada.get("palo", "")
		MensajesRed.CANTAR_TUTE:
			return "Cantar tute de %s" % jugada.get("figura", "")
		MensajesRed.CAMBIAR_SIETE:
			return "Cambiar el 7"
		MensajesRed.NO_CAMBIAR_SIETE:
			return "No cambiar el 7"
		_:
			return jugada.get("tipo", "")
