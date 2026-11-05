extends GutTest
## La mesa (tapete) por sí sola, sin red: los letreros que enseña al jugador.

const ESCENA_TAPETE := preload("res://compartido/Escenas/tapete/Tapete.tscn")


func _tapete() -> Control:
	var tapete: Control = ESCENA_TAPETE.instantiate()
	add_child_autofree(tapete)
	return tapete


func _letreros(tapete: Control) -> Array:
	return tapete.get_children().filter(func(n: Node) -> bool: return n is Label and n.visible)


func test_avisar_error_enseña_el_motivo_dentro_de_la_ventana() -> void:
	var tapete := _tapete()
	tapete.avisar_error("Tienes que asistir: echa una carta de copas.")
	var letreros := _letreros(tapete).filter(func(l: Label) -> bool: return l.text.begins_with("Tienes que asistir"))
	assert_eq(letreros.size(), 1, "Sale un letrero con el motivo")
	var rect := tapete.get_viewport_rect()
	var letrero: Label = letreros[0]
	assert_true(rect.has_point(letrero.position), "El letrero está dentro de la ventana")


func test_en_la_vuelta_se_ven_las_idas() -> void:
	var tapete := _tapete()
	tapete.asientos = [101, 202]
	tapete.nombres_por_peer = {101: "Jugador 1", 202: "Jugador 2"}
	assert_eq(tapete._marcador_de_bazas({"mano": "idas", "tanteo_idas": []}), "", "En las idas no hay nada que enseñar")
	assert_eq(tapete._marcador_de_bazas({"mano": "vuelta", "tanteo_idas": [81, 69]}), "Vuelta · idas: J1 81 · J2 69")
	tapete.asientos = [101, 202, 303, 404]
	assert_eq(tapete._marcador_de_bazas({"mano": "vuelta", "tanteo_idas": [70, 60]}),
		"Vuelta · idas: Pareja A 70 · Pareja B 60")


func test_etiquetas_con_y_sin_nombre() -> void:
	var tapete := _tapete()
	tapete.asientos = [101, 202]
	tapete.nombres_por_peer = {101: "Jugador 1", 202: "Lorenzo"}
	assert_eq(tapete._etiqueta_de(101), "J1", "Sin nombre elegido, solo el asiento")
	assert_eq(tapete._etiqueta_de(202), "J2 · Lorenzo")
	assert_eq(tapete._abreviatura(202), "J2", "En los textos de la mesa, el asiento")


func test_limpiar_nombre() -> void:
	var partida := load("res://escenas/partida.gd")
	assert_eq(partida.limpiar_nombre("  Lorenzo   Duarte "), "Lorenzo Duarte")
	assert_eq(partida.limpiar_nombre("   "), "", "Vacío: se usará Jugador N")
	assert_eq(partida.limpiar_nombre("Un nombre larguísimo de verdad").length(), 14)


## Mesa de Mus a 2 con una mano en la que está el jugador local (asiento 0).
func _mesa_mus(mano: Array) -> Control:
	var tapete := _tapete()
	tapete.asientos = [tapete.multiplayer.get_unique_id(), 999]
	tapete.generar_mano_desde_array(mano)
	tapete._mus = MesaMus.new(tapete)
	return tapete


func test_mus_elegir_cartas_para_descartarse() -> void:
	var tapete := _mesa_mus(["As_oros", "Cuatro_copas", "Rey_bastos", "Cinco_espadas"])
	var mus: MesaMus = tapete._mus
	tapete._vista = {"fase": "descarte", "turno": 0}
	assert_true(mus.puedo_descartar(), "Es mi turno de descarte")
	var cuatro = tapete.cartas_en_mano[1]
	mus.alternar_descarte(cuatro)
	assert_eq(mus.seleccion, [cuatro], "Pulsar una carta la elige")
	assert_eq(cuatro.self_modulate, MesaMus.COLOR_ELEGIDA, "Y se ve elegida")
	mus.alternar_descarte(cuatro)
	assert_eq(mus.seleccion, [], "Pulsarla otra vez la deja")
	tapete._vista = {"fase": "descarte", "turno": 1}
	assert_false(mus.puedo_descartar(), "Fuera de mi turno no se elige")


func test_mus_textos_de_los_botones() -> void:
	var tapete := _mesa_mus([])
	var mus: MesaMus = tapete._mus
	tapete._vista = {"envite": {}}
	assert_eq(mus.texto_jugada({"tipo": MotorDeJuego.ENVIDAR, "cantidad": 2}), "Envido 2")
	tapete._vista = {"envite": {"apuesta": 2}}
	assert_eq(mus.texto_jugada({"tipo": MotorDeJuego.ENVIDAR, "cantidad": 5}), "Subo 5")
	assert_eq(mus.texto_jugada({"tipo": MotorDeJuego.NO_MUS}), "No hay mus")
	assert_eq(mus.texto_jugada({"tipo": MotorDeJuego.CANTAR, "palo": "oros"}), "", "Lo que no es del Mus lo pone la mesa")


func test_mus_autojugar_se_descarta_de_lo_que_no_son_reyes_ni_ases() -> void:
	var tapete := _mesa_mus([])
	tapete._vista = {"mi_mano": ["Rey_oros", "Cuatro_copas", "As_bastos", "Sota_espadas"], "rondas_de_descarte": 0}
	var jugada: Dictionary = tapete._mus.jugada_automatica([{"tipo": MotorDeJuego.DESCARTAR, "cartas": ["Rey_oros"]}])
	assert_eq(jugada, {"tipo": MotorDeJuego.DESCARTAR, "cartas": ["Cuatro_copas", "Sota_espadas"]})


func test_un_aviso_nuevo_sustituye_al_anterior() -> void:
	var tapete := _tapete()
	tapete.avisar_error("Espera tu turno.")
	tapete.avisar_error("No tienes esa carta.")
	await get_tree().process_frame
	var textos := _letreros(tapete).map(func(l: Label) -> String: return l.text)
	assert_does_not_have(textos, "Espera tu turno.")
	assert_has(textos, "No tienes esa carta.")
