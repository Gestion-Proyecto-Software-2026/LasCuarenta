extends GutTest
## La navegación real (change_scene_to_file) no se prueba aquí, igual que el
## resto de pantallas del cliente (ver lobby.gd/test_lobby.gd): se comprueba a
## mano (ver el informe de pruebas manuales). Lo que sí probamos es que esta
## pantalla conecta, envía unirse_partida con los datos correctos, y reacciona
## a los errores del servidor.

const ESPERA := preload("res://client/ui/espera/espera.tscn")
const ClienteRedFalso := preload("res://tests/unit/client/cliente_red_falso.gd")
const ClienteApiFalso := preload("res://tests/unit/client/cliente_api_falso.gd")

var red
var api
var espera


func before_each() -> void:
	red = ClienteRedFalso.new()
	red.sala_id = "sala-1"
	add_child_autofree(red)
	api = ClienteApiFalso.new()
	api.usuario = {"id": "u1", "nombre_visible": "Ana"}
	api.token = "tok-123"
	add_child_autofree(api)

	espera = ESPERA.instantiate()
	espera.red = red
	espera.api = api
	add_child_autofree(espera)
	await wait_frames(1)


func _etiqueta(nombre: String) -> Label:
	return espera.find_child(nombre, true, false)


func _boton(nombre: String) -> Button:
	return espera.find_child(nombre, true, false)


func test_al_entrar_se_conecta_al_servidor_de_partida() -> void:
	assert_eq(red.llamadas[0], ["conectar_al_servidor"])


func test_al_conectar_envia_unirse_partida_con_usuario_y_token() -> void:
	red.conectado.emit()

	assert_true(red.llamadas.has(["unirse_partida", "u1", "tok-123"]))


func test_fallo_de_conexion_muestra_error_y_boton_volver() -> void:
	red.fallo_conexion.emit()

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_true(_boton("BotonVolver").visible)


func test_error_del_servidor_muestra_el_mensaje_y_desconecta() -> void:
	red.error_recibido.emit("La sala no existe")

	assert_eq(_etiqueta("EtiquetaError").text, "La sala no existe")
	assert_true(red.llamadas.has(["desconectar"]))


func test_desconexion_del_servidor_muestra_error_y_desconecta() -> void:
	red.desconectado_del_servidor.emit()

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_true(red.llamadas.has(["desconectar"]))


func test_el_boton_salir_esta_visible_desde_el_principio() -> void:
	# No hace falta esperar a un error: se puede salir mientras se espera a los
	# demás jugadores (ver docs/analisis_funcional_app.md §5).
	assert_true(_boton("BotonVolver").visible)


func test_todos_los_juegos_y_modos_van_a_la_mesa_comun() -> void:
	# PBI-12: una sola pantalla de partida para Guiñote, Tute y Mus, a 2 y a 4.
	for juego: String in ["guinote", "tute", "mus"]:
		for jugadores: Array in [[{}, {}], [{}, {}, {}, {}]]:
			var escena: String = espera._escena_para({"juego": juego, "jugadores": jugadores})
			assert_eq(escena, "res://client/ui/mesa/partida_mesa.tscn", "%s a %d" % [juego, jugadores.size()])


func test_salir_abandona_la_sala_por_HTTP_y_desconecta_de_ENet() -> void:
	# Llama directamente a _abandonar_sala (y no al botón) para no disparar la
	# navegación real de get_tree().change_scene_to_file; ver el comentario de
	# esa función en espera.gd.
	await espera._abandonar_sala()

	assert_true(api.llamadas.has(["salir_sala", "sala-1"]))
	assert_true(red.llamadas.has(["desconectar"]))

# El botón "Salir de la sala" también cambia de escena (get_tree().change_scene_to_file);
# esa navegación no se prueba aquí por el mismo motivo que en lobby.gd (ver
# docs/mapa/tests-ci.md): se comprueba a mano.


# --- Sala de espera y moderación (PBI-09) ---

const SALA_COMPLETA := {
	"creador_id": "u1", "capacidad": 2,
	"jugadores": [
		{"usuario_id": "u1", "nombre": "Ana", "posicion": 0, "conectado": true},
		{"usuario_id": "u2", "nombre": "Luis", "posicion": 1, "conectado": true},
	],
}


func _lista() -> VBoxContainer:
	return espera.find_child("ListaJugadores", true, false)


func _sala(cambios: Dictionary = {}) -> Dictionary:
	var sala := SALA_COMPLETA.duplicate(true)
	sala.merge(cambios, true)
	red.sala = sala
	red.sala_actualizada.emit(sala)
	return sala


