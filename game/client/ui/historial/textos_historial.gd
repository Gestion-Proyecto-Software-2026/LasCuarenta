extends RefCounted
## Los textos de la pantalla de historial (PBI-06) que se sacan de lo que manda
## el backend en GET /usuarios/:id/historial y /estadisticas
## (docs/analisis_funcional_app.md §5): juego y modo, cómo terminó, marcador,
## fecha y duración de cada partida, y el resumen de estadísticas. Son funciones
## puras, como textos_mesa.gd, para poder probarlas sin la escena; la fecha
## recibe el desfase horario como parámetro por lo mismo.

const NOMBRES_JUEGO := {"guinote": "Guiñote", "mus": "Mus", "tute": "Tute"}
## Cómo terminó una partida que se jugó hasta el final: el `motivo` del motor
## (Guiñote y Tute; el Mus no lo tiene).
const MOTIVOS := {
	"tantos": "Por tantos",
	"tute": "Cantó Tute",
	"vuelta": "En la vuelta",
	"capote": "Capote",
}
## Partidas cortadas por algo ajeno a las reglas: la `causa` manda sobre el motivo.
const CAUSAS := {"renuncio": "Renuncio admitido en el chat"}
const SIN_MOTIVO := "Partida completa"
const COLOR_VICTORIA := Color(0.18, 0.49, 0.196, 1)
const COLOR_DERROTA := Color(0.643, 0.11, 0.122, 1)

const _DIAS_POR_MES := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
## Lo que se usa de una fecha ISO 8601 del backend ("2026-11-18T10:24:13.000Z"):
## la fecha y la hora hasta los segundos, que siempre vienen en UTC.
static var _patron_fecha := RegEx.create_from_string(
	"^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2}):(\\d{2})")


static func nombre_juego(juego: String) -> String:
	return NOMBRES_JUEGO.get(juego, juego.capitalize())


## "por parejas" en las mesas de 4 y "1 contra 1" en las de 2.
static func modo(num_jugadores: int) -> String:
	match num_jugadores:
		4:
			return "por parejas"
		2:
			return "1 contra 1"
	return "%d jugadores" % num_jugadores


## "Guiñote · por parejas", "Mus · 1 contra 1"...
static func juego_y_modo(partida: Dictionary) -> String:
	return "%s · %s" % [nombre_juego(_texto(partida.get("juego"))), modo(_entero(partida.get("num_jugadores")))]


static func resultado(partida: Dictionary) -> String:
	return "VICTORIA" if _gano(partida) else "DERROTA"


static func color_resultado(partida: Dictionary) -> Color:
	return COLOR_VICTORIA if _gano(partida) else COLOR_DERROTA


## Cómo terminó: "Por tantos", "Cantó Tute"..., "Renuncio admitido en el chat"
## si se cortó por eso, o "Partida completa" si no hay más que decir (el Mus).
static func causa(partida: Dictionary) -> String:
	var causa_fin := _texto(partida.get("causa"))
	if CAUSAS.has(causa_fin):
		return CAUSAS[causa_fin]
	return MOTIVOS.get(_texto(partida.get("motivo")), SIN_MOTIVO)


## Tus tantos contra los del rival, "105 – 52"; en el Mus son juegos ganados,
## "2 – 1 juegos".
static func marcador(partida: Dictionary) -> String:
	var texto := "%d – %d" % [_entero(partida.get("puntos_equipo")), _entero(partida.get("puntos_rival"))]
	return texto + " juegos" if _texto(partida.get("juego")) == "mus" else texto


## "18/11/2026 11:24": [param iso] (en UTC) pasado a la hora local, que va
## [param desfase_min] minutos por delante de UTC (ver [method desfase_del_sistema]).
## "" si [param iso] no es una fecha.
static func fecha_local(iso: Variant, desfase_min: int) -> String:
	var segundos := _segundos_unix(iso)
	if segundos < 0:
		return ""
	var fecha := Time.get_datetime_dict_from_unix_time(segundos + desfase_min * 60)
	return "%02d/%02d/%04d %02d:%02d" % [fecha["day"], fecha["month"], fecha["year"], fecha["hour"], fecha["minute"]]


