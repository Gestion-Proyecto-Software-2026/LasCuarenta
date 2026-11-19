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
## Tiempo límite para decidir (PBI-14, issue #37): segundos que tiene cada
## jugador del que depende la partida antes de que el servidor juegue por él.
const SEGUNDOS_POR_TURNO_POR_DEFECTO := 45.0
const AVISO_TIEMPO_AGOTADO := "Se te ha acabado el tiempo: se ha jugado por ti."
## Modo ausente: a quien se le acaba el tiempo [constant TIEMPOS_AGOTADOS_PARA_AUSENTE]
## veces seguidas se le da por ido: el servidor juega por él casi al instante
## hasta que vuelva a jugar él, para no hacer esperar a los demás en cada turno.
const TIEMPOS_AGOTADOS_PARA_AUSENTE := 2
const SEGUNDOS_DE_AUSENTE := 2.0
const AVISO_AUSENTE := "Se te ha dado por ausente: el servidor jugará por ti hasta que vuelvas a jugar tú."
## Registro del resultado en el backend (PBI-06): veces que se intenta
## POST /interno/partidas antes de darlo por perdido. Solo se reintenta si no
## hubo respuesta o el backend falló (5xx); si un intento anterior sí llegó a
## guardarse, el backend contesta 409 y no duplica la partida.
const INTENTOS_REGISTRO := 3
const ERROR_EN_PAUSA := "La partida está en pausa: hay una denuncia de chat pendiente"

## sala_id -> SalaActiva
var salas_activas: Dictionary = {}
## 0 o menos desactiva el tiempo límite.
var segundos_por_turno: float
## Reloj en milisegundos. Los tests lo sustituyen para no tener que esperar.
var reloj: Callable = func() -> int: return Time.get_ticks_msec()
## Fecha y hora actuales en UTC, en ISO 8601 ("2026-11-18T10:24:13Z"): el
## inicio y el fin de la partida que se guardan en el historial. Los tests lo
## sustituyen, igual que [member reloj].
var reloj_fecha: Callable = func() -> String: return Time.get_datetime_string_from_system(true) + "Z"
## Segundos entre un intento de registro y el siguiente. Los tests la ponen a 0
## y entonces se reintenta en el acto, sin esperar a ningún temporizador.
var espera_entre_intentos_s := 2.0

var _backend: Node
var _jwt_secret: String
var _motores: Dictionary
var _peers_conectados: Dictionary = {}  # peer_id -> true
var _sala_de_peer: Dictionary = {}  # peer_id -> sala_id
## Salas cuya partida ya ha terminado pero en las que aún queda alguien
## conectado: se conservan solo para el chat (PBI-08) y se borran, con sus
## mensajes, al irse el último (HU-035, CA-131). sala_id -> SalaActiva
var _salas_terminadas: Dictionary = {}
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
## script de su [MotorDeJuego]; [param p_segundos_por_turno] es el tiempo
## límite para decidir (0 lo desactiva).
func _init(backend: Node, jwt_secret: String, motores: Dictionary,
		p_segundos_por_turno := SEGUNDOS_POR_TURNO_POR_DEFECTO) -> void:
	_backend = backend
	_jwt_secret = jwt_secret
	_motores = motores
	segundos_por_turno = p_segundos_por_turno


func _process(_delta: float) -> void:
	comprobar_tiempos()
	comprobar_denuncias()


func conectar(peer_id: int) -> void:
	_peers_conectados[peer_id] = true


## El asiento queda libre para que el mismo usuario pueda reconectarse con
## otra conexión; la partida no se cancela. Si la partida ya había terminado y
## era el último en irse, la sala se borra y con ella su chat (HU-035, CA-131).
func desconectar(peer_id: int) -> void:
	_peers_conectados.erase(peer_id)
	var sala := _sala_de_chat(peer_id)
	if sala != null:
		sala.peer_en_posicion.erase(sala.posicion_de_peer(peer_id))
		if sala.terminada and sala.peer_en_posicion.is_empty():
			_salas_terminadas.erase(sala.sala_id)
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
			_chatear(peer_id, payload)
		MensajesRed.DENUNCIAR_CHAT:
			_denunciar(peer_id, payload)
		MensajesRed.ADMITIR_DENUNCIA:
			_responder_denuncia(peer_id, true)
		MensajesRed.NO_ADMITIR_DENUNCIA:
			_responder_denuncia(peer_id, false)
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
		# La sala pudo cachearse (más arriba, en _cargar_sala) antes de que este
		# usuario se uniera por REST en el lobby —p. ej. el creador se conecta
		# por ENet nada más crear la sala, cuando el resto aún no se ha unido—;
		# refrescar los participantes desde el backend antes de rechazarlo.
		await _actualizar_participantes(sala)
		if not _peers_conectados.has(peer_id):
			return
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
	_poner_al_dia_del_chat(sala, posicion)


