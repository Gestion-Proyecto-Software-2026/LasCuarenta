extends GutTest


func test_id_combina_palo_y_valor() -> void:
	assert_eq(Carta.new(Carta.Palo.ESPADAS, 12).id, "espadas_12")
	assert_eq(Carta.new(Carta.Palo.OROS, 1).id, "oros_1")


func test_desde_id_reconstruye_la_carta() -> void:
	var carta := Carta.desde_id("copas_7")
	assert_not_null(carta)
	assert_eq(carta.palo, Carta.Palo.COPAS)
	assert_eq(carta.valor, 7)


func test_desde_id_rechaza_ids_invalidos() -> void:
	for id in ["", "copas", "copas_8", "copas_9", "copas_13", "copas_x", "triunfo_1", "copas_1_2"]:
		assert_null(Carta.desde_id(id), "'%s' no debería ser una carta válida" % id)


func test_id_ida_y_vuelta_para_toda_la_baraja() -> void:
	for carta in Baraja.crear():
		assert_true(Carta.desde_id(carta.id).es_igual(carta), carta.id)


func test_es_igual_compara_por_valor() -> void:
	var a := Carta.new(Carta.Palo.BASTOS, 10)
	assert_true(a.es_igual(Carta.new(Carta.Palo.BASTOS, 10)))
	assert_false(a.es_igual(Carta.new(Carta.Palo.BASTOS, 11)))
	assert_false(a.es_igual(null))
