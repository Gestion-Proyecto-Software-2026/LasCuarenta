extends Node
## Doble de ClienteRed que habla directamente con un RoomManager, sin ENet: lo
## que la pantalla envía le llega al servidor como si viniera del peer, y lo que
## el servidor manda a ese peer sale por las mismas señales que en ClienteRed.
## Sirve para jugar partidas enteras con la pantalla de verdad y el servidor de
## verdad en un mismo test (test_mesa_seis_modos.gd).

signal conectado
signal fallo_conexion
signal desconectado_del_servidor
signal sala_actualizada(sala: Dictionary)
signal partida_iniciada(config: Dictionary)
signal estado_actualizado(estado: Dictionary)
signal partida_terminada(resultado: Dictionary)
signal error_recibido(mensaje: String)
## Chat de la partida (PBI-08): un mensaje nuevo, la lista entera al unirse o
## reconectarse, y una denuncia que empieza o se resuelve.
signal chat_recibido(mensaje: Dictionary)
signal chat_reiniciado(mensajes: Array)
signal denuncia_actualizada(denuncia: Dictionary)

var sala_id := ""
var servidor_direccion := "bucle"
var config: Dictionary = {}
var sala: Dictionary = {}
var ultimo_estado: Dictionary = {}
var resultado: Dictionary = {}
var chat: Array = []
var denuncia: Dictionary = {}

var servidor: RoomManager
var peer := 0
var errores: Array[String] = []
var estados_recibidos := 0


func _init(p_servidor: RoomManager, p_peer: int) -> void:
	servidor = p_servidor
	peer = p_peer
	servidor.mensaje_para.connect(_on_mensaje_para)
	servidor.conectar(peer)


func unirse_partida(usuario_id: String, token: String) -> void:
	enviar(MensajesRed.UNIRSE_PARTIDA, {"usuario_id": usuario_id, "token": token, "sala_id": sala_id})


func empezar_partida() -> void:
	enviar(MensajesRed.EMPEZAR_PARTIDA)


func actualizar_sala() -> void:
	enviar(MensajesRed.ACTUALIZAR_SALA)


func enviar(tipo: String, payload: Dictionary = {}) -> void:
	servidor.recibir(peer, MensajesRed.crear(tipo, payload))


func desconectar() -> void:
	servidor.desconectar(peer)


## Igual que ClienteRed._on_mensaje.
func _on_mensaje_para(para: int, mensaje: Dictionary) -> void:
	if para != peer:
		return
	var payload: Dictionary = mensaje.get("payload", {})
	match mensaje.get("tipo"):
		MensajesRed.SALA_ACTUALIZADA:
			sala = payload
			sala_actualizada.emit(sala)
		MensajesRed.PARTIDA_INICIADA:
			config = payload.get("config", {})
			partida_iniciada.emit(config)
		MensajesRed.ESTADO_PARTIDA:
			ultimo_estado = payload
			estados_recibidos += 1
			estado_actualizado.emit(ultimo_estado)
		MensajesRed.PARTIDA_TERMINADA:
			resultado = payload.get("resultado", {})
			partida_terminada.emit(resultado)
		MensajesRed.ERROR:
			errores.append(payload.get("mensaje", ""))
			error_recibido.emit(payload.get("mensaje", ""))
		MensajesRed.CHAT_MENSAJE:
			chat.append(payload)
			chat_recibido.emit(payload)
		MensajesRed.CHAT_HISTORIAL:
			var mensajes: Variant = payload.get("mensajes", [])
			chat = mensajes if mensajes is Array else []
			chat_reiniciado.emit(chat)
		MensajesRed.DENUNCIA_CHAT:
			denuncia = payload if payload.get("estado") == "pendiente" else {}
			denuncia_actualizada.emit(payload)
