extends GutTest

var juego: Juego_Guinote
var jugador: Jugador

# Función de ayuda para fabricar cartas rápidas para los tests
func crear_carta(palo: FuncionesGlobales.palos, valor: int) -> Carta:
	var c = Carta.new()
	c.palo = palo
	c.valor = valor
	return c

func before_each():
	juego = autofree(Juego_Guinote.new())
	juego.baraja = [] # Vaciamos la baraja por defecto
	juego.palos_cantados = [] # Vaciamos los cantes
	juego.carta_triunfo = crear_carta(FuncionesGlobales.palos.copas, 1) # As de Copas
	juego.palo_triunfo = FuncionesGlobales.palos.copas
	
	jugador = Jugador.new(1, "Tester")
	juego.jugadores.append(jugador)
	add_child(juego)
# =========================================================
# TEST 1: ROBAR UNA CARTA NO TE DEJA CANTAR EN ESE TURNO
# =========================================================
func test_evaluar_cantes_ignora_cartas_robadas_en_ese_turno():
	# 1. Le damos 5 cartas al jugador, incluida la Sota de Oros (valor 10)
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.oros, 10))
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.espadas, 3))
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.bastos, 4))
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.espadas, 5))
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.copas, 6))
	
	# Le damos una baraja falsa de 1 carta para que pase el "if baraja.size() > 0"
	juego.baraja.append(crear_carta(FuncionesGlobales.palos.oros, 12)) # Rey de Oros
	
	# 2. Simulamos el momento exacto ANTES de robar (cuando acaba la baza)
	juego.evaluar_acciones_previas_al_robo(jugador)
	
	# COMPROBACIÓN: Como no tiene el Rey AÚN, no puede cantar
	assert_eq(jugador.cantes_pendientes.size(), 0, "No debe poder cantar solo con la Sota.")
	
	# 3. Simulamos el momento del robo: ahora sí recibe el Rey de Oros
	var carta_robada = juego.baraja.pop_back()
	jugador.recibir_carta(carta_robada)
	
	# COMPROBACIÓN VITAL: Aunque ahora tenga Sota y Rey, sus 'cantes_pendientes' deben seguir vacíos
	# porque la ventana de oportunidad ya se evaluó.
	assert_eq(jugador.cantes_pendientes.size(), 0, "Robar el Rey NO le permite cantar de forma retroactiva.")
	
	# 4. Simulamos que pasa un turno entero y volvemos a evaluar
	juego.baraja.append(crear_carta(FuncionesGlobales.palos.bastos, 1)) # Rellenamos baraja
	juego.evaluar_acciones_previas_al_robo(jugador)
	
	# COMPROBACIÓN: ¡Ahora sí! En su nuevo turno, la máquina ve que ya tenía la Sota y el Rey.
	assert_true(jugador.cantes_pendientes.has(FuncionesGlobales.palos.oros), "En el turno siguiente SÍ debe detectar el cante de las 20.")

# =========================================================
# TEST 2: TIRAR UNA CARTA ANULA LAS OPCIONES PENDIENTES
# =========================================================
func test_tirar_carta_anula_cantar_y_cambiar():
	# 1. Forzamos que el jugador tenga los permisos activos
	jugador.cantes_pendientes.append(FuncionesGlobales.palos.copas)
	jugador.puede_cambiar_triunfo_pendiente = true
	
	# 2. Simulamos la acción de procesar jugada (el jugador tira una carta a la mesa)
	var carta_lanzada = crear_carta(FuncionesGlobales.palos.espadas, 1)
	juego._procesar_jugada(jugador, carta_lanzada)
	
	# COMPROBACIÓN: Tirar la carta debe haber vaciado sus acciones pendientes inmediatamente
	assert_eq(jugador.cantes_pendientes.size(), 0, "Al tirar carta, pierde su derecho a cantar.")
	assert_false(jugador.puede_cambiar_triunfo_pendiente, "Al tirar carta, pierde su derecho a cambiar el 7.")

# =========================================================
# TEST 3: NO SE PUEDE CANTAR DOS VECES EL MISMO PALO
# =========================================================
func test_no_se_puede_cantar_palo_repetido():
	# 1. Le damos Sota y Rey de Espadas
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.espadas, 10))
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.espadas, 12))
	juego.baraja.append(crear_carta(FuncionesGlobales.palos.oros, 1))
	
	# Marcamos internamente que las Espadas ya se cantaron previamente en la partida
	juego.palos_cantados.append(FuncionesGlobales.palos.espadas)
	
	# 2. Evaluamos su mano
	juego.evaluar_acciones_previas_al_robo(jugador)
	
	# COMPROBACIÓN: Como las Espadas están en 'palos_cantados', no se le debe añadir a pendientes
	assert_eq(jugador.cantes_pendientes.size(), 0, "No debe permitir cantar un palo que ya se cantó.")

# =========================================================
# TEST 4: EL 7 NO SE PUEDE CAMBIAR POR CARTAS INFERIORES
# =========================================================
func test_siete_solo_cambia_por_figuras_mayores():
	juego.palo_triunfo = FuncionesGlobales.palos.oros
	jugador.recibir_carta(crear_carta(FuncionesGlobales.palos.oros, 7)) # Tiene el 7 de triunfo en mano
	juego.baraja.append(crear_carta(FuncionesGlobales.palos.bastos, 1)) # Carta cualquiera para que la baraja > 0
	
	# CASO A: El triunfo en la mesa es un 5 (rango 3). El 7 (rango 5) NO puede cambiar un 5.
	juego.carta_triunfo = crear_carta(FuncionesGlobales.palos.oros, 5) 
	juego.evaluar_acciones_previas_al_robo(jugador)
	assert_false(jugador.puede_cambiar_triunfo_pendiente, "El 7 no puede cambiarse por un 5 (es de rango inferior o igual).")
	
	# CASO B: El triunfo en la mesa es un Caballo (11, rango 6). El 7 SÍ puede cambiarlo.
	juego.carta_triunfo = crear_carta(FuncionesGlobales.palos.oros, 11)
	juego.evaluar_acciones_previas_al_robo(jugador)
	assert_true(jugador.puede_cambiar_triunfo_pendiente, "El 7 SÍ debe poder cambiarse por el Caballo.")
