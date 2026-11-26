extends AcceptDialog
## Panel de ajustes del cliente (PBI-21): una casilla por ajuste del autoload
## Ajustes, que se guarda en cuanto se pulsa (no hay que confirmar nada; el
## botón solo cierra). Se abre desde el lobby (botón "Ajustes") y desde la mesa
## (botón "Ajustes" del chat). Construido en código, como chat_mesa.gd.

const ANCHO := 300.0

## Inyectable en tests (una instancia de ajustes.gd con una ruta temporal).
var ajustes = Ajustes

## "Sonido": si suenan las cartas y el aviso de turno (PBI-21).
var casilla_sonido: CheckButton

## Donde van las casillas, una debajo de otra.
var _casillas: VBoxContainer


func _ready() -> void:
	title = "Ajustes"
	ok_button_text = "Cerrar"
	_construir()
	# Se lee al abrirse: el ajuste ha podido cambiar desde otra pantalla.
	about_to_popup.connect(leer_ajustes)
	leer_ajustes()


## Pone las casillas como están los ajustes, sin volver a guardarlos.
func leer_ajustes() -> void:
	casilla_sonido.set_pressed_no_signal(ajustes.sonido)


func _on_sonido_cambiado(activado: bool) -> void:
	ajustes.poner_sonido(activado)


func _construir() -> void:
	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 10)
	columna.custom_minimum_size = Vector2(ANCHO, 0)
	add_child(columna)

	_casillas = VBoxContainer.new()
	_casillas.name = "Casillas"
	columna.add_child(_casillas)
	casilla_sonido = _crear_casilla("CasillaSonido", "Sonido", "Las cartas al repartir, robar y jugarlas, y un aviso cuando te toca.")
	casilla_sonido.toggled.connect(_on_sonido_cambiado)

	var nota := Label.new()
	nota.text = "Se guardan en este ordenador y se recuerdan al volver a abrir el juego."
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Con un ancho fijo: un texto que se parte en líneas sin ancho mínimo pide
	# muchísimo alto y el diálogo se abre fuera de la ventana.
	nota.custom_minimum_size = Vector2(ANCHO, 0)
	nota.add_theme_font_size_override("font_size", 12)
	nota.modulate = Color(1, 1, 1, 0.7)
	columna.add_child(nota)


func _crear_casilla(nombre: String, texto: String, ayuda: String) -> CheckButton:
	var casilla := CheckButton.new()
	casilla.name = nombre
	casilla.text = texto
	casilla.tooltip_text = ayuda
	_casillas.add_child(casilla)
	return casilla