## Devuelve [code]{ "sala": SalaActiva, "error": "" }[/code], o
## [code]{ "sala": null, "error": motivo }[/code].
func _cargar_sala(sala_id: String) -> Dictionary:
	# Terminada hace nada: el backend quizá aún no lo sabe (el registro va
	# después), pero no se puede volver a empezar.
	if _salas_terminadas.has(sala_id):
		return {"sala": null, "error": "La sala ya ha terminado"}
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
		sala.nombre_en_posicion[int(posicion)] = _nombre_de(participante)
	return sala


## Vuelve a pedir al backend los participantes de [param sala] y añade los que
## falten en la caché (ver comentario en [method _unirse]). Ignora la
## respuesta si falla o si la sala ya no está activa (p. ej. terminó mientras
## se consultaba): quien llame vuelve a comprobar `posicion_de_usuario` después.
func _actualizar_participantes(sala: SalaActiva) -> void:
	var respuesta: Dictionary = await _backend.obtener_sala(sala.sala_id)
	if not salas_activas.has(sala.sala_id) or not respuesta.get("ok", false) \
			or not respuesta.get("datos") is Dictionary:
		return
	var participantes: Variant = respuesta["datos"].get("participantes")
	if not participantes is Array:
		return
	for participante: Variant in participantes:
		if not participante is Dictionary:
			continue
		var usuario_id: Variant = participante.get("usuario_id")
		var posicion: Variant = participante.get("posicion")
		if not usuario_id is String or not (posicion is float or posicion is int):
			continue
		var pos_int := int(posicion)
		if pos_int < 0 or pos_int >= sala.capacidad:
			continue
		if sala.posicion_de_usuario.has(usuario_id) or sala.usuario_en_posicion.has(pos_int):
			continue
		sala.posicion_de_usuario[usuario_id] = pos_int
		sala.usuario_en_posicion[pos_int] = usuario_id
		sala.nombre_en_posicion[pos_int] = _nombre_de(participante)


func _empezar(sala: SalaActiva) -> void:
	sala.estado = sala.motor.iniciar(sala.capacidad)
	sala.fecha_inicio = reloj_fecha.call()
	_actualizar_tiempos(sala, -1)
	for posicion: int in sala.peer_en_posicion:
		_enviar_inicio(sala, posicion)
		_enviar_estado(sala, posicion)


func _jugar(peer_id: int, tipo: String, payload: Dictionary) -> void:
	var sala := _sala_del_peer(peer_id)
	if sala == null:
		var terminada := _sala_de_chat(peer_id) != null
		_enviar_error(peer_id, MotorDeJuego.ERROR_PARTIDA_TERMINADA if terminada
			else "Primero tienes que unirte a una partida")
		return
	if not sala.empezada():
		_enviar_error(peer_id, "La partida todavía no ha empezado")
		return
	if sala.en_pausa():
		_enviar_error(peer_id, ERROR_EN_PAUSA)
		return

	var jugada := {"tipo": tipo}
	jugada.merge(payload)  # sin sobrescribir: un "tipo" dentro del payload no cuenta
	var asiento := sala.posicion_de_peer(peer_id)
	var resultado := sala.motor.aplicar_jugada(sala.estado, asiento, jugada)
	if not resultado.ok:
		_enviar_error(peer_id, _motivo_del_rechazo(sala, asiento, jugada, resultado.error))
		return
	# Si juega él, no está ausente: vuelve a tener su tiempo normal.
	sala.agotados_seguidos.erase(asiento)
	_avanzar(sala, asiento, jugada, resultado.estado)


