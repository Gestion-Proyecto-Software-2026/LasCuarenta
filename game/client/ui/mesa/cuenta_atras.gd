extends Label
## Cuenta atrás del tiempo límite para decidir (PBI-14, issue #37), en la mesa
## común. El servidor manda en cada `estado_partida` cuánto le queda a cada
## jugador esperado (`tiempos_para_decidir`); aquí solo se descuenta en pantalla
## hasta el siguiente estado. Si se agota, quien juega es el servidor, no el
## cliente. La crea partida_mesa.gd.

## Por debajo de estos segundos, tu cuenta atrás se pone en rojo.
const SEGUNDOS_DE_AVISO := 10
const COLOR_NORMAL := Color(0.96, 0.92, 0.80)
const COLOR_AVISO := Color(0.95, 0.35, 0.30)

var _fin_ms := -1  # Time.get_ticks_msec() en que se acaba el tiempo mostrado
var _es_tuyo := false
var _ausente := false
var _posicion := -1
var _num_jugadores := 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Mismo texto con borde negro que el resto de letreros de la mesa.
	var ajustes := LabelSettings.new()
	ajustes.font_size = 20
	ajustes.outline_size = 6
	ajustes.outline_color = Color.BLACK
	ajustes.font_color = COLOR_NORMAL
	label_settings = ajustes


## Lee [code]tiempos_para_decidir[/code] de [param estado]. Si te toca a ti, se
## enseña tu tiempo; si no, el de quien se está esperando.
func actualizar(estado: Dictionary, tu_posicion: int, num_jugadores: int) -> void:
	var elegido: Dictionary = {}
	for tiempo: Dictionary in estado.get("tiempos_para_decidir", []):
		if elegido.is_empty() or tiempo.get("posicion") == tu_posicion:
			elegido = tiempo
	if elegido.is_empty():
		parar()
		return
	_posicion = int(elegido.get("posicion", -1))
	_es_tuyo = _posicion == tu_posicion
	_ausente = bool(elegido.get("ausente", false))
	_num_jugadores = num_jugadores
	_fin_ms = Time.get_ticks_msec() + int(float(elegido.get("segundos", 0.0)) * 1000.0)
	_refrescar()
	visible = true


func parar() -> void:
	_fin_ms = -1
	visible = false


func _process(_delta: float) -> void:
	if _fin_ms >= 0:
		_refrescar()


func _refrescar() -> void:
	var segundos := ceili(maxf(0.0, (_fin_ms - Time.get_ticks_msec()) / 1000.0))
	text = texto(segundos, _es_tuyo, _posicion, _num_jugadores, _ausente)
	var en_aviso := _es_tuyo and segundos <= SEGUNDOS_DE_AVISO
	if label_settings:
		label_settings.font_color = COLOR_AVISO if en_aviso else COLOR_NORMAL


static func texto(segundos: int, es_tuyo: bool, posicion: int, num_jugadores: int, ausente := false) -> String:
	if es_tuyo:
		return "Te quedan %d s para jugar" % segundos
	var quien := "El rival" if num_jugadores == 2 else "J%d" % (posicion + 1)
	if ausente:
		return "%s está ausente: juega el servidor" % quien
	return "%s tiene %d s para jugar" % [quien, segundos]