func test_pinta_un_jugador_por_asiento_ocupado() -> void:
	_sala()

	assert_eq(_lista().get_child_count(), 2)
	assert_eq(_lista().get_child(0).get_node("Nombre").text, "Ana (creador) (tú)")
	assert_eq(_lista().get_child(1).get_node("Nombre").text, "Luis")


func test_el_creador_ve_expulsar_en_los_demas_y_empezar_activo_con_la_sala_completa() -> void:
	_sala()

	assert_null(_lista().get_child(0).get_node_or_null("BotonExpulsar"), "no puede expulsarse a sí mismo")
	assert_not_null(_lista().get_child(1).get_node_or_null("BotonExpulsar"))
	assert_true(_boton("BotonEmpezar").visible)
	assert_false(_boton("BotonEmpezar").disabled)


func test_con_la_sala_incompleta_empezar_esta_desactivado() -> void:
	_sala({"jugadores": [SALA_COMPLETA["jugadores"][0]]})

	assert_true(_boton("BotonEmpezar").disabled)
	assert_eq(_etiqueta("EtiquetaEstado").text, "Esperando jugadores (1/2)...")


func test_quien_no_es_creador_no_ve_expulsar_ni_empezar() -> void:
	api.usuario = {"id": "u2", "nombre_visible": "Luis"}
	_sala()

	for fila in _lista().get_children():
		assert_null(fila.get_node_or_null("BotonExpulsar"))
	assert_false(_boton("BotonEmpezar").visible)
	assert_eq(_etiqueta("EtiquetaEstado").text, "Sala completa. Esperando a que el creador empiece la partida...")


func test_empezar_lo_pide_al_servidor() -> void:
	_sala()

	_boton("BotonEmpezar").pressed.emit()

	assert_true(red.llamadas.has(["empezar_partida"]))


func test_expulsar_llama_al_backend_y_pide_releer_la_sala() -> void:
	_sala()

	_lista().get_child(1).get_node("BotonExpulsar").pressed.emit()
	await wait_process_frames(2)

	assert_true(api.llamadas.has(["expulsar_jugador", "sala-1", "u2"]))
	assert_true(red.llamadas.has(["actualizar_sala"]))


func test_si_el_backend_rechaza_la_expulsion_se_muestra_el_error() -> void:
	api.respuesta_expulsar = {"ok": false, "codigo": 409, "datos": {"error": "la partida ya ha empezado"}}
	_sala()

	_lista().get_child(1).get_node("BotonExpulsar").pressed.emit()
	await wait_process_frames(2)

	assert_eq(_etiqueta("EtiquetaError").text, "la partida ya ha empezado")
	assert_false(red.llamadas.has(["actualizar_sala"]))
	assert_false(red.llamadas.has(["desconectar"]))


func test_un_error_recuperable_en_la_sala_no_desconecta() -> void:
	_sala()

	red.error_recibido.emit("Faltan jugadores: la sala tiene que estar completa para empezar")

	assert_true(_etiqueta("EtiquetaError").visible)
	assert_false(red.llamadas.has(["desconectar"]))


func test_al_ser_expulsado_se_muestra_el_motivo_y_se_desconecta() -> void:
	api.usuario = {"id": "u2", "nombre_visible": "Luis"}
	_sala()

	red.error_recibido.emit("El creador de la sala te ha expulsado")

	assert_eq(_etiqueta("EtiquetaError").text, "El creador de la sala te ha expulsado")
	assert_true(red.llamadas.has(["desconectar"]))
	assert_false(_boton("BotonEmpezar").visible)


# --- Máquinas en la sala de espera (PBI-20) ---

const SALA_CON_MAQUINA := {
	"creador_id": "u1", "capacidad": 4,
	"jugadores": [
		{"usuario_id": "u1", "nombre": "Ana", "posicion": 0, "conectado": true, "maquina": false},
		{"usuario_id": "", "nombre": "Máquina · Difícil", "posicion": 2, "conectado": true, "maquina": true, "dificultad": "dificil"},
	],
}


func _sala_con_maquina(creador := "u1") -> void:
	var sala := SALA_CON_MAQUINA.duplicate(true)
	sala["creador_id"] = creador
	red.sala = sala
	red.sala_actualizada.emit(sala)