## Deja [param estado] como estado de la partida tras [param jugada] de
## [param quien] (una persona o, si se le acabó el tiempo, el servidor), se lo
## cuenta a todos y la cierra si ha terminado.
func _avanzar(sala: SalaActiva, quien: int, jugada: Dictionary, estado: EstadoPartida) -> void:
	sala.estado = estado
	sala.ultima_jugada = _jugada_publica(jugada, quien, sala.ultima_jugada.get("numero", 0) + 1)
	_actualizar_tiempos(sala, quien)
	for posicion: int in sala.peer_en_posicion:
		_enviar_estado(sala, posicion)
	if sala.motor.ha_terminado(sala.estado):
		_terminar(sala)


## El motivo concreto por el que el motor rechaza la jugada ("Tienes que
## asistir..."), si sabe darlo; si no, el error genérico de [MotorDeJuego].
func _motivo_del_rechazo(sala: SalaActiva, posicion: int, jugada: Dictionary, error: String) -> String:
	if not sala.motor.has_method("explicar_rechazo"):
		return error
	var motivo: String = sala.motor.call("explicar_rechazo", sala.estado, posicion, jugada)
	return motivo if not motivo.is_empty() else error


## Juega por quien haya agotado su tiempo para decidir. Se llama en cada frame
## ([method _process]); los tests la llaman a mano tras adelantar [member reloj].
func comprobar_tiempos() -> void:
	if segundos_por_turno <= 0:
		return
	var ahora: int = reloj.call()
	for sala_id: String in salas_activas.keys():
		var sala: SalaActiva = salas_activas.get(sala_id)
		# En pausa por una denuncia del chat los relojes no corren.
		if sala == null or not sala.empezada() or sala.en_pausa():
			continue
		for posicion: int in sala.limite_de:
			if sala.limite_de[posicion] <= ahora:
				# Una por sala y vuelta: tras jugar cambian los límites.
				_jugar_por_tiempo(sala, posicion)
				break


func _jugar_por_tiempo(sala: SalaActiva, posicion: int) -> void:
	var jugada := sala.motor.jugada_por_tiempo(sala.estado, posicion)
	var resultado := sala.motor.aplicar_jugada(sala.estado, posicion, jugada)
	if jugada.is_empty() or not resultado.ok:
		# No debería pasar (el motor elige entre sus jugadas válidas); se quita el
		# límite para no reintentarlo en cada frame.
		push_error("Sala %s: no se pudo jugar por tiempo por el jugador %d" % [sala.sala_id, posicion])
		sala.limite_de.erase(posicion)
		return
	var era_ausente := sala.es_ausente(posicion)
	sala.agotados_seguidos[posicion] = sala.agotados_seguidos.get(posicion, 0) + 1
	_avanzar(sala, posicion, jugada, resultado.estado)
	# Después del estado (que borra los errores en pantalla) para que se vea.
	if salas_activas.has(sala.sala_id) and sala.peer_en_posicion.has(posicion) and not era_ausente:
		_enviar_error(sala.peer_en_posicion[posicion],
			AVISO_AUSENTE if sala.es_ausente(posicion) else AVISO_TIEMPO_AGOTADO)


## Recalcula quién tiene cuenta atrás. Quien acaba de jugar y quien empieza a
## ser esperado estrenan tiempo; quien ya esperaba conserva el que le quedaba
## (p. ej. cuando otro canta mientras él tiene que echar carta). Quien está
## ausente (se le ha acabado el tiempo [constant TIEMPOS_AGOTADOS_PARA_AUSENTE]
## veces seguidas) tiene solo [constant SEGUNDOS_DE_AUSENTE].
func _actualizar_tiempos(sala: SalaActiva, quien_ha_jugado: int) -> void:
	if segundos_por_turno <= 0:
		return
	var ahora: int = reloj.call()
	var nuevos := {}
	for posicion: int in sala.motor.jugadores_esperados(sala.estado):
		if posicion != quien_ha_jugado and sala.limite_de.has(posicion):
			nuevos[posicion] = sala.limite_de[posicion]
		else:
			var segundos := SEGUNDOS_DE_AUSENTE if sala.es_ausente(posicion) else segundos_por_turno
			nuevos[posicion] = ahora + int(segundos * 1000.0)
	sala.limite_de = nuevos


