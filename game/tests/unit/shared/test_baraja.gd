extends GutTest


func _ids(cartas: Array[Carta]) -> Array[String]:
	var ids: Array[String] = []
	for carta in cartas:
		ids.append(carta.id)
	return ids


func test_crear_devuelve_40_cartas_distintas() -> void:
	var ids := _ids(Baraja.crear())
	assert_eq(ids.size(), Baraja.TOTAL_CARTAS)
	var unicas := {}
	for id in ids:
		unicas[id] = true
	assert_eq(unicas.size(), Baraja.TOTAL_CARTAS)


func test_crear_tiene_10_cartas_por_palo() -> void:
	var por_palo := {}
	for carta in Baraja.crear():
		por_palo[carta.palo] = por_palo.get(carta.palo, 0) + 1
	for palo in Carta.Palo.values():
		assert_eq(por_palo.get(palo, 0), 10, Carta.Palo.keys()[palo])


func test_barajar_conserva_las_cartas() -> void:
	var cartas := Baraja.crear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	Baraja.barajar(cartas, rng)
	var ids := _ids(cartas)
	var originales := _ids(Baraja.crear())
	ids.sort()
	originales.sort()
	assert_eq(ids, originales)


func test_barajar_cambia_el_orden() -> void:
	var cartas := Baraja.crear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	Baraja.barajar(cartas, rng)
	assert_ne(_ids(cartas), _ids(Baraja.crear()))


func test_barajar_con_la_misma_semilla_es_reproducible() -> void:
	var a := Baraja.crear()
	var b := Baraja.crear()
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 42
	rng_b.seed = 42
	Baraja.barajar(a, rng_a)
	Baraja.barajar(b, rng_b)
	assert_eq(_ids(a), _ids(b))
