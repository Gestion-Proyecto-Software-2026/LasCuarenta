extends GutTest

var juego: Juego_Guinote

func before_each():
	# Al ser un Node, usamos autofree() para que GUT lo elimine de la memoria 
	# al acabar el test y no genere "Memory Leaks" (fugas de memoria).
	juego = autofree(Juego_Guinote.new())

func test_obtener_puntos_carta():
	var carta = Carta.new()
	
	# Probamos el As
	carta.valor = 1
	assert_eq(juego.obtener_puntos_carta(carta), 11, "El As (1) debe valer 11 puntos.")
	
	# Probamos el Tres
	carta.valor = 3
	assert_eq(juego.obtener_puntos_carta(carta), 10, "El Tres (3) debe valer 10 puntos.")
	
	# Probamos el Rey
	carta.valor = 12
	assert_eq(juego.obtener_puntos_carta(carta), 4, "El Rey (12) debe valer 4 puntos.")
	
	# Probamos una carta blanca
	carta.valor = 5
	assert_eq(juego.obtener_puntos_carta(carta), 0, "Las cartas blancas no valen puntos.")

func test_obtener_rango_carta():
	var carta1 = Carta.new()
	var carta2 = Carta.new()
	
	carta1.valor = 3   # El Tres
	carta2.valor = 12  # El Rey
	
	var rango1 = juego.obtener_rango_carta(carta1)
	var rango2 = juego.obtener_rango_carta(carta2)
	
	assert_true(rango1 > rango2, "El rango del Tres debe ser mayor que el rango del Rey en el guiñote.")