## [code][{ "posicion": int, "segundos": float, "ausente": bool }][/code]: cuánto
## le queda a cada jugador esperado, para que el cliente enseñe la cuenta atrás.
func _tiempos_para_decidir(sala: SalaActiva) -> Array[Dictionary]:
	var tiempos: Array[Dictionary] = []
	# En pausa el reloj está parado: lo que le queda a cada uno es lo de entonces.
	var ahora: int = sala.pausada_desde if sala.en_pausa() else reloj.call()
	for posicion: int in sala.limite_de:
		tiempos.append({
			"posicion": posicion,
			"segundos": maxf(0.0, (sala.limite_de[posicion] - ahora) / 1000.0),
			"ausente": sala.es_ausente(posicion),
		})
	return tiempos


## Cierra la partida: avisa a los jugadores con el resultado, libera la sala y
## lo guarda en el backend. [param resultado] vacío es el del motor
## ([method MotorDeJuego.calcular_resultado]); quien corte la partida antes de
## tiempo (p. ej. un renuncio, PBI-08) pasa el suyo y su [param causa].
func _terminar(sala: SalaActiva, resultado: Dictionary = {}, causa := "completa") -> void:
	if resultado.is_empty():
		resultado = sala.motor.calcular_resultado(sala.estado)
	# Antes de avisar a nadie: así los jugadores y el historial ven lo mismo.
	resultado["causa"] = causa
	sala.terminada = true
	sala.limite_de.clear()
	sala.pausada_desde = -1
	for posicion: int in sala.peer_en_posicion:
		_enviar(sala.peer_en_posicion[posicion], MensajesRed.PARTIDA_TERMINADA, {"resultado": resultado})
	salas_activas.erase(sala.sala_id)
	# Los jugadores siguen en la sala, pero ya solo para chatear (PBI-08): se
	# borra cuando se va el último (ver desconectar).
	if not sala.peer_en_posicion.is_empty():
		_salas_terminadas[sala.sala_id] = sala
	_registrar_resultado(sala, resultado)


## Guarda la partida terminada en el backend (POST /interno/partidas) para el
## historial y el ranking, reintentando según [constant INTENTOS_REGISTRO] si
## el backend no contesta o falla (5xx). Un 409 es que ya estaba guardada (un
## intento anterior llegó aunque no se recibiera la respuesta) y vale como
## éxito; cualquier otro 4xx es un error en los datos, que no se arregla
## repitiendo la misma petición.
func _registrar_resultado(sala: SalaActiva, resultado: Dictionary) -> void:
	var datos := {
		"sala_id": sala.sala_id,
		"jugadores": sala.jugadores(),
		"resultado": resultado,
		"fecha_fin": reloj_fecha.call(),
	}
	# Sin fecha de inicio el backend usa la de fin; una cadena vacía la rechazaría.
	if not sala.fecha_inicio.is_empty():
		datos["fecha_inicio"] = sala.fecha_inicio
	var codigo := 0
	for intento in INTENTOS_REGISTRO:
		if intento > 0 and espera_entre_intentos_s > 0.0 and is_inside_tree():
			await get_tree().create_timer(espera_entre_intentos_s).timeout
		var respuesta: Dictionary = await _backend.registrar_partida(datos)
		codigo = int(respuesta.get("codigo", 0))
		if respuesta.get("ok", false) or codigo == 409:
			return
		if codigo > 0 and codigo < 500:
			push_error("El backend rechazó el resultado de la sala %s (código %d): %s"
				% [sala.sala_id, codigo, respuesta.get("datos")])
			return
	push_error("No se pudo registrar el resultado de la sala %s en el backend tras %d intentos (código %d)"
		% [sala.sala_id, INTENTOS_REGISTRO, codigo])


# --- Chat de la partida y denuncias (PBI-08) ----------------------------------
# El chat no toca el motor ni el estado de la partida: se atiende al momento,
# aunque la partida esté en pausa o ya haya terminado.


