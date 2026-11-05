extends GutTest
## Partidas completas de Tute jugadas solo con ReglasTute, sin red: cada jugador
## echa al azar una de las cartas que le permiten y canta siempre que puede.
## Comprueba que las reglas encajan entre sí de principio a fin.

const PARTIDAS := 60
const VALORES := ["As", "Dos", "Tres", "Cuatro", "Cinco", "Seis", "Siete", "Sota", "Caballo", "Rey"]
const PALOS := ["oros", "copas", "espadas", "bastos"]


func _baraja(rng: RandomNumberGenerator) -> Array:
	var cartas: Array = []
	for palo in PALOS:
		for valor in VALORES:
			cartas.append(load("res://data/Cartas/%s_%s.tres" % [valor, palo]))
	for i in range(cartas.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cartas[i]
		cartas[i] = cartas[j]
		cartas[j] = tmp
	return cartas


## Juega una partida entera con ReglasTute sola (sin motor ni red) y devuelve lo que ha pasado.
func _jugar(semilla: int, cantar := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var dador := rng.randi_range(0, 3)
	var manos := ReglasTute.repartir(_baraja(rng), dador)
	var triunfo: int = manos[dador].back().palo
	var ganadas: Array = [[], [], [], []]
	var cantes: Array = [0, 0, 0, 0]
	var cantados: Array = []
	var pendientes := {}
	var errores: Array = []
	var turno := (dador + 1) % 4
	var ultimo := -1
	var bazas := 0
	var cuarentas := 0

	while bazas < ReglasTute.CARTAS_POR_JUGADOR:
		var baza: Array = []
		var quienes: Array = []
		for k in 4:
			var asiento := (turno + k) % 4
			# Un cante pendiente se canta antes de echar carta, como en la partida real.
			if pendientes.has(asiento):
				var cante: Dictionary = pendientes[asiento]
				pendientes.erase(asiento)
				if cante["tipo"] == "tute":
					return {"motivo": "tute", "ganador": ReglasTute.equipo(asiento), "errores": errores}
				cantados.append(cante["palo"])
				cantes[asiento] += cante["puntos"]
				if cante["puntos"] == ReglasTute.PUNTOS_CUARENTA:
					cuarentas += 1
			var permitidas := ReglasTute.cartas_permitidas(manos[asiento], baza, triunfo)
			if permitidas.is_empty():
				errores.append("baza %d: el asiento %d no puede echar ninguna carta" % [bazas, asiento])
				return {"motivo": "error", "errores": errores}
			var carta: Carta = permitidas[rng.randi_range(0, permitidas.size() - 1)]
			var motivo := ReglasTute.motivo_rechazo(manos[asiento], baza, triunfo, carta)
			if motivo != "":
				errores.append("baza %d: carta permitida pero rechazada (%s)" % [bazas, motivo])
			manos[asiento].erase(carta)
			baza.append(carta)
			quienes.append(asiento)

		var ganador: int = quienes[ReglasTute.indice_ganador(baza, triunfo)]
		ganadas[ganador].append_array(baza)
		ultimo = ganador
		turno = ganador
		bazas += 1
		pendientes.clear()
		if cantar and bazas < ReglasTute.CARTAS_POR_JUGADOR:
			for asiento in [ganador, ReglasTute.companero(ganador)]:
				var opcion := ReglasTute.mejor_cante(manos[asiento], triunfo, cantados)
				if not opcion.is_empty():
					pendientes[asiento] = opcion

	return {
		"motivo": "tantos", "errores": errores, "bazas": bazas, "manos": manos, "cuarentas": cuarentas,
		"ganadas": ganadas, "cantes": cantes, "tanteo": ReglasTute.tanteo(ganadas, cantes, ultimo),
	}


func test_partidas_completas_respetan_las_reglas() -> void:
	var por_tantos := 0
	var por_tute := 0
	var con_cantes := 0
	for semilla in PARTIDAS:
		var r := _jugar(semilla)
		assert_eq(r["errores"], [], "Partida %d sin errores de reglas" % semilla)
		if r["motivo"] == "tute":
			por_tute += 1
			continue
		if r["motivo"] != "tantos":
			continue
		por_tantos += 1
		var t: Dictionary = r["tanteo"]
		var cantado := 0
		for puntos in r["cantes"]:
			cantado += puntos
		if cantado > 0:
			con_cantes += 1
		var recogidas := 0
		for cartas in r["ganadas"]:
			recogidas += cartas.size()
		assert_eq(r["bazas"], 10, "Partida %d: se juegan las 10 bazas" % semilla)
		assert_eq(recogidas, 40, "Partida %d: todas las cartas acaban en alguna baza" % semilla)
		assert_eq(t["cartas"][0] + t["cartas"][1], 120, "Partida %d: las cartas suman 120" % semilla)
		assert_eq(t["ultimas"][0] + t["ultimas"][1], 10, "Partida %d: hay unas diez de últimas" % semilla)
		assert_eq(t["total"][0] + t["total"][1], 130 + cantado, "Partida %d: total = 130 + cantes" % semilla)
		for mano in r["manos"]:
			assert_true(mano.is_empty(), "Partida %d: nadie se queda con cartas" % semilla)
	gut.p("%d partidas: %d por tantos, %d por Tute, %d con cantes" % [PARTIDAS, por_tantos, por_tute, con_cantes])
	assert_gt(por_tantos, 0, "Alguna partida termina por tantos")
	assert_gt(con_cantes, 0, "Alguna partida llega a tener cantes")


func test_la_misma_semilla_da_la_misma_partida() -> void:
	var a := _jugar(7)
	var b := _jugar(7)
	assert_eq(a["motivo"], b["motivo"])
	if a["motivo"] == "tantos":
		assert_eq(a["tanteo"]["total"], b["tanteo"]["total"])


## Muchas partidas cantando siempre: cuadran las sumas, y salen las 40 y el Tute.
func test_dos_mil_partidas_cantando() -> void:
	var errores := 0
	var descuadres := 0
	var tutes := 0
	var con_cuarenta := 0
	for semilla in range(1000, 3000):
		var r := _jugar(semilla)
		errores += r["errores"].size()
		if r["motivo"] == "tute":
			tutes += 1
			continue
		var t: Dictionary = r["tanteo"]
		var cantado := 0
		for puntos in r["cantes"]:
			cantado += puntos
		if r["cuarentas"] > 0:
			con_cuarenta += 1
		if t["cartas"][0] + t["cartas"][1] != 120 or t["total"][0] + t["total"][1] != 130 + cantado:
			descuadres += 1
	gut.p("2000 partidas cantando: %d por Tute, %d con las 40" % [tutes, con_cuarenta])
	assert_eq(errores, 0, "Ninguna carta permitida sale rechazada")
	assert_eq(descuadres, 0, "Las cartas suman 120 y el total, 130 más los cantes")
	assert_gt(tutes, 0, "En 2000 partidas tiene que salir algún Tute")
	assert_gt(con_cuarenta, 0, "En 2000 partidas tiene que salir alguna vez las 40")


## Si nadie pulsa el botón de cantar, nunca hay cantes ni se gana por Tute.
func test_dos_mil_partidas_sin_cantar() -> void:
	var raras := 0
	for semilla in range(1000, 3000):
		var r := _jugar(semilla, false)
		if r["motivo"] != "tantos" or r["tanteo"]["total"][0] + r["tanteo"]["total"][1] != 130:
			raras += 1
	assert_eq(raras, 0, "Sin cantes, siempre se acaba por tantos y suman exactamente 130")
