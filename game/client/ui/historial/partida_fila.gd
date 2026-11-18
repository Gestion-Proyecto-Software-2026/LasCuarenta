extends PanelContainer
## Una partida de la lista del historial (PBI-06): si se ganó, a qué se jugó,
## el marcador, cuándo, cuánto duró, cómo terminó y con quién.

const Textos := preload("res://client/ui/historial/textos_historial.gd")

@onready var etiqueta_resultado: Label = %EtiquetaResultado
@onready var etiqueta_juego: Label = %EtiquetaJuego
@onready var etiqueta_marcador: Label = %EtiquetaMarcador
@onready var etiqueta_detalle: Label = %EtiquetaDetalle
@onready var etiqueta_jugadores: Label = %EtiquetaJugadores

var partida_id := ""


## Llamar después de add_child, cuando los nodos únicos ya están listos.
## [param desfase_min] son los minutos que la hora local va por delante de UTC.
func configurar(partida: Dictionary, desfase_min: int) -> void:
	var id: Variant = partida.get("partida_id", "")
	partida_id = id if id is String else ""
	etiqueta_resultado.text = Textos.resultado(partida)
	etiqueta_resultado.add_theme_color_override("font_color", Textos.color_resultado(partida))
	etiqueta_juego.text = Textos.juego_y_modo(partida)
	etiqueta_marcador.text = Textos.marcador(partida)
	etiqueta_detalle.text = Textos.detalle(partida, desfase_min)
	etiqueta_jugadores.text = Textos.jugadores(partida)
	etiqueta_jugadores.visible = not etiqueta_jugadores.text.is_empty()
