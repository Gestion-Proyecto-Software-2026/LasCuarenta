extends GutTest
## No probamos una conexión ENet real (necesitaría un servidor escuchando);
## probamos el enrutado de mensajes y los casos de error que no dependen de
## la red (dirección mal formada). La conexión de verdad se prueba a mano
## (ver el informe de pruebas manuales).

const ClienteRedScript := preload("res://client/autoload/cliente_red.gd")

var red


func before_each() -> void:
	red = ClienteRedScript.new()
	add_child_autofree(red)


func test_preparar_guarda_sala_y_direccion() -> void:
	red.preparar("sala-1", "localhost:9001")

	assert_eq(red.sala_id, "sala-1")
	assert_eq(red.servidor_direccion, "localhost:9001")


func test_direccion_sin_puerto_emite_fallo_conexion_sin_tocar_la_red() -> void:
	red.preparar("sala-1", "direccion-sin-puerto")
	watch_signals(red)

	red.conectar_al_servidor()

	assert_signal_emitted(red, "fallo_conexion")


func test_puerto_no_numerico_emite_fallo_conexion() -> void:
	red.preparar("sala-1", "localhost:abc")
	watch_signals(red)

	red.conectar_al_servidor()

	assert_signal_emitted(red, "fallo_conexion")


func test_ignora_mensajes_de_peers_que_no_son_el_servidor() -> void:
	watch_signals(red)

	red._on_mensaje(2, MensajesRed.crear(MensajesRed.ESTADO_PARTIDA, {"fase": "robo"}))

	assert_signal_not_emitted(red, "estado_actualizado")
	assert_eq(red.ultimo_estado, {})


func test_partida_iniciada_guarda_config_y_emite_la_senal() -> void:
	watch_signals(red)
	var config := {"sala_id": "s1", "juego": "guinote", "tu_posicion": 2, "jugadores": []}

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.PARTIDA_INICIADA, {"config": config}))

	assert_signal_emitted_with_parameters(red, "partida_iniciada", [config])
	assert_eq(red.config, config)


func test_estado_partida_guarda_el_ultimo_estado_y_emite_la_senal() -> void:
	watch_signals(red)
	var estado := {"fase": "robo", "mi_mano": ["oros_1"], "jugadas_validas": []}

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.ESTADO_PARTIDA, estado))

	assert_signal_emitted_with_parameters(red, "estado_actualizado", [estado])
	assert_eq(red.ultimo_estado, estado)


func test_partida_terminada_guarda_el_resultado_y_emite_la_senal() -> void:
	watch_signals(red)
	var resultado := {"equipo_ganador": 0, "puntos_por_equipo": [101, 54]}

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.PARTIDA_TERMINADA, {"resultado": resultado}))

	assert_signal_emitted_with_parameters(red, "partida_terminada", [resultado])
	assert_eq(red.resultado, resultado)


func test_error_recibido_emite_el_mensaje() -> void:
	watch_signals(red)

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.ERROR, {"mensaje": "La sala no existe"}))

	assert_signal_emitted_with_parameters(red, "error_recibido", ["La sala no existe"])




# --- Chat de la partida (PBI-08) ---

func test_chat_mensaje_se_guarda_y_emite_la_senal() -> void:
	watch_signals(red)
	var mensaje := {"id": 1, "posicion": 1, "nombre": "Luis", "mensaje": "hola"}

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.CHAT_MENSAJE, mensaje))

	assert_eq(red.chat, [mensaje])
	assert_signal_emitted_with_parameters(red, "chat_recibido", [mensaje])


func test_chat_historial_sustituye_el_chat_guardado() -> void:
	red.chat = [{"id": 9}]
	watch_signals(red)
	var mensajes := [{"id": 1}, {"id": 2}]

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.CHAT_HISTORIAL, {"mensajes": mensajes}))

	assert_eq(red.chat, mensajes)
	assert_signal_emitted(red, "chat_reiniciado")


func test_denuncia_pendiente_se_guarda_y_al_resolverse_se_olvida() -> void:
	watch_signals(red)
	var pendiente := {"estado": "pendiente", "mensaje_id": 1, "segundos": 60.0}

	red._on_mensaje(1, MensajesRed.crear(MensajesRed.DENUNCIA_CHAT, pendiente))
	assert_eq(red.denuncia, pendiente)
	red._on_mensaje(1, MensajesRed.crear(MensajesRed.DENUNCIA_CHAT, {"estado": "caducada", "mensaje_id": 1}))

	assert_eq(red.denuncia, {})
	assert_signal_emit_count(red, "denuncia_actualizada", 2)


func test_desconectar_olvida_el_chat_y_la_denuncia() -> void:
	red.chat = [{"id": 1}]
	red.denuncia = {"estado": "pendiente"}

	red.desconectar()

	assert_eq(red.chat, [])
	assert_eq(red.denuncia, {})
