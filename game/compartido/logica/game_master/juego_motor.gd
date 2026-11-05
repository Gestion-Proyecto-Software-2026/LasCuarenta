extends Controlador_juego_Base
class_name Juego_Motor
## Lleva por red cualquier juego cuyas reglas estén en un motor ([MotorDeJuego]):
## los 6 modos, Guiñote, Tute y Mus a 2 y a 4 ([MotorGuinote], [MotorTute],
## [MotorTuteDos], [MotorMus]).
##
## Como en el resto del prototipo, el servidor no juega: recibe las jugadas de
## los clientes, se las pasa al motor y, si son válidas, manda a cada jugador lo
## que ve ahora (su "vista") y lo que puede hacer. La mesa se limita a pintarlo.

signal aviso_emitido(texto: String)
signal partida_terminada(texto: String)

const NOMBRES := {"guinote": "Guiñote", "tute": "Tute", "tute_dos": "Tute", "mus": "Mus"}
## En el Mus, al acabar cada mano se enseñan las cartas este tiempo (por pausa_baza).
const FACTOR_PAUSA_MANO := 2.5

## Qué se juega: "guinote", "tute", "tute_dos" o "mus". Lo elige la escena de partida.
var juego: String = "guinote"
## Segundos que la baza completa se queda a la vista antes de recogerla.
var pausa_baza: float = 2.0
## Con una semilla (>= 0) el reparto sale siempre igual. -1 = al azar.
var semilla: int = -1

var motor: MotorDeJuego
var estado: EstadoPartida
var _tapete: Node


func _ready() -> void:
	_tapete = get_node_or_null("../Tapete")


func _crear_motor() -> MotorDeJuego:
	var rng := RandomNumberGenerator.new()
	if semilla >= 0:
		rng.seed = semilla
	else:
		rng.randomize()
	match juego:
		"tute":
			return MotorTute.new(rng)
		"tute_dos":
			return MotorTuteDos.new(rng)
		"mus":
			return MotorMus.new(rng)
	return MotorGuinote.new(rng)


# --- FLUJO PRINCIPAL (solo en el servidor) ---

func _iniciar_juego() -> void:
	if not multiplayer.is_server():
		return
	motor = _crear_motor()
	estado = motor.iniciar(jugadores.size())
	if estado == null:
		return
	juego_en_curso = true
	acciones_bloqueadas = false
	var peers: Array = []
	var nombres: Array = []
	for jugador in jugadores:
		peers.append(jugador.peer_id)
		nombres.append(jugador.nombre)
	var vista := motor.vista_para_jugador(estado, 0)
	# En el Mus no hay pinta, y en vez de quién reparte importa quién es mano.
	var dador: int = vista["mano"] if juego == "mus" else vista["dador"]
	if _tapete:
		_tapete.rpc("configurar_mesa", peers, nombres, vista.get("pinta", ""), peers[dador],
			{"mazo": juego != "tute", "juego": juego})
	if juego == "mus":
		_avisar_todos("Empieza el Mus. Es mano %s." % jugadores[dador].nombre)
	else:
		_avisar_todos("Empieza el %s. Triunfo: %s. Reparte %s." % [
			NOMBRES.get(juego, juego), vista.get("palo_triunfo", "?"), jugadores[dador].nombre])
	_enviar_estado()


## A cada jugador, lo que ve y lo que puede hacer.
func _enviar_estado() -> void:
	for asiento in jugadores.size():
		_enviar_estado_a(asiento)


func _enviar_estado_a(asiento: int) -> void:
	if _tapete:
		_tapete.rpc_id(jugadores[asiento].peer_id, "actualizar_vista",
			motor.vista_para_jugador(estado, asiento), motor.jugadas_validas(estado, asiento))


# --- COMUNICACIÓN CLIENTE -> SERVIDOR ---

## La mesa llama a esto al soltar una carta en el centro.
@rpc("any_peer", "call_remote", "reliable")
func intentar_jugar_carta(id_carta: String) -> void:
	_recibir_jugada({"tipo": MotorDeJuego.JUGAR_CARTA, "carta_id": id_carta})


## Cualquier otra jugada: cantar, cambiar la pinta, capote...
@rpc("any_peer", "call_remote", "reliable")
func enviar_jugada(jugada: Dictionary) -> void:
	_recibir_jugada(jugada)


