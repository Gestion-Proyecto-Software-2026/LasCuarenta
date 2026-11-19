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
## Tute de 2: anunciar que se ganarán todas las bazas del arrastre.
const CAPOTE := "capote"
const MUS := "mus"
const NO_MUS := "no_mus"
const DESCARTAR := "descartar"
const PASAR := "pasar"
const ENVIDAR := "envidar"
const ORDAGO := "ordago"
const QUIERO := "quiero"
const NO_QUIERO := "no_quiero"
const CHAT_ENVIAR := "chat_enviar"
## Sala de espera (PBI-09): el creador arranca la partida cuando están todos.
const EMPEZAR_PARTIDA := "empezar_partida"
## Sala de espera: pide al servidor que vuelva a leer la sala del backend
## (p. ej. tras expulsar a alguien por REST).
const ACTUALIZAR_SALA := "actualizar_sala"
## Denuncia de un mensaje del chat por revelar cartas o hacer señas (PBI-08):
## la hace un rival de quien lo escribió y pausa la partida hasta que la parte
## denunciada responde o pasa un minuto.
const DENUNCIAR_CHAT := "denunciar_chat"
const ADMITIR_DENUNCIA := "admitir_denuncia"
const NO_ADMITIR_DENUNCIA := "no_admitir_denuncia"

# Servidor → cliente
## Quién está sentado en la sala de espera y quién es el creador (PBI-09).
const SALA_ACTUALIZADA := "sala_actualizada"
const PARTIDA_INICIADA := "partida_iniciada"
const ESTADO_PARTIDA := "estado_partida"
const PARTIDA_TERMINADA := "partida_terminada"
const CHAT_MENSAJE := "chat_mensaje"
## Todos los mensajes del chat de la sala, al unirse o reconectarse (PBI-08).
const CHAT_HISTORIAL := "chat_historial"
## Una denuncia empieza (pendiente) o se resuelve (admitida, no_admitida, caducada).
const DENUNCIA_CHAT := "denuncia_chat"
const ERROR := "error"

## Los que van por el canal de ENet del chat (ver CanalRed.CANAL_CHAT). Las
## denuncias no: pausan y reanudan la partida, así que van con las jugadas.
const TIPOS_CHAT := [CHAT_ENVIAR, CHAT_MENSAJE, CHAT_HISTORIAL]


static func crear(tipo: String, payload: Dictionary = {}) -> Dictionary:
	return {"tipo": tipo, "payload": payload}