## Minutos que la hora local va ahora por delante de UTC (60 en invierno en la
## península). Godot solo da el desfase de este momento, así que una partida de
## antes de un cambio de hora sale con una hora de diferencia.
static func desfase_del_sistema() -> int:
	return _entero(Time.get_time_zone_from_system().get("bias"))


## "24 min" de [param fecha_inicio] a [param fecha_fin]. "" si falta alguna o
## son la misma: el backend pone la de fin cuando no sabe cuándo empezó.
static func duracion(fecha_inicio: Variant, fecha_fin: Variant) -> String:
	var inicio := _segundos_unix(fecha_inicio)
	var fin := _segundos_unix(fecha_fin)
	if inicio < 0 or fin <= inicio:
		return ""
	if fin - inicio < 60:
		return "menos de 1 min"
	return "%d min" % roundi((fin - inicio) / 60.0)


## La segunda línea de una partida: "18/11/2026 11:24 · 24 min · Por tantos".
static func detalle(partida: Dictionary, desfase_min: int) -> String:
	var partes := PackedStringArray()
	for parte: String in [
		fecha_local(partida.get("fecha_fin"), desfase_min),
		duracion(partida.get("fecha_inicio"), partida.get("fecha_fin")),
		causa(partida),
	]:
		if not parte.is_empty():
			partes.append(parte)
	return " · ".join(partes)


## Con quién se jugó: "Con Marta · Contra Luis y Pedro" por parejas, o
## "Contra Luis" en el 1 contra 1.
static func jugadores(partida: Dictionary) -> String:
	var partes := PackedStringArray()
	var companeros := _nombres(partida.get("companeros"))
	if not companeros.is_empty():
		partes.append("Con " + companeros)
	var rivales := _nombres(partida.get("rivales"))
	if not rivales.is_empty():
		partes.append("Contra " + rivales)
	return " · ".join(partes)


## "12 partidas · 7 victorias · 5 derrotas · 58,3 % de victorias" a partir de
## los `totales` de las estadísticas.
static func resumen(totales: Variant) -> String:
	var t: Dictionary = totales if totales is Dictionary else {}
	return "%s · %s de victorias" % [_cuentas(t), porcentaje(t.get("porcentaje_victorias"))]


## Una línea por cada juego con partidas: "Guiñote: 8 partidas · 5 victorias ·
## 3 derrotas · 62,5 %". Los juegos sin partidas no salen.
static func lineas_por_juego(por_juego: Variant) -> PackedStringArray:
	var lineas := PackedStringArray()
	if not por_juego is Array:
		return lineas
	for juego: Variant in por_juego:
		if juego is Dictionary and _entero(juego.get("jugadas")) > 0:
			lineas.append("%s: %s · %s" % [
				nombre_juego(_texto(juego.get("juego"))), _cuentas(juego), porcentaje(juego.get("porcentaje_victorias"))])
	return lineas


## "58,3 %", con coma decimal y sin decimales si no hacen falta ("50 %").
static func porcentaje(valor: Variant) -> String:
	var redondeado := snappedf(_numero(valor), 0.1)
	if is_equal_approx(redondeado, roundf(redondeado)):
		return "%d %%" % roundi(redondeado)
	return ("%.1f %%" % redondeado).replace(".", ",")


## "Racha: 3 victorias seguidas · Mejor racha: 4 victorias seguidas", sin la
## parte que no haya (nada si todavía no hay partidas).
static func rachas(racha_actual: Variant, mejor_racha_victorias: Variant) -> String:
	var partes := PackedStringArray()
	if racha_actual is Dictionary:
		var tipo := _texto(racha_actual.get("tipo"))
		var partidas := _entero(racha_actual.get("partidas"))
		if tipo in ["victoria", "derrota"] and partidas > 0:
			partes.append("Racha: " + _seguidas(partidas, tipo))
	var mejor := _entero(mejor_racha_victorias)
	if mejor > 0:
		partes.append("Mejor racha: " + _seguidas(mejor, "victoria"))
	return " · ".join(partes)