func _recibir_jugada(jugada: Dictionary) -> void:
	if not multiplayer.is_server() or not juego_en_curso:
		return
	var peer := multiplayer.get_remote_sender_id()
	var asiento := _asiento_de(peer)
	if asiento == -1:
		return
	if acciones_bloqueadas:
		_rechazar(asiento, jugada, "Espera a que se recoja la baza.")
		return
	var resultado := motor.aplicar_jugada(estado, asiento, jugada)
	if not resultado.ok:
		var motivo := resultado.error
		# Con una carta que no vale, mejor decir qué obliga (asistir, montar, fallar...).
		if jugada.get("tipo") == MotorDeJuego.JUGAR_CARTA and motor.has_method("motivo_carta_no_valida"):
			var explicacion: String = motor.call("motivo_carta_no_valida", estado, asiento, str(jugada.get("carta_id", "")))
			if explicacion != "":
				motivo = explicacion
		_rechazar(asiento, jugada, motivo)
		return
	var anterior := estado
	estado = resultado.estado
	if jugada["tipo"] == MotorDeJuego.JUGAR_CARTA:
		rpc("carta_jugada_en_mesa", peer, jugada["carta_id"])
		if _baza_recien_cerrada():
			await _recoger_baza(anterior, asiento, jugada["carta_id"])
	else:
		_anunciar(asiento, jugada, anterior)
	if juego == "mus":
		if estado.get("ultima_mano") != anterior.get("ultima_mano"):
			await _ensenar_mano_de_mus()
	elif estado.get("mano_actual") != anterior.get("mano_actual"):
		_anunciar_vuelta()
	# Durante la pausa se ha podido cancelar la partida (se ha ido alguien).
	if not juego_en_curso:
		return
	_enviar_estado()
	if motor.ha_terminado(estado):
		_terminar()


func _rechazar(asiento: int, jugada: Dictionary, motivo: String) -> void:
	var peer := jugadores[asiento].peer_id
	if jugada.get("tipo") == MotorDeJuego.JUGAR_CARTA:
		rpc_id(peer, "jugada_rechazada", jugada.get("carta_id", ""))
	if _tapete:
		_tapete.rpc_id(peer, "avisar_error", motivo)
	if not acciones_bloqueadas:
		_enviar_estado_a(asiento)


## Tras echar una carta, la baza está vacía si esa carta la ha cerrado.
func _baza_recien_cerrada() -> bool:
	return "baza_actual" in estado and (estado.get("baza_actual") as Array).is_empty()


## Deja la baza completa a la vista un rato antes de recogerla. El ganador se
## calcula con la baza de antes de la última carta: si era la última de las
## idas, el estado nuevo ya es la vuelta recién repartida.
func _recoger_baza(anterior: EstadoPartida, asiento: int, carta: String) -> void:
	acciones_bloqueadas = true
	var baza: Array[Dictionary] = []
	baza.assign(anterior.get("baza_actual"))
	baza.append({"jugador_id": asiento, "carta": carta})
	var ganador: int = motor.call("ganador_de_baza", baza, anterior.get("palo_triunfo"))
	_avisar_todos("Baza para %s." % jugadores[ganador].nombre)
	rpc("sincronizar_turno", -1)  # mientras se ve la baza no le toca a nadie
	await get_tree().create_timer(pausa_baza).timeout
	acciones_bloqueadas = false


## Al acabar una mano de Mus todos enseñan las cartas y se cobra: se deja a la
## vista un rato antes de repartir la siguiente.
func _ensenar_mano_de_mus() -> void:
	acciones_bloqueadas = true
	var ultima: Dictionary = motor.vista_para_jugador(estado, 0)["ultima_mano"]
	var piedras: Array = estado.get("piedras")
	_avisar_todos("Fin de la mano. Piedras: %d - %d. Juegos: %d - %d." % [
		piedras[0], piedras[1], estado.get("juegos")[0], estado.get("juegos")[1]])
	if _tapete:
		_tapete.rpc("mostrar_fin_de_mano", ultima)
	await get_tree().create_timer(pausa_baza * FACTOR_PAUSA_MANO).timeout
	acciones_bloqueadas = false


func _anunciar(asiento: int, jugada: Dictionary, anterior: EstadoPartida) -> void:
	var texto := ""
	match jugada["tipo"]:
		MotorDeJuego.CANTAR:
			var en_triunfo: bool = jugada["palo"] == Cartas.nombre_palo(estado.get("palo_triunfo"))
			texto = "¡Las 40!" if en_triunfo else "Las 20 en %s" % jugada["palo"]
		MotorDeJuego.CANTAR_TUTE:
			texto = "¡Tute de %s!" % jugada["figura"]
		MotorDeJuego.CAMBIAR_SIETE:
			texto = "Cambio la pinta"
		MotorDeJuego.NO_CAMBIAR_SIETE:
			texto = "No cambio la pinta"
		MotorDeJuego.CAPOTE:
			texto = "¡Capote!"
		MotorDeJuego.MUS:
			texto = "Mus"
		MotorDeJuego.NO_MUS:
			texto = "No hay mus"
		MotorDeJuego.DESCARTAR:
			var cuantas: int = jugada["cartas"].size()
			texto = "Me descarto de %s" % ("una" if cuantas == 1 else str(cuantas))
		MotorDeJuego.PASAR:
			texto = "Paso"
		MotorDeJuego.ENVIDAR:
			var habia_envite: bool = not (anterior.get("envite") as Dictionary).is_empty()
			texto = ("Subo %d" if habia_envite else "Envido %d") % jugada["cantidad"]
		MotorDeJuego.ORDAGO:
			texto = "¡Órdago!"
		MotorDeJuego.QUIERO:
			texto = "Quiero"
		MotorDeJuego.NO_QUIERO:
			texto = "No quiero"
		_:
			texto = jugada["tipo"]
	_avisar_todos("%s: %s" % [jugadores[asiento].nombre, texto])
	if _tapete:
		_tapete.rpc("anunciar", jugadores[asiento].peer_id, texto)


