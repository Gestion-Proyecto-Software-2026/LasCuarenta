class_name RoomManager
extends Node
## Aloja las salas del servidor de partida y traduce entre los mensajes del
## protocolo y los motores de reglas (analisis_funcional_app.md §6 y §7).
##
## No sabe nada de ENet ni de las reglas de ningún juego: recibe mensajes ya
## deserializados con [method recibir] y responde emitiendo [signal mensaje_para]
## y [signal expulsar], que main_server.gd conecta a la red. Los juegos se le
## pasan en el constructor ([code]{ "guinote": MotorGuinote, ... }[/code]), así
## que añadir un juego no toca este fichero.

## Mensaje de salida hacia un cliente.
signal mensaje_para(peer_id: int, mensaje: Dictionary)
## El cliente debe desconectarse (token no válido, sala inexistente...). Siempre
## va precedido de un mensaje [code]error[/code] explicando el motivo.
signal expulsar(peer_id: int)

const ESTADOS_SALA_JUGABLES := ["esperando", "en_curso"]

## sala_id -> SalaActiva
var salas_activas: Dictionary = {}

var _backend: Node
var _jwt_secret: String
var _motores: Dictionary
var _peers_conectados: Dictionary = {}  # peer_id -> true
var _sala_de_peer: Dictionary = {}  # peer_id -> sala_id
var _consultas_en_curso: Dictionary = {}  # sala_id -> _Consulta
var _uuid := RegEx.create_from_string(
	"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


## Consulta al backend compartida por todos los que se unen a la misma sala
## mientras la respuesta no ha llegado, para no pedirla varias veces.
class _Consulta:
	signal terminada
	var respuesta: Dictionary


## [param backend] es un [ClienteBackend] (o un doble en los tests);
## [param motores] asocia el nombre del juego (como lo devuelve el backend) al
## script de su [MotorDeJuego].
func _init(backend: Node, jwt_secret: String, motores: Dictionary) -> void:
	_backend = backend
	_jwt_secret = jwt_secret
	_motores = motores


func conectar(peer_id: int) -> void:
	_peers_conectados[peer_id] = true


## El asiento queda libre para que el mismo usuario pueda reconectarse con
## otra conexión; la partida no se cancela.
func desconectar(peer_id: int) -> void:
	_peers_conectados.erase(peer_id)
	var sala := _sala_del_peer(peer_id)
	if sala != null:
		sala.peer_en_posicion.erase(sala.posicion_de_peer(peer_id))
	_sala_de_peer.erase(peer_id)


func recibir(peer_id: int, mensaje: Dictionary) -> void:
	var tipo: Variant = mensaje.get("tipo")
	var payload: Variant = mensaje.get("payload", {})
	if not tipo is String or not payload is Dictionary:
		_enviar_error(peer_id, "Mensaje mal formado: se espera { tipo, payload }")
		return
	match tipo:
		MensajesRed.UNIRSE_PARTIDA:
			_unirse(peer_id, payload)
		MensajesRed.CHAT_ENVIAR:
			_enviar_error(peer_id, "El chat todavía no está disponible")
		_:
			_jugar(peer_id, tipo, payload)


func _unirse(peer_id: int, payload: Dictionary) -> void:
	if _sala_de_peer.has(peer_id):
		_enviar_error(peer_id, "Ya estás en una partida")
		return
	var usuario_id: Variant = payload.get("usuario_id")
	var token: Variant = payload.get("token")
	var sala_id: Variant = payload.get("sala_id")
	if not (usuario_id is String and token is String and sala_id is String) \
			or usuario_id.is_empty() or _uuid.search(sala_id) == null:
		_rechazar(peer_id, "unirse_partida necesita usuario_id, token y un sala_id válido")
		return
	var datos_token := VerificadorJwt.verificar(token, _jwt_secret)
	if datos_token.is_empty() or str(datos_token.get("id", "")) != usuario_id:
		_rechazar(peer_id, "Token no válido o caducado")
		return

	var carga := await _cargar_sala(sala_id)
	# Mientras se consultaba al backend, el cliente pudo desconectarse o unirse por otra vía.
	if not _peers_conectados.has(peer_id):
		return
	if _sala_de_peer.has(peer_id):
		_enviar_error(peer_id, "Ya estás en una partida")
		return
	if carga["sala"] == null:
		_rechazar(peer_id, carga["error"])
		return

	var sala: SalaActiva = carga["sala"]
	if not sala.posicion_de_usuario.has(usuario_id):
		_rechazar(peer_id, "No eres participante de esta sala")
		return
	var posicion: int = sala.posicion_de_usuario[usuario_id]
	var peer_anterior: int = sala.peer_en_posicion.get(posicion, -1)
	if peer_anterior != -1 and peer_anterior != peer_id:
		_sala_de_peer.erase(peer_anterior)
		_rechazar(peer_anterior, "Te has conectado a esta partida desde otra sesión")
	sala.peer_en_posicion[posicion] = peer_id
	_sala_de_peer[peer_id] = sala.sala_id

	if sala.empezada():
		# Reconexión: se le pone al día solo a él.
		_enviar_inicio(sala, posicion)
		_enviar_estado(sala, posicion)
	elif sala.todos_conectados():
		_empezar(sala)


## Devuelve [code]{ "sala": SalaActiva, "error": "" }[/code], o
## [code]{ "sala": null, "error": motivo }[/code].
func _cargar_sala(sala_id: String) -> Dictionary:
	if salas_activas.has(sala_id):
		return {"sala": salas_activas[sala_id], "error": ""}

	var respuesta: Dictionary
	if _consultas_en_curso.has(sala_id):
		var consulta: _Consulta = _consultas_en_curso[sala_id]
		await consulta.terminada
		respuesta = consulta.respuesta
	else:
		var consulta := _Consulta.new()
		_consultas_en_curso[sala_id] = consulta
		respuesta = await _backend.obtener_sala(sala_id)
		_consultas_en_curso.erase(sala_id)
		consulta.respuesta = respuesta
		consulta.terminada.emit()

	# Otro jugador que esperaba la misma consulta puede haberla creado ya.
	if salas_activas.has(sala_id):
		return {"sala": salas_activas[sala_id], "error": ""}
	if respuesta.get("codigo") == 404:
		return {"sala": null, "error": "La sala no existe"}
	if not respuesta.get("ok", false) or not respuesta.get("datos") is Dictionary:
		return {"sala": null, "error": "No se pudo consultar la sala; inténtalo de nuevo"}

	var creada: Variant = _crear_sala(sala_id, respuesta["datos"])
	if creada is String:
		return {"sala": null, "error": creada}
	salas_activas[sala_id] = creada
	return {"sala": creada, "error": ""}


## Construye la sala a partir de la respuesta de GET /interno/salas/:id.
## Devuelve la [SalaActiva] o un String con el motivo por el que no es válida.
func _crear_sala(sala_id: String, datos: Dictionary) -> Variant:
	if datos.get("estado") not in ESTADOS_SALA_JUGABLES:
		return "La sala ya ha terminado"
	var script: Variant = _motores.get(datos.get("juego"))
	if script == null:
		return "Este juego todavía no está disponible"

	var sala := SalaActiva.new()
	sala.sala_id = sala_id
	sala.juego = datos["juego"]
	sala.motor = script.new()
	var capacidad: Variant = datos.get("capacidad")
	if not (capacidad is float or capacidad is int) or int(capacidad) not in sala.motor.jugadores_admitidos():
		return "La sala no tiene un número de jugadores válido para este juego"
	sala.capacidad = int(capacidad)

	var participantes: Variant = datos.get("participantes")
	if not participantes is Array:
		return "La sala no tiene participantes"
	for participante: Variant in participantes:
		if not participante is Dictionary:
			return "Participantes de la sala mal formados"
		var usuario_id: Variant = participante.get("usuario_id")
		var posicion: Variant = participante.get("posicion")
		if not usuario_id is String or not (posicion is float or posicion is int) \
				or int(posicion) < 0 or int(posicion) >= sala.capacidad \
				or sala.usuario_en_posicion.has(int(posicion)) or sala.posicion_de_usuario.has(usuario_id):
			return "Participantes de la sala mal formados"
		sala.posicion_de_usuario[usuario_id] = int(posicion)
		sala.usuario_en_posicion[int(posicion)] = usuario_id
	return sala


func _empezar(sala: SalaActiva) -> void:
	sala.estado = sala.motor.iniciar(sala.capacidad)
	for posicion: int in sala.peer_en_posicion:
		_enviar_inicio(sala, posicion)
		_enviar_estado(sala, posicion)


func _jugar(peer_id: int, tipo: String, payload: Dictionary) -> void:
	var sala := _sala_del_peer(peer_id)
	if sala == null:
		_enviar_error(peer_id, "Primero tienes que unirte a una partida")
		return
	if not sala.empezada():
		_enviar_error(peer_id, "La partida todavía no ha empezado")
		return

	var jugada := {"tipo": tipo}
	jugada.merge(payload)  # sin sobrescribir: un "tipo" dentro del payload no cuenta
	var resultado := sala.motor.aplicar_jugada(sala.estado, sala.posicion_de_peer(peer_id), jugada)
	if not resultado.ok:
		_enviar_error(peer_id, resultado.error)
		return

	sala.estado = resultado.estado
	for posicion: int in sala.peer_en_posicion:
		_enviar_estado(sala, posicion)
	if sala.motor.ha_terminado(sala.estado):
		_terminar(sala)


func _terminar(sala: SalaActiva) -> void:
	var resultado := sala.motor.calcular_resultado(sala.estado)
	for posicion: int in sala.peer_en_posicion:
		_enviar(sala.peer_en_posicion[posicion], MensajesRed.PARTIDA_TERMINADA, {"resultado": resultado})
		_sala_de_peer.erase(sala.peer_en_posicion[posicion])
	salas_activas.erase(sala.sala_id)

	var respuesta: Dictionary = await _backend.registrar_partida({
		"sala_id": sala.sala_id,
		"jugadores": sala.jugadores(),
		"resultado": resultado,
	})
	if not respuesta.get("ok", false):
		push_error("No se pudo registrar el resultado de la sala %s en el backend (código %s)"
			% [sala.sala_id, respuesta.get("codigo")])


func _enviar_inicio(sala: SalaActiva, posicion: int) -> void:
	_enviar(sala.peer_en_posicion[posicion], MensajesRed.PARTIDA_INICIADA, {"config": {
		"sala_id": sala.sala_id,
		"juego": sala.juego,
		"tu_posicion": posicion,
		"jugadores": sala.jugadores(),
	}})


func _enviar_estado(sala: SalaActiva, posicion: int) -> void:
	_enviar(sala.peer_en_posicion[posicion], MensajesRed.ESTADO_PARTIDA,
		sala.motor.vista_para_jugador(sala.estado, posicion))


func _sala_del_peer(peer_id: int) -> SalaActiva:
	return salas_activas.get(_sala_de_peer.get(peer_id, ""))


func _enviar(peer_id: int, tipo: String, payload: Dictionary) -> void:
	mensaje_para.emit(peer_id, MensajesRed.crear(tipo, payload))


func _enviar_error(peer_id: int, texto: String) -> void:
	_enviar(peer_id, MensajesRed.ERROR, {"mensaje": texto})


func _rechazar(peer_id: int, texto: String) -> void:
	_enviar_error(peer_id, texto)
	expulsar.emit(peer_id)