## Reenvía un mensaje a todos los de la sala, quien lo escribe incluido. Nunca
## llega a otra sala. Quién lo dice (usuario, nombre y asiento) lo pone el
## servidor a partir de la conexión, nunca del payload.
func _chatear(peer_id: int, payload: Dictionary) -> void:
	var sala := _sala_de_chat(peer_id)
	var posicion := sala.posicion_de_peer(peer_id) if sala != null else -1
	if posicion < 0:
		_enviar_error(peer_id, "Primero tienes que unirte a una partida")
		return
	var texto: Variant = payload.get("mensaje")
	var error := ChatSala.validar(texto)
	if not error.is_empty():
		_enviar_error(peer_id, error)
		return
	var mensaje := sala.chat.publicar(posicion, sala.usuario_en_posicion.get(posicion, ""),
		sala.nombre_en_posicion.get(posicion, ""), texto, sala.en_curso())
	_a_toda_la_sala(sala, MensajesRed.CHAT_MENSAJE, mensaje)


## Lo que necesita del chat quien acaba de unirse o reconectarse: todos los
## mensajes de la sala (HU-035, CA-130) y, si la partida está en pausa, la denuncia.
func _poner_al_dia_del_chat(sala: SalaActiva, posicion: int) -> void:
	var peer: int = sala.peer_en_posicion[posicion]
	_enviar(peer, MensajesRed.CHAT_HISTORIAL, {"mensajes": sala.chat.mensajes.duplicate(true)})
	if sala.chat.hay_denuncia():
		_enviar(peer, MensajesRed.DENUNCIA_CHAT,
			ChatSala.vista_denuncia(sala.chat.denuncia, "pendiente", reloj.call()))


## Un rival del autor denuncia un mensaje (HU-036): si se admite la denuncia,
## la partida se pausa hasta que la parte denunciada responda o pase el plazo.
func _denunciar(peer_id: int, payload: Dictionary) -> void:
	var sala := _sala_del_peer(peer_id)
	if sala == null:
		_enviar_error(peer_id, ChatSala.ERROR_SIN_PARTIDA if _sala_de_chat(peer_id) != null
			else "Primero tienes que unirte a una partida")
		return
	var ahora: int = reloj.call()
	var error := sala.chat.denunciar(payload.get("mensaje_id"), sala.posicion_de_peer(peer_id), ahora, sala.en_curso())
	if not error.is_empty():
		_enviar_error(peer_id, error)
		return
	sala.pausar(ahora)
	_a_toda_la_sala(sala, MensajesRed.DENUNCIA_CHAT,
		ChatSala.vista_denuncia(sala.chat.denuncia, "pendiente", ahora))


## Cualquiera de la parte denunciada contesta; vale la primera respuesta.
func _responder_denuncia(peer_id: int, admite: bool) -> void:
	var sala := _sala_del_peer(peer_id)
	if sala == null:
		_enviar_error(peer_id, ChatSala.ERROR_SIN_DENUNCIA if _sala_de_chat(peer_id) != null
			else "Primero tienes que unirte a una partida")
		return
	var posicion := sala.posicion_de_peer(peer_id)
	var error := sala.chat.puede_responder(posicion)
	if not error.is_empty():
		_enviar_error(peer_id, error)
		return
	_resolver_denuncia(sala, "admitida" if admite else "no_admitida", posicion)


## Da por caducadas (sin admitir) las denuncias a las que nadie ha contestado a
## tiempo. Como [method comprobar_tiempos], se llama en cada frame y los tests
## la llaman a mano; funciona aunque el tiempo límite para decidir esté desactivado.
func comprobar_denuncias() -> void:
	var ahora: int = reloj.call()
	for sala_id: String in salas_activas.keys():
		var sala: SalaActiva = salas_activas.get(sala_id)
		if sala != null and sala.chat.hay_denuncia() and int(sala.chat.denuncia["limite_ms"]) <= ahora:
			_resolver_denuncia(sala, "caducada")