## Los últimos resultados como letras de colores, del más reciente al más
## antiguo: una V verde por victoria y una D roja por derrota, en BBCode para
## un RichTextLabel.
static func ultimos_resultados(resultados: Variant) -> String:
	var letras := PackedStringArray()
	if not resultados is Array:
		return ""
	for resultado_partida: Variant in resultados:
		match resultado_partida:
			"victoria":
				letras.append("[color=#%s]V[/color]" % COLOR_VICTORIA.to_html(false))
			"derrota":
				letras.append("[color=#%s]D[/color]" % COLOR_DERROTA.to_html(false))
	return " ".join(letras)


## "8 partidas · 5 victorias · 3 derrotas", en singular cuando es 1.
static func _cuentas(datos: Dictionary) -> String:
	return "%s · %s · %s" % [
		_contar(_entero(datos.get("jugadas")), "partida"),
		_contar(_entero(datos.get("victorias")), "victoria"),
		_contar(_entero(datos.get("derrotas")), "derrota"),
	]


static func _contar(cuantas: int, palabra: String) -> String:
	return "%d %s" % [cuantas, palabra if cuantas == 1 else palabra + "s"]


## "1 victoria" o "3 victorias seguidas".
static func _seguidas(cuantas: int, tipo: String) -> String:
	return "1 %s" % tipo if cuantas == 1 else "%d %ss seguidas" % [cuantas, tipo]


## "Ana", "Ana y Luis" o "Ana, Luis y Pedro"; "Jugador N" (su asiento) si
## alguno no tiene nombre.
static func _nombres(lista: Variant) -> String:
	var nombres := PackedStringArray()
	if not lista is Array:
		return ""
	for jugador: Variant in lista:
		if jugador is Dictionary:
			var nombre := _texto(jugador.get("nombre_visible"))
			nombres.append(nombre if not nombre.is_empty() else "Jugador %d" % (_entero(jugador.get("posicion")) + 1))
	if nombres.size() <= 1:
		return "".join(nombres)
	return "%s y %s" % [", ".join(nombres.slice(0, nombres.size() - 1)), nombres[nombres.size() - 1]]


## Segundos desde 1970 de una fecha ISO 8601 en UTC, o -1 si no lo es. Se
## comprueba antes cada campo porque Time da un error con fechas imposibles.
static func _segundos_unix(iso: Variant) -> int:
	if not iso is String:
		return -1
	var encontrado := _patron_fecha.search(iso)
	if encontrado == null:
		return -1
	var campos: Array[int] = []
	for i in range(1, 7):
		campos.append(encontrado.get_string(i).to_int())
	var anio := campos[0]
	var mes := campos[1]
	var dia := campos[2]
	if mes < 1 or mes > 12 or dia < 1 or dia > _dias_del_mes(anio, mes) \
			or campos[3] > 23 or campos[4] > 59 or campos[5] > 59:
		return -1
	return Time.get_unix_time_from_datetime_dict({
		"year": anio, "month": mes, "day": dia,
		"hour": campos[3], "minute": campos[4], "second": campos[5],
	})


static func _dias_del_mes(anio: int, mes: int) -> int:
	var bisiesto := anio % 4 == 0 and (anio % 100 != 0 or anio % 400 == 0)
	return 29 if mes == 2 and bisiesto else _DIAS_POR_MES[mes - 1]


static func _gano(partida: Dictionary) -> bool:
	return partida.get("gano") is bool and partida["gano"]


## Los números del JSON llegan como float; cualquier otra cosa cuenta como 0.
static func _entero(valor: Variant) -> int:
	return roundi(valor) if valor is float or valor is int else 0


static func _numero(valor: Variant) -> float:
	return float(valor) if valor is float or valor is int else 0.0


static func _texto(valor: Variant) -> String:
	return valor if valor is String else ""