func test_el_creador_ve_una_fila_por_cada_plaza_y_las_libres_dejan_anadir_maquina() -> void:
	_sala_con_maquina()

	assert_eq(_lista().get_child_count(), 4, "una fila por plaza, ocupada o libre")
	assert_not_null(_lista().get_child(1).get_node_or_null("BotonAnadirMaquina"), "plaza 1 libre")
	assert_not_null(_lista().get_child(3).get_node_or_null("BotonAnadirMaquina"), "plaza 3 libre")
	assert_null(_lista().get_child(2).get_node_or_null("BotonAnadirMaquina"), "la plaza 2 ya la ocupa una máquina")


func test_la_maquina_sale_con_su_nombre_y_el_creador_puede_quitarla() -> void:
	_sala_con_maquina()

	var fila: HBoxContainer = _lista().get_child(2)
	assert_eq(fila.get_node("Nombre").text, "Máquina · Difícil")
	assert_not_null(fila.get_node_or_null("BotonQuitarMaquina"))
	var selector: OptionButton = fila.get_node("SelectorDificultad")
	assert_eq(selector.selected, 2, "el selector muestra su dificultad actual")


func test_quien_no_es_creador_ve_la_maquina_pero_no_puede_tocarla_ni_ve_plazas_libres() -> void:
	api.usuario = {"id": "u2", "nombre_visible": "Luis"}
	_sala_con_maquina("u1")

	assert_eq(_lista().get_child_count(), 2, "solo las plazas ocupadas")
	assert_null(_lista().find_child("BotonQuitarMaquina", true, false))
	assert_null(_lista().find_child("BotonAnadirMaquina", true, false))


func test_anadir_maquina_usa_la_dificultad_elegida_y_pide_releer_la_sala() -> void:
	_sala_con_maquina()

	var fila: HBoxContainer = _lista().get_child(1)
	fila.get_node("SelectorDificultad").select(0)
	fila.get_node("BotonAnadirMaquina").pressed.emit()
	await wait_process_frames(2)

	assert_true(api.llamadas.has(["anadir_maquina", "sala-1", "facil", 1]))
	assert_true(red.llamadas.has(["actualizar_sala"]))


func test_por_defecto_la_maquina_es_normal() -> void:
	_sala_con_maquina()

	_lista().get_child(3).get_node("BotonAnadirMaquina").pressed.emit()
	await wait_process_frames(2)

	assert_true(api.llamadas.has(["anadir_maquina", "sala-1", "normal", 3]))


func test_quitar_maquina_llama_al_backend_y_pide_releer_la_sala() -> void:
	_sala_con_maquina()

	_lista().get_child(2).get_node("BotonQuitarMaquina").pressed.emit()
	await wait_process_frames(2)

	assert_true(api.llamadas.has(["quitar_maquina", "sala-1", 2]))
	assert_true(red.llamadas.has(["actualizar_sala"]))


func test_cambiar_la_dificultad_quita_la_maquina_y_sienta_otra_en_la_misma_plaza() -> void:
	_sala_con_maquina()

	_lista().get_child(2).get_node("SelectorDificultad").item_selected.emit(0)
	await wait_process_frames(3)

	var quitar: int = api.llamadas.find(["quitar_maquina", "sala-1", 2])
	var anadir: int = api.llamadas.find(["anadir_maquina", "sala-1", "facil", 2])
	assert_true(quitar != -1 and anadir > quitar, "primero la quita y luego sienta la nueva")


func test_si_el_backend_rechaza_la_maquina_se_muestra_el_error_y_se_vuelve_a_leer_la_sala() -> void:
	api.respuesta_maquina = {"ok": false, "codigo": 409, "datos": {"error": "la sala está llena"}}
	_sala_con_maquina()

	_lista().get_child(1).get_node("BotonAnadirMaquina").pressed.emit()
	await wait_process_frames(2)

	assert_eq(_etiqueta("EtiquetaError").text, "la sala está llena")
	assert_true(_etiqueta("EtiquetaError").visible)


func test_con_maquinas_en_todas_las_plazas_libres_el_creador_puede_empezar() -> void:
	var sala := SALA_CON_MAQUINA.duplicate(true)
	sala["capacidad"] = 2
	sala["jugadores"] = [
		{"usuario_id": "u1", "nombre": "Ana", "posicion": 0, "conectado": true, "maquina": false},
		{"usuario_id": "", "nombre": "Máquina · Normal", "posicion": 1, "conectado": true, "maquina": true, "dificultad": "normal"},
	]
	red.sala = sala
	red.sala_actualizada.emit(sala)

	assert_false(_boton("BotonEmpezar").disabled, "las dos plazas están ocupadas")