## Cierra la denuncia pendiente y se lo cuenta a todos. Admitida: termina la
## partida y gana la parte perjudicada con el marcador que llevaba cada uno
## (HU-036 CA-134, HU-016 CA-060). Si no: se sigue jugando donde estaba (CA-135),
## y todos reciben el estado con sus jugadas y lo que les queda de tiempo.
func _resolver_denuncia(sala: SalaActiva, estado: String, quien := -1) -> void:
	var ahora: int = reloj.call()
	var denuncia := sala.chat.cerrar_denuncia()
	_a_toda_la_sala(sala, MensajesRed.DENUNCIA_CHAT, ChatSala.vista_denuncia(denuncia, estado, ahora, quien))
	if estado == "admitida":
		var ganador := 1 - int(denuncia["equipo_denunciado"])
		_terminar(sala, sala.motor.resultado_anticipado(sala.estado, ganador), "renuncio")
		return
	sala.reanudar(ahora)
	for posicion: int in sala.peer_en_posicion:
		_enviar_estado(sala, posicion)


func _enviar_inicio(sala: SalaActiva, posicion: int) -> void:
	_enviar(sala.peer_en_posicion[posicion], MensajesRed.PARTIDA_INICIADA, {"config": {
		"sala_id": sala.sala_id,
		"juego": sala.juego,
		"tu_posicion": posicion,
		"jugadores": sala.jugadores_con_nombre(),
	}})


## La vista del jugador más lo que puede hacer ahora mismo, para que el cliente
## no tenga que conocer las reglas (nunca decide si una jugada es válida).
func _enviar_estado(sala: SalaActiva, posicion: int) -> void:
	var payload := sala.motor.vista_para_jugador(sala.estado, posicion)
	payload["jugadas_validas"] = sala.motor.jugadas_validas(sala.estado, posicion)
	payload["ultima_jugada"] = sala.ultima_jugada
	payload["tiempos_para_decidir"] = _tiempos_para_decidir(sala)
	_enviar(sala.peer_en_posicion[posicion], MensajesRed.ESTADO_PARTIDA, payload)


## Nombre visible de un participante tal como lo da el backend; "" si no viene.
static func _nombre_de(participante: Dictionary) -> String:
	var nombre: Variant = participante.get("nombre_visible", "")
	return nombre if nombre is String else ""


## Lo que todos los jugadores pueden saber de una jugada aceptada, para que la
## mesa la anuncie ("¡Las 40!", "Envido 2"...): quién, qué tipo y sus datos
## públicos. De un descarte solo se dice cuántas cartas, nunca cuáles.
## [param numero] cuenta las jugadas de la partida: así el cliente distingue
## una jugada nueva de un estado repetido (p. ej. al reconectarse).
static func _jugada_publica(jugada: Dictionary, posicion: int, numero: int) -> Dictionary:
	var publica := {"numero": numero, "jugador_id": posicion, "tipo": jugada.get("tipo", "")}
	for clave: String in ["carta_id", "palo", "figura", "cantidad"]:
		if jugada.has(clave):
			publica[clave] = jugada[clave]
	if jugada.get("cartas") is Array:
		publica["num_cartas"] = (jugada["cartas"] as Array).size()
	return publica


func _sala_del_peer(peer_id: int) -> SalaActiva:
	return salas_activas.get(_sala_de_peer.get(peer_id, ""))


## La sala del peer para el chat: la activa o, si su partida ya ha terminado,
## la que se conserva para seguir chateando (ver [member _salas_terminadas]).
func _sala_de_chat(peer_id: int) -> SalaActiva:
	var sala_id: String = _sala_de_peer.get(peer_id, "")
	return salas_activas.get(sala_id, _salas_terminadas.get(sala_id))


func _a_toda_la_sala(sala: SalaActiva, tipo: String, payload: Dictionary) -> void:
	for posicion: int in sala.peer_en_posicion:
		_enviar(sala.peer_en_posicion[posicion], tipo, payload.duplicate(true))


func _enviar(peer_id: int, tipo: String, payload: Dictionary) -> void:
	mensaje_para.emit(peer_id, MensajesRed.crear(tipo, payload))


func _enviar_error(peer_id: int, texto: String) -> void:
	_enviar(peer_id, MensajesRed.ERROR, {"mensaje": texto})


func _rechazar(peer_id: int, texto: String) -> void:
	_enviar_error(peer_id, texto)
	expulsar.emit(peer_id)
