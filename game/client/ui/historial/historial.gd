extends Control
## Historial y estadísticas de un jugador (PBI-06): sus partidas terminadas, de
## la más reciente a la más antigua, y un resumen de cómo le va. Se abre desde
## el lobby para ver el tuyo, o con [member usuario_a_consultar] para ver el de
## otro jugador si lo tiene público. Todo va por ClienteApi (REST,
## docs/analisis_funcional_app.md §5).

const ESCENA_FILA := preload("res://client/ui/historial/partida_fila.tscn")
const Textos := preload("res://client/ui/historial/textos_historial.gd")
const ESCENA_LOBBY := "res://client/ui/lobby/lobby.tscn"
const ESCENA_LOGIN := "res://client/ui/login/login.tscn"
## Opciones del filtro: lo que se ve y el `juego` que se pide ("" = todos).
const FILTROS := [["Todos", ""], ["Guiñote", "guinote"], ["Mus", "mus"], ["Tute", "tute"]]
const AVISO_PRIVADO := "Este jugador tiene su historial en privado."
const AVISO_SIN_CONEXION := "No se pudo conectar con el servidor"

## De quién es el historial que se abre ("me" = el del usuario de la sesión).
## Quien quiera enseñar el de otro jugador (p. ej. el ranking, PBI-07) lo pone
## antes de cambiar de escena; [method _ready] lo lee y lo deja otra vez en
## "me", para que al volver a abrirlo desde el lobby salga el tuyo.
static var usuario_a_consultar := "me"

@onready var etiqueta_subtitulo: Label = %EtiquetaSubtitulo
@onready var panel_estadisticas: VBoxContainer = %PanelEstadisticas
@onready var etiqueta_resumen: Label = %EtiquetaResumen
@onready var etiqueta_por_juego: Label = %EtiquetaPorJuego
@onready var etiqueta_rachas: Label = %EtiquetaRachas
@onready var ultimos_resultados: RichTextLabel = %UltimosResultados
@onready var opcion_juego: OptionButton = %OpcionJuego
@onready var interruptor_publico: CheckButton = %InterruptorPublico
@onready var boton_actualizar: Button = %BotonActualizar
@onready var etiqueta_error: Label = %EtiquetaError
@onready var lista: ScrollContainer = %Lista
@onready var lista_partidas: VBoxContainer = %ListaPartidas
@onready var etiqueta_vacia: Label = %EtiquetaVacia
@onready var boton_volver: Button = %BotonVolver

## Por defecto el autoload; los tests de GUT lo sustituyen por un doble.
var api = ClienteApi
## Cambia de pantalla. Los tests lo sustituyen para no navegar de verdad.
var ir_a: Callable = func(escena: String) -> void: get_tree().change_scene_to_file(escena)
## Minutos que la hora local va por delante de UTC, para las fechas de la
## lista. Los tests lo fijan para que no dependan de dónde se ejecutan.
var desfase_min := Textos.desfase_del_sistema()
## A quién se le piden el historial y las estadísticas: "me" o su id.
var usuario_id := "me"

var _propio := true
## Si el backend ya ha dicho si tu historial es público. Hasta entonces (p. ej.
## si fallan las estadísticas) el interruptor no se puede tocar: enseñaría el
## valor por defecto de la escena, no el tuyo.
var _privacidad_conocida := false


func _ready() -> void:
	usuario_id = usuario_a_consultar
	usuario_a_consultar = "me"
	if not api.esta_autenticado():
		ir_a.call_deferred(ESCENA_LOGIN)
		return
	# Tu propio id (p. ej. al pulsarte en el ranking) también es tu historial.
	_propio = usuario_id in ["me", "", str(api.usuario.get("id", ""))]
	if _propio:
		usuario_id = "me"
	etiqueta_subtitulo.text = "Tus partidas" if _propio else "Partidas de otro jugador"
	interruptor_publico.visible = _propio
	etiqueta_error.visible = false
	opcion_juego.clear()
	for filtro: Array in FILTROS:
		opcion_juego.add_item(filtro[0])
	opcion_juego.item_selected.connect(_on_filtro_seleccionado)
	interruptor_publico.toggled.connect(_on_interruptor_publico_toggled)
	boton_actualizar.pressed.connect(_on_boton_actualizar_pressed)
	boton_volver.pressed.connect(_on_boton_volver_pressed)
	refrescar()


## Pide las estadísticas y, si se pueden ver, las partidas.
func refrescar() -> void:
	_ocultar_error()
	_bloquear(true)
	var resultado: Dictionary = await api.estadisticas(usuario_id)
	if resultado.ok and resultado.datos is Dictionary:
		_pintar_estadisticas(resultado.datos)
		await _cargar_partidas()
	else:
		# Lo de antes ya no vale (p. ej. el jugador acaba de hacer privado su historial).
		panel_estadisticas.visible = false
		_vaciar_lista()
		_bloquear(false)
		_tratar_error(resultado)


## Pide las partidas del juego elegido en el filtro y las pinta.
func _cargar_partidas() -> void:
	_bloquear(true)
	var resultado: Dictionary = await api.historial(usuario_id, _juego_filtrado())
	_bloquear(false)
	if resultado.ok and resultado.datos is Array:
		_pintar_partidas(resultado.datos)
	else:
		# Sin borrar la lista quedarían a la vista partidas de otro filtro.
		_vaciar_lista()
		_tratar_error(resultado)


