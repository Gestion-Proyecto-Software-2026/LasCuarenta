class_name ChatSala
extends RefCounted
## El chat de una sala del servidor de partida (PBI-08): los mensajes que se han
## escrito y la denuncia que haya pendiente. Es lógica pura, sin red: RoomManager
## decide a quién se reenvía cada cosa y qué hace la partida mientras tanto.
##
## Denunciar un mensaje (HU-036): revelar cartas o hacer señas por el chat es
## renuncio. Un rival de quien lo escribió lo denuncia, la partida se pausa hasta
## [constant SEGUNDOS_PARA_ADMITIR] y la parte denunciada lo admite (gana la
## perjudicada) o no (se sigue jugando). Un mismo mensaje solo se denuncia una vez.

const MAX_CARACTERES := 500
## Salvaguarda de memoria: muy por encima de lo que se escribe en una partida.
## Si se llega, se descartan los más antiguos.
const MAX_MENSAJES := 500
const SEGUNDOS_PARA_ADMITIR := 60.0

const ERROR_NO_ES_TEXTO := "El mensaje de chat tiene que ser un texto"
const ERROR_VACIO := "No puedes enviar un mensaje vacío"
const ERROR_LARGO := "El mensaje no puede pasar de 500 caracteres"
const ERROR_SIN_PARTIDA := "Solo se pueden denunciar mensajes mientras se juega la partida"
const ERROR_YA_PENDIENTE := "Ya hay una denuncia pendiente: espera a que se resuelva"
const ERROR_NO_EXISTE := "Ese mensaje no existe"
const ERROR_ANTES_DE_EMPEZAR := "Ese mensaje se escribió antes de empezar la partida"
const ERROR_NO_ES_RIVAL := "Solo pueden denunciar un mensaje los rivales de quien lo escribió"
const ERROR_YA_DENUNCIADO := "Ese mensaje ya se ha denunciado"
const ERROR_SIN_DENUNCIA := "No hay ninguna denuncia pendiente"
const ERROR_NO_DENUNCIADO := "Solo puede responder la parte denunciada"

## Lo que se manda en chat_mensaje: { id, usuario_id, posicion, equipo, nombre,
## mensaje, durante_partida }, del más antiguo al más reciente.
var mensajes: Array[Dictionary] = []
## La denuncia pendiente ({} si no hay): { mensaje_id, mensaje, denunciante,
## denunciado, equipo_denunciado, limite_ms }. limite_ms es el instante (reloj de
## RoomManager) en que se acaba el plazo para responder.
var denuncia: Dictionary = {}

var _siguiente_id := 1
var _denunciados: Dictionary = {}  # mensaje_id -> true

static var _control := RegEx.create_from_string("[\\x{0000}-\\x{001F}\\x{007F}]")


## Los caracteres de control (saltos de línea, tabuladores...) pasan a ser
## espacios, y se quitan los del principio y el final.
static func limpiar(texto: String) -> String:
	return _control.sub(texto, " ", true).strip_edges()


## "" si [param texto] se puede publicar; si no, el motivo para el jugador.
static func validar(texto: Variant) -> String:
	if not texto is String:
		return ERROR_NO_ES_TEXTO
	# Uno muy por encima del límite no puede quedarse en 500 al quitarle los
	# espacios de los extremos: se rechaza sin llegar a recorrerlo.
	if (texto as String).length() > MAX_CARACTERES * 4:
		return ERROR_LARGO
	var limpio := limpiar(texto)
	if limpio.is_empty():
		return ERROR_VACIO
	if limpio.length() > MAX_CARACTERES:
		return ERROR_LARGO
	return ""


