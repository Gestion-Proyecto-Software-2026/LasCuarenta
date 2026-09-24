class_name MensajesRed
extends RefCounted
## Nombres de los mensajes del protocolo cliente ↔ servidor de partida
## (analisis_funcional_app.md §6). Cada mensaje viaja por [code]CanalRed[/code]
## como [code]{ "tipo": String, "payload": Dictionary }[/code].

# Cliente → servidor
const UNIRSE_PARTIDA := "unirse_partida"
const JUGAR_CARTA := "jugar_carta"
const CANTAR := "cantar"
const CANTAR_TUTE := "cantar_tute"
const CAMBIAR_SIETE := "cambiar_siete"
const NO_CAMBIAR_SIETE := "no_cambiar_siete"
const MUS := "mus"
const NO_MUS := "no_mus"
const APOSTAR := "apostar"
const CHAT_ENVIAR := "chat_enviar"

# Servidor → cliente
const PARTIDA_INICIADA := "partida_iniciada"
const ESTADO_PARTIDA := "estado_partida"
const PARTIDA_TERMINADA := "partida_terminada"
const CHAT_MENSAJE := "chat_mensaje"
const ERROR := "error"


static func crear(tipo: String, payload: Dictionary = {}) -> Dictionary:
	return {"tipo": tipo, "payload": payload}