func _pintar_estadisticas(datos: Dictionary) -> void:
	var nombre: Variant = datos.get("nombre_visible")
	if not _propio and nombre is String and not nombre.is_empty():
		etiqueta_subtitulo.text = "Partidas de %s" % nombre
	if _propio and datos.get("historial_publico") is bool:
		interruptor_publico.set_pressed_no_signal(datos["historial_publico"])
		_privacidad_conocida = true
	etiqueta_resumen.text = Textos.resumen(datos.get("totales"))
	var por_juego := Textos.lineas_por_juego(datos.get("por_juego"))
	etiqueta_por_juego.text = "\n".join(por_juego)
	etiqueta_por_juego.visible = not por_juego.is_empty()
	etiqueta_rachas.text = Textos.rachas(datos.get("racha_actual"), datos.get("mejor_racha_victorias"))
	etiqueta_rachas.visible = not etiqueta_rachas.text.is_empty()
	var ultimos := Textos.ultimos_resultados(datos.get("ultimos_resultados"))
	ultimos_resultados.text = "[center]Últimos resultados: %s[/center]" % ultimos
	ultimos_resultados.visible = not ultimos.is_empty()
	panel_estadisticas.visible = true


func _pintar_partidas(partidas: Array) -> void:
	_vaciar_lista()
	var ordenadas := ordenar_por_fecha(partidas)
	lista.visible = not ordenadas.is_empty()
	etiqueta_vacia.visible = ordenadas.is_empty()
	for partida: Dictionary in ordenadas:
		var fila = ESCENA_FILA.instantiate()
		lista_partidas.add_child(fila)
		fila.configurar(partida, desfase_min)


## De la más reciente a la más antigua por `fecha_fin` (las que no la tienen,
## al final) y, a igual fecha, por `partida_id` descendente, como el backend:
## ya vienen así, pero no cuesta asegurarlo. Descarta lo que no sea una partida.
static func ordenar_por_fecha(partidas: Array) -> Array:
	var ordenadas := partidas.filter(func(partida: Variant) -> bool: return partida is Dictionary)
	ordenadas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Las fechas ISO 8601 del backend se ordenan bien como texto.
		var fecha_a := _cadena(a.get("fecha_fin"))
		var fecha_b := _cadena(b.get("fecha_fin"))
		if fecha_a != fecha_b:
			return fecha_a > fecha_b
		return _cadena(a.get("partida_id")) > _cadena(b.get("partida_id")))
	return ordenadas


static func _cadena(valor: Variant) -> String:
	return valor if valor is String else ""


func _vaciar_lista() -> void:
	for fila in lista_partidas.get_children():
		lista_partidas.remove_child(fila)
		fila.queue_free()
	lista.visible = false
	etiqueta_vacia.visible = false


func _juego_filtrado() -> String:
	return FILTROS[maxi(opcion_juego.selected, 0)][1]


func _on_filtro_seleccionado(_indice: int) -> void:
	_ocultar_error()
	_cargar_partidas()


## Cambia quién puede ver tu historial. Si el backend no lo acepta, el
## interruptor vuelve a como estaba y se dice por qué.
func _on_interruptor_publico_toggled(publico: bool) -> void:
	_ocultar_error()
	_bloquear(true)
	var resultado: Dictionary = await api.cambiar_privacidad(publico)
	_bloquear(false)
	if resultado.ok:
		var confirmado: Variant = resultado.datos.get("historial_publico") if resultado.datos is Dictionary else null
		interruptor_publico.set_pressed_no_signal(confirmado if confirmado is bool else publico)
	else:
		interruptor_publico.set_pressed_no_signal(not publico)
		_tratar_error(resultado)


func _on_boton_actualizar_pressed() -> void:
	refrescar()


func _on_boton_volver_pressed() -> void:
	ir_a.call(ESCENA_LOBBY)


func _tratar_error(resultado: Dictionary) -> void:
	if resultado.codigo == 401:
		_cerrar_sesion_caducada()
	else:
		_mostrar_error(_mensaje_de(resultado))


func _cerrar_sesion_caducada() -> void:
	api.cerrar_sesion()
	ir_a.call(ESCENA_LOGIN)


func _mensaje_de(resultado: Dictionary) -> String:
	if resultado.codigo == 403:
		return AVISO_PRIVADO
	if resultado.codigo == 0:
		return AVISO_SIN_CONEXION
	if resultado.datos is Dictionary and resultado.datos.get("error") is String:
		return resultado.datos["error"]
	return "No se pudo cargar el historial"


func _mostrar_error(mensaje: String) -> void:
	etiqueta_error.text = mensaje
	etiqueta_error.visible = true


func _ocultar_error() -> void:
	etiqueta_error.visible = false


func _bloquear(bloqueado: bool) -> void:
	opcion_juego.disabled = bloqueado
	interruptor_publico.disabled = bloqueado or not _privacidad_conocida
	boton_actualizar.disabled = bloqueado