## Guarda un mensaje ya validado y lo devuelve tal como se reenvía a la sala.
## [param durante_partida] dice si se escribió con la partida en juego: solo
## esos se pueden denunciar.
func publicar(posicion: int, usuario_id: String, nombre: String, texto: String, durante_partida: bool) -> Dictionary:
	var mensaje := {
		"id": _siguiente_id,
		"usuario_id": usuario_id,
		"posicion": posicion,
		"equipo": MotorDeJuego.equipo_de(posicion),
		"nombre": nombre,
		"mensaje": limpiar(texto),
		"durante_partida": durante_partida,
	}
	_siguiente_id += 1
	mensajes.append(mensaje)
	if mensajes.size() > MAX_MENSAJES:
		mensajes.pop_front()
	return mensaje


func hay_denuncia() -> bool:
	return not denuncia.is_empty()


## Abre la denuncia de [param mensaje_id] hecha por quien se sienta en
## [param denunciante]. Devuelve "" si se admite (y desde ese momento hay
## denuncia pendiente) o el motivo por el que no. [param en_curso]: si la
## partida se está jugando (empezada y sin terminar).
func denunciar(mensaje_id: Variant, denunciante: int, ahora_ms: int, en_curso: bool) -> String:
	if not en_curso:
		return ERROR_SIN_PARTIDA
	if hay_denuncia():
		return ERROR_YA_PENDIENTE
	var mensaje := _buscar(mensaje_id)
	if mensaje.is_empty():
		return ERROR_NO_EXISTE
	if not mensaje["durante_partida"]:
		return ERROR_ANTES_DE_EMPEZAR
	if mensaje["equipo"] == MotorDeJuego.equipo_de(denunciante):
		return ERROR_NO_ES_RIVAL
	if _denunciados.has(mensaje["id"]):
		return ERROR_YA_DENUNCIADO
	_denunciados[mensaje["id"]] = true
	denuncia = {
		"mensaje_id": mensaje["id"],
		"mensaje": mensaje["mensaje"],
		"denunciante": denunciante,
		"denunciado": mensaje["posicion"],
		"equipo_denunciado": mensaje["equipo"],
		"limite_ms": ahora_ms + int(SEGUNDOS_PARA_ADMITIR * 1000.0),
	}
	return ""


## "" si quien se sienta en [param posicion] puede contestar a la denuncia
## pendiente (cualquiera de la parte denunciada); si no, el motivo.
func puede_responder(posicion: int) -> String:
	if not hay_denuncia():
		return ERROR_SIN_DENUNCIA
	if MotorDeJuego.equipo_de(posicion) != denuncia["equipo_denunciado"]:
		return ERROR_NO_DENUNCIADO
	return ""


## Quita la denuncia pendiente y la devuelve ({} si no había).
func cerrar_denuncia() -> Dictionary:
	var cerrada := denuncia
	denuncia = {}
	return cerrada


## Payload de denuncia_chat para [param datos] (una denuncia, pendiente o recién
## cerrada) en el [param estado] indicado. [code]segundos[/code] es lo que queda
## para responder; solo tiene sentido mientras está pendiente.
static func vista_denuncia(datos: Dictionary, estado: String, ahora_ms: int, respondido_por := -1) -> Dictionary:
	var segundos := 0.0
	if estado == "pendiente":
		segundos = maxf(0.0, (int(datos.get("limite_ms", ahora_ms)) - ahora_ms) / 1000.0)
	return {
		"estado": estado,
		"mensaje_id": datos.get("mensaje_id", -1),
		"mensaje": datos.get("mensaje", ""),
		"denunciante": datos.get("denunciante", -1),
		"denunciado": datos.get("denunciado", -1),
		"equipo_denunciado": datos.get("equipo_denunciado", -1),
		"segundos": segundos,
		"respondido_por": respondido_por,
	}


## El mensaje con ese id, o {} si no existe (o el id no es un entero).
func _buscar(mensaje_id: Variant) -> Dictionary:
	var id := -1
	if mensaje_id is int:
		id = mensaje_id
	elif mensaje_id is float and is_equal_approx(mensaje_id, roundf(mensaje_id)):
		id = int(mensaje_id)
	if id < 1:
		return {}
	for mensaje: Dictionary in mensajes:
		if mensaje["id"] == id:
			return mensaje
	return {}
