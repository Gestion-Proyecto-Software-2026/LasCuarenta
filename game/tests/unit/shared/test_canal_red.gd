extends GutTest
## CanalRed (PBI-08): el chat va por su propio canal de ENet para no retrasar
## las jugadas; todo lo demás, también las denuncias, por el canal 0.

const CanalRedScript := preload("res://shared/canal_red.gd")


func test_el_chat_va_por_el_canal_del_chat() -> void:
	for tipo: String in [MensajesRed.CHAT_ENVIAR, MensajesRed.CHAT_MENSAJE, MensajesRed.CHAT_HISTORIAL]:
		assert_eq(CanalRedScript.canal_de(MensajesRed.crear(tipo)), CanalRedScript.CANAL_CHAT, tipo)


func test_las_jugadas_y_las_denuncias_van_por_el_canal_0() -> void:
	for tipo: String in [
		MensajesRed.UNIRSE_PARTIDA, MensajesRed.JUGAR_CARTA, MensajesRed.ESTADO_PARTIDA,
		MensajesRed.PARTIDA_TERMINADA, MensajesRed.ERROR, MensajesRed.DENUNCIAR_CHAT,
		MensajesRed.ADMITIR_DENUNCIA, MensajesRed.NO_ADMITIR_DENUNCIA, MensajesRed.DENUNCIA_CHAT,
	]:
		assert_eq(CanalRedScript.canal_de(MensajesRed.crear(tipo)), 0, tipo)
	assert_eq(CanalRedScript.canal_de({}), 0, "un mensaje sin tipo, por el normal")


func test_cada_rpc_usa_su_canal() -> void:
	var script: Script = CanalRedScript
	var config: Dictionary = script.get_rpc_config()
	assert_eq(int(config["_entregar_chat"].get("channel", 0)), CanalRedScript.CANAL_CHAT)
	assert_eq(int(config["_entregar"].get("channel", 0)), 0)
	assert_eq(int(config["_entregar_chat"]["transfer_mode"]), MultiplayerPeer.TRANSFER_MODE_RELIABLE)
