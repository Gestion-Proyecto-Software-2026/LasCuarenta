extends GutTest

var jugador: Jugador

# before_each() se ejecuta automáticamente ANTES de cada test.
# Nos asegura tener un jugador "limpio" para cada prueba.
func before_each():
	jugador = Jugador.new(1, "Pepe")

func test_inicializacion():
	assert_eq(jugador.peer_id, 1, "El ID debe asignarse correctamente al crear el jugador.")
	assert_eq(jugador.nombre, "Pepe", "El nombre debe asignarse correctamente.")
	assert_eq(jugador.mano.size(), 0, "La mano debe empezar vacía.")

func test_recibir_y_obtener_carta():
	# Simulamos una carta creando un nuevo Resource
	var carta_oro = Carta.new()
	carta_oro.id = "oros_1"
	
	jugador.recibir_carta(carta_oro)
	assert_eq(jugador.mano.size(), 1, "El jugador debe tener 1 carta tras recibirla.")
	
	var carta_buscada = jugador.obtener_carta_por_id("oros_1")
	assert_not_null(carta_buscada, "Debería encontrar la carta si el ID coincide.")
	assert_eq(carta_buscada.id, "oros_1", "El ID de la carta recuperada debe ser exacto.")
	
	var carta_inexistente = jugador.obtener_carta_por_id("bastos_3")
	assert_null(carta_inexistente, "Debe devolver null si la carta no existe en la mano.")

func test_quitar_carta():
	var carta = Carta.new()
	carta.id = "espadas_7"
	
	jugador.recibir_carta(carta)
	assert_eq(jugador.mano.size(), 1, "Aseguramos que tiene 1 carta.")
	
	jugador.quitar_carta(carta)
	assert_eq(jugador.mano.size(), 0, "La mano debe volver a 0 tras quitar la carta.")

func test_vaciar_mano():
	jugador.recibir_carta(Carta.new())
	jugador.recibir_carta(Carta.new())
	jugador.cantes_pendientes.append(0) # Oros
	jugador.puede_cambiar_triunfo_pendiente = true
	jugador.puntos_cantes = 40
	
	jugador.vaciar_mano()
	
	assert_eq(jugador.mano.size(), 0, "Se deben vaciar las cartas de la mano.")
	assert_eq(jugador.cantes_pendientes.size(), 0, "Los cantes pendientes deben resetearse.")
	assert_false(jugador.puede_cambiar_triunfo_pendiente, "No puede cambiar el triunfo tras reiniciar.")
	assert_eq(jugador.puntos_cantes, 0, "Los puntos de cante deben volver a 0.")