## Nadie ha pasado de 100 en las idas: se reparte otra vez y el tanteo sigue.
func _anunciar_vuelta() -> void:
	var total: Array = estado.get("tanteo_idas")["total"]
	var texto := "Nadie pasa de 100: ¡vuelta! Idas %d - %d" % [total[0], total[1]]
	_avisar_todos(texto)
	if _tapete:
		_tapete.rpc("anunciar", -1, texto)
		_tapete.rpc("actualizar_marcador", "Idas: %s %d · %s %d" % [
			_nombre_equipo(0), total[0], _nombre_equipo(1), total[1]])


# --- FIN DE LA PARTIDA ---

const MOTIVOS := {
	"tantos": "por tantos al acabar las idas",
	"vuelta": "en la vuelta",
	"tute": "cantando Tute",
	"capote": "por capote",
}


func _terminar() -> void:
	juego_en_curso = false
	acciones_bloqueadas = true
	if juego == "mus":
		_terminar_mus()
		return
	var r := motor.calcular_resultado(estado)
	var ganador: int = r["equipo_ganador"]
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	lineas.append("Gana %s %s." % [_nombre_equipo(ganador), MOTIVOS.get(r["motivo"], r["motivo"])])
	var manos: Array = r["manos"]
	for i in manos.size():
		var t: Dictionary = manos[i]
		var titulo := "Tanteo" if juego == "tute" else ("Idas" if i == 0 else "Vuelta")
		lineas.append("%s:" % titulo)
		for equipo in 2:
			lineas.append("  %s: %d = cartas %d + cantes %d + últimas %d" % [
				_nombre_equipo(equipo), t["total"][equipo], t["cartas"][equipo],
				t["cantes"][equipo], t["diez_ultimas"][equipo]])
	var total: Array = r["puntos_por_equipo"]
	if manos.size() > 1:
		lineas.append("Total: %d - %d" % [total[0], total[1]])
	var texto := "\n".join(lineas)
	if _tapete:
		_tapete.rpc("mostrar_resultado", texto)
	var idas: Dictionary = manos[0]
	print("FIN %s | jugadores=%d | ganador=%s | motivo=%s | idas_cartas=%d-%d | total=%d-%d | manos=%d" % [
		NOMBRES.get(juego, juego).to_upper(), jugadores.size(), "AB"[ganador], r["motivo"],
		idas["cartas"][0], idas["cartas"][1], total[0], total[1], manos.size()])
	aviso_emitido.emit(texto)
	partida_terminada.emit(texto)


## Mus: la partida es al mejor de 3 juegos, y cada juego, a 40 piedras.
func _terminar_mus() -> void:
	var r := motor.calcular_resultado(estado)
	var ganador: int = r["equipo_ganador"]
	var juegos: Array = r["puntos_por_equipo"]
	var lineas := PackedStringArray(["FIN DE LA PARTIDA"])
	lineas.append("Gana %s, %d juegos a %d." % [_nombre_equipo(ganador), juegos[ganador], juegos[1 - ganador]])
	var motivos: Array = []
	for i in r["juegos"].size():
		var jugado: Dictionary = r["juegos"][i]
		motivos.append(jugado["motivo"])
		lineas.append("Juego %d: %s (%d - %d piedras%s)" % [
			i + 1, _nombre_equipo(jugado["equipo"]), jugado["piedras"][0], jugado["piedras"][1],
			", por órdago" if jugado["motivo"] == "ordago" else ""])
	var texto := "\n".join(lineas)
	if _tapete:
		_tapete.rpc("mostrar_resultado", texto)
	print("FIN MUS | jugadores=%d | ganador=%s | juegos=%d-%d | motivos=%s" % [
		jugadores.size(), "AB"[ganador], juegos[0], juegos[1], ",".join(motivos)])
	aviso_emitido.emit(texto)
	partida_terminada.emit(texto)


## "Jugador 1" en la mesa de 2; "la pareja A (Jugador 1 y Jugador 3)" en la de 4.
func _nombre_equipo(equipo: int) -> String:
	if jugadores.size() == 2:
		return jugadores[equipo].nombre
	return "la pareja %s (%s y %s)" % ["AB"[equipo], jugadores[equipo].nombre, jugadores[equipo + 2].nombre]


# --- HELPERS ---

func _asiento_de(peer_id: int) -> int:
	for asiento in jugadores.size():
		if jugadores[asiento].peer_id == peer_id:
			return asiento
	return -1


func _avisar_todos(texto: String) -> void:
	print("[%s] %s" % [NOMBRES.get(juego, juego).to_upper(), texto])
	if _tapete:
		_tapete.rpc("mostrar_aviso", texto)
	aviso_emitido.emit(texto)
