extends Control
## Mesa común de los tres juegos (Guiñote, Tute y Mus, a 2 y a 4 jugadores): la
## misma mesa, las mismas cartas, letreros y botones para todos (PBI-12).
##
## Es la mesa del prototipo unificado, con su mismo aspecto, adaptada al
## cliente: no habla con la red. La pantalla que la contiene (partida_mesa.gd)
## le pasa lo que manda el servidor ([method configurar_mesa],
## [method actualizar_vista], [method anunciar]...) y escucha
## [signal jugada_solicitada] para enviar lo que el jugador quiere hacer. Como
## en el resto del cliente, la mesa nunca decide si una jugada es válida: solo
## deja hacer lo que viene en `jugadas_validas`.
##
## Los jugadores se identifican por su asiento (0 … n-1), que es el
## `jugador_id` de los motores y el `posicion` del protocolo.

const ESCENA_CARTA := preload("res://client/ui/mesa/carta_mesa.tscn")

## Fondo de la mesa. Para cambiarlo basta con sustituir esta imagen; si no
## existe, se pinta un tapete verde provisional.
const RUTA_FONDO := "res://client/assets/mesa/tapete.png"
const RUTA_CARTAS := "res://client/assets/cartas/%s.png"

## Escala de todas las cartas de la mesa: mano y baza miden lo mismo.
const ESCALA_MESA := 0.5
const ESCALA_DORSO := 0.28
const ESCALA_PINTA := 0.4
const SEPARACION_DORSOS := 20.0
## Hacia dónde se desplaza cada carta de la baza desde el centro, según quién
## la echa: 0 = tú, 1 = rival de la derecha, 2 = compañero, 3 = rival de la izquierda.
const DESPLAZAMIENTO_BAZA := {0: Vector2(0, 82), 1: Vector2(112, 0), 2: Vector2(0, -82), 3: Vector2(-112, 0)}
## Un color por pareja: tu compañero lleva el tuyo y los rivales el otro.
const COLOR_PAREJA := [Color(0.25, 0.6, 1.0), Color(1.0, 0.45, 0.3)]
const COLOR_TURNO := Color(1.0, 0.85, 0.3)
## Letrero de "esa carta no vale" y demás rechazos del servidor.
const COLOR_ERROR := Color(1.0, 0.55, 0.5)
const COLOR_NO_JUGABLE := Color(0.45, 0.45, 0.45)
## Abre y cierra el panel de depuración (solo en builds de depuración).
const TECLA_DEPURACION := KEY_F3
const LINEAS_DEPURACION := 18
## Pila del mazo (juegos con robo): a la izquierda de la baza.
const DESPLAZAMIENTO_PILA := Vector2(-300, 0)
const MAX_DORSOS_PILA := 10
## Lo que se tarda en borrar un anuncio ("¡Las 40!", "Mus"...).
const DURACION_ANUNCIO := 2.5

const NOMBRE_PAREJA := ["pareja A", "pareja B"]
const NOMBRE_VALOR := {
	1: "As", 2: "Dos", 3: "Tres", 4: "Cuatro", 5: "Cinco", 6: "Seis", 7: "Siete",
	10: "Sota", 11: "Caballo", 12: "Rey",
}
## Tute de 2: con una pinta alta se cambia por el 7; con una baja, por el 2.
const VALORES_ALTOS_TUTE_DOS := [1, 3, 12, 11, 10]

## El jugador quiere hacer algo: echar una carta, cantar, envidar...
## [param jugada] tiene el formato de `jugadas_validas`: { tipo, ...datos }.
signal jugada_solicitada(jugada: Dictionary)
## Se emite al enseñar el resultado final de la partida.
signal partida_finalizada(texto: String)

@onready var nodo_mano: Control = $mano
@onready var area_mano: Area2D = $mano/area_mano
@onready var colision_mano: CollisionShape2D = $mano/area_mano/CollisionShape2D
@onready var nodo_mazo: Control = $mazo
@onready var colision_mazo: CollisionShape2D = $mazo/area_mazo/CollisionShape2D

var cartas_en_mano: Array = []
var cartas_sobre_area_mano: Array = []  # Qué cartas están sobrevolando el área de la mano
var cartas_sobre_area_mesa: Array = []  # Qué cartas están sobrevolando el centro
var carta_en_mesa = null  # Tu carta en la baza
var cartas_en_mazo: Array = []  # La pinta cuando no hay mazo (Tute por parejas)
var cartas_otros_en_mesa: Array = []  # Cartas de los demás en la baza

## Cuántos se sientan y en qué asiento estás tú; 0 y -1 hasta configurar_mesa().
var num_jugadores := 0
var mi_asiento := -1
var nombres: Array = []  # nombre de cada asiento ("" si no se sabe)
var etiquetas_jugador: Dictionary = {}  # asiento -> etiqueta "J#"
var dorsos: Dictionary = {}  # asiento -> Node2D con los dorsos de su mano
var restantes: Dictionary = {}  # asiento -> cartas que le quedan

## Si es true, este cliente juega solo (para probar la partida sin pantalla).
var autojugar: bool = false
## Con autojugar, si canta y cambia la pinta cuando puede (true) o nunca.
var autocantar: bool = true
## Con autojugar, lo que tarda en echar carta y en pulsar un botón.
var espera_autojugar_carta := 0.15
var espera_autojugar_accion := 0.05

## Juego de la mesa: "guinote", "tute" (por parejas), "tute_dos" o "mus".
var _juego := ""
## Si el juego tiene mazo para robar: entonces se pinta la pila en vez de la pinta en la esquina.
var _con_mazo := false
var _pila: Node2D
var _texto_pila: Label
var _pila_actual: Array = []  # [cartas, pinta] que se están dibujando
var _palo_triunfo := ""
## Última vista recibida del servidor.
var _vista: Dictionary = {}
var _caja_acciones: VBoxContainer
## Lo que solo se hace en el Mus (mesa_mus.gd); null en el resto de juegos.
var _mus: MesaMus
## Arriba a la derecha: piedras del Mus, o las idas durante la vuelta.
var _texto_marcador: Label
var _aviso_error: Label

var _textura_dorso: Texture2D
var _tween_turno: Tween
var _marcador := ""
var _info_partida := ""
var _registro := PackedStringArray()
var _panel_depuracion: PanelContainer
var _texto_depuracion: Label
var _panel_resultado: PanelContainer


func _ready() -> void:
	_crear_fondo()
	get_viewport().size_changed.connect(_recolocar_mesa)


# ==========================================
# LA MANO
# ==========================================

func generar_mano_desde_array(cartas_ids: Array) -> void:
	for id in cartas_ids:
		var nueva_carta = ESCENA_CARTA.instantiate()
		nueva_carta.escala_base = ESCALA_MESA
		nodo_mano.add_child(nueva_carta)
		nueva_carta.inicializar(id)
		nueva_carta.carta_soltada.connect(_on_carta_soltada)
		cartas_en_mano.append(nueva_carta)
	reorganizar_mano()


func reorganizar_mano() -> void:
	var total := cartas_en_mano.size()
	if total == 0:
		return

	# Con más de 6 cartas (el Tute reparte 10) se abre el abanico.
	var ancho_total: float = 400.0 + max(0, total - 6) * 45.0
	var altura_curva := 24.0
	var rotacion_max := 15.0
	# La mano se coloca según el tamaño real de la ventana, para que las
	# cartas se vean enteras.
	var centro_abanico: Vector2 = global_position + _centro_mano() - nodo_mano.global_position

	for i in range(total):
		var carta = cartas_en_mano[i]
		var t := 0.5
		if total > 1:
			t = float(i) / float(total - 1)

		var pos_x: float = centro_abanico.x + lerp(-ancho_total / 2.0, ancho_total / 2.0, t)
		var t_offset := (t - 0.5) * 2.0
		var pos_y: float = centro_abanico.y + (t_offset * t_offset) * altura_curva
		var rot: float = lerp(-rotacion_max, rotacion_max, t)
		# Mus: las cartas elegidas para descartarse se quedan levantadas.
		if _mus and _mus.seleccion.has(carta):
			pos_y -= 40.0

		carta.z_index_base = i
		carta.pos_base = Vector2(pos_x, pos_y)
		carta.rot_base = rot

		# La carta solo se mueve si no se está arrastrando ni está en hover.
		if carta.current_state == CartaMesa.State.IDLE:
			carta.z_index = i
			if carta.tween_abanico:
				carta.tween_abanico.kill()
			carta.tween_abanico = FuncionesGlobales.lanzar_tweens_simultaneos([
				{"prop": "position", "valor": carta.pos_base, "dur": 0.4, "trans": Tween.TRANS_CUBIC, "ease": Tween.EASE_OUT},
				{"prop": "rotation_degrees", "valor": carta.rot_base, "dur": 0.4, "trans": Tween.TRANS_CUBIC, "ease": Tween.EASE_OUT}
			], carta)


## Señal de la carta cuando se suelta el clic izquierdo.
func _on_carta_soltada(carta_soltada) -> void:
	# En el Mus no se echan cartas: durante tu descarte, pulsar una la elige.
	if _mus:
		if _mus.puedo_descartar():
			_mus.alternar_descarte(carta_soltada)
		else:
			reorganizar_mano()
		return

	# CASO 1: se ha soltado en la MESA (tiene prioridad).
	if cartas_sobre_area_mesa.has(carta_soltada):
		if carta_en_mesa == null:
			_jugar_carta_en_mesa(carta_soltada)
		else:
			# Ya hay una carta tuya en la mesa: vuelve a la mano.
			reorganizar_mano()

	# CASO 2: se ha soltado dentro de la MANO (reordenar).
	elif cartas_sobre_area_mano.has(carta_soltada):
		if not cartas_en_mano.has(carta_soltada):
			cartas_en_mano.append(carta_soltada)
		var nuevo_indice := 0
		for otra_carta in cartas_en_mano:
			if otra_carta != carta_soltada:
				if carta_soltada.global_position.x > otra_carta.global_position.x:
					nuevo_indice += 1
		cartas_en_mano.erase(carta_soltada)
		cartas_en_mano.insert(nuevo_indice, carta_soltada)
		reorganizar_mano()

	# CASO 3: se ha soltado fuera de las zonas válidas.
	else:
		reorganizar_mano()


## Lleva una carta de tu mano al centro de la mesa y se la propone al servidor.
## La usa el arrastre con el ratón y también el modo autojugar.
func _jugar_carta_en_mesa(carta) -> void:
	if cartas_en_mano.has(carta):
		cartas_en_mano.erase(carta)
	carta_en_mesa = carta
	carta.bloqueada = true
	# Tu carta va en la baza del centro, desplazada hacia ti.
	var centro_mesa_global: Vector2 = global_position + _pos_carta_baza(0)
	carta.pos_base = centro_mesa_global - carta.get_parent().global_position
	carta.rot_base = 0.0
	carta.z_index_base = 0
	carta.cambiar_estado(CartaMesa.State.IDLE)
	# La mano tapa el hueco que ha dejado.
	reorganizar_mano()
	jugada_solicitada.emit({"tipo": MensajesRed.JUGAR_CARTA, "carta_id": carta.id})


func _on_area_mano_area_entered(area: Area2D) -> void:
	var carta = area.get_parent()
	if carta is CartaMesa and not cartas_sobre_area_mano.has(carta):
		cartas_sobre_area_mano.append(carta)


func _on_area_mano_area_exited(area: Area2D) -> void:
	var carta = area.get_parent()
	if carta is CartaMesa and cartas_sobre_area_mano.has(carta):
		cartas_sobre_area_mano.erase(carta)


func _on_area_mesa_area_entered(area: Area2D) -> void:
	var carta = area.get_parent()
	if carta is CartaMesa and not cartas_sobre_area_mesa.has(carta):
		cartas_sobre_area_mesa.append(carta)


func _on_area_mesa_area_exited(area: Area2D) -> void:
	var carta = area.get_parent()
	if carta is CartaMesa and cartas_sobre_area_mesa.has(carta):
		cartas_sobre_area_mesa.erase(carta)


## El servidor ha rechazado la carta que tenías en la mesa: vuelve a tu mano.
## Devuelve true si había una carta pendiente de respuesta.
func devolver_carta_rechazada() -> bool:
	if not _carta_en_vuelo():
		return false
	carta_en_mesa.bloqueada = false
	# Con append() la carta vuelve al último hueco de la mano (a la derecha).
	cartas_en_mano.append(carta_en_mesa)
	carta_en_mesa = null
	reorganizar_mano()
	return true


## El servidor ha aceptado la carta que echaste: ya no está "en vuelo".
func confirmar_carta_propia(id_carta: String) -> void:
	if carta_en_mesa and carta_en_mesa.id == id_carta:
		carta_en_mesa.set_meta("aceptada", true)


# ==========================================
# EL MAZO
# ==========================================

func sincronizar_mazo(cantidad_cartas: int, id_triunfo: String = "") -> void:
	# Solo se redibuja si ha cambiado algo (llega con cada vista).
	if _pila_actual == [cantidad_cartas, id_triunfo]:
		return
	# Si el juego tiene mazo, la pila va junto a la baza.
	if _con_mazo:
		_dibujar_pila(cantidad_cartas, id_triunfo)
		return
	_pila_actual = [cantidad_cartas, id_triunfo]

	for carta in cartas_en_mazo:
		carta.queue_free()
	cartas_en_mazo.clear()
	if cantidad_cartas <= 0:
		return

	var centro_mazo_local: Vector2 = colision_mazo.global_position - nodo_mazo.global_position
	for i in range(cantidad_cartas):
		var nueva_carta = ESCENA_CARTA.instantiate()
		nodo_mazo.add_child(nueva_carta)
		# La primera carta (el fondo) es la pinta, si la hay.
		if i == 0 and id_triunfo != "":
			nueva_carta.inicializar(id_triunfo)
			nueva_carta.rot_base = 90.0
			nueva_carta.pos_base = centro_mazo_local + Vector2(50, 0)
		else:
			nueva_carta.inicializar(CartaMesa.ID_DORSO)
			nueva_carta.rot_base = 0.0
			nueva_carta.pos_base = centro_mazo_local + Vector2(-1 * i, -1 * i)
		# Se mata el tween que se lanza solo al entrar en el árbol y se colocan
		# de forma instantánea.
		if nueva_carta.tween_actual:
			nueva_carta.tween_actual.kill()
		nueva_carta.position = nueva_carta.pos_base
		nueva_carta.rotation_degrees = nueva_carta.rot_base
		nueva_carta.scale = Vector2(0.72, 0.72)
		nueva_carta.z_index_base = i
		nueva_carta.z_index = i
		nueva_carta.bloqueada = true
		nueva_carta.current_state = CartaMesa.State.IDLE
		cartas_en_mazo.append(nueva_carta)

	# Sin mazo (Tute por parejas), la única carta es la pinta, en su esquina.
	_colocar_pinta()


# ==========================================
# LO QUE MANDA EL SERVIDOR (a través de partida_mesa.gd)
# En pantalla solo hay cartas, dorsos, etiquetas "J#" y letreros cortos; todo el
# texto de seguimiento va al panel de depuración (F3).
# ==========================================

## Quién se sienta dónde, cuál es la pinta y quién reparte (en el Mus, quién es
## mano). [param p_juego] es "guinote", "tute", "tute_dos" o "mus".
func configurar_mesa(p_juego: String, p_nombres: Array, p_mi_asiento: int, id_pinta: String, dador: int) -> void:
	_juego = p_juego
	# El Tute por parejas reparte las 40 cartas: no hay mazo del que robar.
	_con_mazo = _juego != "tute"
	_mus = MesaMus.new(self) if _juego == "mus" else null
	_palo_triunfo = _palo_de(id_pinta)
	nombres = p_nombres
	num_jugadores = p_nombres.size()
	mi_asiento = p_mi_asiento
	restantes.clear()
	_textura_dorso = load(RUTA_CARTAS % CartaMesa.ID_DORSO)
	for asiento in num_jugadores:
		_crear_etiqueta_jugador(asiento)
	var yo := _nombre_o_abreviatura(mi_asiento)
	if num_jugadores == 4:
		yo += " (%s)" % NOMBRE_PAREJA[mi_asiento % 2]
	if _juego == "mus":
		_info_partida = "Tú: %s\nMus · empieza de mano %s" % [yo, _nombre_o_abreviatura(dador)]
	elif _con_mazo:
		_info_partida = "Tú: %s\nTriunfo: %s · pinta: %s, bajo el mazo · reparte %s" % [
			yo, _palo_de(id_pinta), _nombre_carta(id_pinta), _nombre_o_abreviatura(dador)]
	else:
		_info_partida = "Tú: %s\nTriunfo: %s · pinta: %s, la tiene %s" % [
			yo, _palo_de(id_pinta), _nombre_carta(id_pinta), _nombre_o_abreviatura(dador)]
	_depurar("Mesa lista. " + _info_partida.replace("\n", " · "))
	_recolocar_mesa()


## Oscurece las cartas que no puedes echar. Lista vacía = no es tu turno.
func marcar_cartas_jugables(ids: Array) -> void:
	for carta in cartas_en_mano:
		carta.self_modulate = Color.WHITE if ids.is_empty() or ids.has(carta.id) else COLOR_NO_JUGABLE
	if autojugar and not ids.is_empty():
		_jugar_solo(ids)


## Lo que va pasando en la partida: solo va al panel de depuración.
func mostrar_aviso(texto: String) -> void:
	_depurar(texto)


## El marcador no se ve durante la mano: se guarda y sale en el resultado final.
func actualizar_marcador(texto: String) -> void:
	_marcador = texto
	_refrescar_depuracion()


func mostrar_resultado(texto: String) -> void:
	_mostrar_acciones([])
	for carta in cartas_en_mano:
		carta.bloqueada = true
		carta.self_modulate = Color.WHITE
	marcar_turno(-1)
	_depurar(texto.replace("\n", " · "))
	if _panel_resultado == null:
		_panel_resultado = PanelContainer.new()
		_panel_resultado.name = "PanelResultado"
		_panel_resultado.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.82)
		estilo.border_color = COLOR_TURNO
		estilo.set_border_width_all(3)
		estilo.set_corner_radius_all(14)
		estilo.set_content_margin_all(24)
		_panel_resultado.add_theme_stylebox_override("panel", estilo)
		var etiqueta := _crear_texto(20)
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_resultado.add_child(etiqueta)
		_panel_resultado.z_index = 150
		add_child(_panel_resultado)
	var completo := texto
	if _marcador != "":
		completo += "\n\n" + _marcador
	(_panel_resultado.get_child(0) as Label).text = completo
	_panel_resultado.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel_resultado.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_resultado.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel_resultado.show()
	partida_finalizada.emit(texto)


## Tras cada jugada el servidor manda a cada uno lo que ve (su "vista") y lo que
## puede hacer; la mesa se pone igual que la vista, sin llevar cuentas propias.
func actualizar_vista(vista: Dictionary, jugadas: Array) -> void:
	_vista = vista
	_palo_triunfo = vista.get("palo_triunfo", _palo_triunfo)
	_sincronizar_mano(vista.get("mi_mano", []))
	_sincronizar_baza(vista.get("baza_actual", []))
	var cartas_por_jugador: Array = vista.get("cartas_por_jugador", [])
	for asiento in num_jugadores:
		if asiento != mi_asiento and asiento < cartas_por_jugador.size():
			restantes[asiento] = cartas_por_jugador[asiento]
			_dibujar_dorsos(asiento)
	var pinta: Variant = vista.get("pinta")
	sincronizar_mazo(vista.get("cartas_en_mazo", 0), pinta if pinta is String else "")
	var quien: int = vista.get("esperando_cambio_siete", -1)
	if quien == -1:
		quien = vista.get("turno", -1)
	marcar_turno(quien)
	var ids: Array = []
	var acciones: Array = []
	for jugada: Dictionary in jugadas:
		if jugada["tipo"] == MensajesRed.JUGAR_CARTA:
			ids.append(jugada["carta_id"])
		else:
			acciones.append(jugada)
	marcar_cartas_jugables(ids)
	if _mus:
		_mus.actualizar(vista, acciones)
	else:
		_mostrar_acciones(acciones)
		_poner_marcador(_marcador_de_bazas(vista))


## Un jugador dice algo en voz alta ("¡Las 40!", "Capote"...): sale junto a su
## etiqueta. Con asiento = -1 es un aviso de la mesa y sale en el centro.
func anunciar(asiento: int, texto: String) -> void:
	_depurar("%s: %s" % [_nombre_o_abreviatura(asiento) if _es_asiento(asiento) else "Mesa", texto])
	var etiqueta := _mostrar_letrero(texto, COLOR_TURNO)
	var ancho := etiqueta.get_minimum_size().x
	var pos := _centro_baza() - Vector2(ancho / 2.0, 130.0)
	if _es_asiento(asiento):
		pos = _pos_etiqueta(_posicion_relativa(asiento)) + Vector2(0, 40)
		pos.x = minf(pos.x, _tam().x - ancho - 10.0)
	etiqueta.position = pos


## Solo para ti, cuando el servidor rechaza lo que has intentado (p. ej. por
## qué no vale esa carta): sale debajo de tu mano.
func avisar_error(texto: String) -> void:
	_depurar(texto)
	if is_instance_valid(_aviso_error):
		_aviso_error.queue_free()
	_aviso_error = _mostrar_letrero(texto, COLOR_ERROR, 20)
	_aviso_error.position = Vector2((_tam().x - _aviso_error.get_minimum_size().x) / 2.0, _tam().y - 36.0)


## Un texto que se borra solo al cabo de unos segundos.
func _mostrar_letrero(texto: String, color: Color, tam_fuente := 24) -> Label:
	var etiqueta := _crear_texto(tam_fuente)
	etiqueta.text = texto
	etiqueta.label_settings.font_color = color
	etiqueta.z_index = 120
	add_child(etiqueta)
	var tween := etiqueta.create_tween()
	tween.tween_interval(DURACION_ANUNCIO)
	tween.tween_property(etiqueta, "modulate:a", 0.0, 0.4)
	tween.tween_callback(etiqueta.queue_free)
	return etiqueta


## Deja la mano como dice el servidor: quita las que ya no tienes (p. ej. el 7
## que cambias por la pinta) y añade las robadas, sin desordenar las demás.
func _sincronizar_mano(ids: Array) -> void:
	var quitadas := false
	for carta in cartas_en_mano.duplicate():
		if not ids.has(carta.id):
			cartas_en_mano.erase(carta)
			carta.queue_free()
			quitadas = true
	var en_mano: Array = cartas_en_mano.map(func(c): return c.id)
	# Tu carta en la mesa sigue en tu mano para el servidor hasta que la acepta.
	if _carta_en_vuelo():
		en_mano.append(carta_en_mesa.id)
	var nuevas := ids.filter(func(id): return not en_mano.has(id))
	if not nuevas.is_empty():
		generar_mano_desde_array(nuevas)
	elif quitadas:
		reorganizar_mano()


## Tu carta está en la mesa pero el servidor aún no ha contestado.
func _carta_en_vuelo() -> bool:
	return carta_en_mesa != null and not carta_en_mesa.get_meta("aceptada", false)


## Deja en el centro las cartas de la baza en curso y recoge las demás.
func _sincronizar_baza(baza: Array) -> void:
	var mia := ""
	for jugada: Dictionary in baza:
		if jugada["jugador_id"] == mi_asiento:
			mia = jugada["carta_id"]
	# Tu carta se recoge cuando ya la aceptó el servidor y no está en la baza en
	# curso. Mirar solo si sigue en tu mano no basta: en la vuelta se reparte otra
	# vez y te puede volver a tocar la misma carta.
	if carta_en_mesa and not _carta_en_vuelo() and carta_en_mesa.id != mia:
		carta_en_mesa.queue_free()
		carta_en_mesa = null
	var faltan := {}  # id de carta -> asiento de quien la echó
	for jugada: Dictionary in baza:
		var asiento: int = jugada["jugador_id"]
		if asiento != mi_asiento or carta_en_mesa == null:
			faltan[jugada["carta_id"]] = asiento
	for carta in cartas_otros_en_mesa.duplicate():
		if faltan.has(carta.get_meta("id_carta")):
			faltan.erase(carta.get_meta("id_carta"))
		else:
			cartas_otros_en_mesa.erase(carta)
			carta.queue_free()
	for id in faltan:
		_colocar_carta_de_otro(faltan[id], id)


## Botones con lo que puedes hacer además de echar carta (cantar, cambiar la pinta...).
## [param automaticas]: entre qué elige autojugar, si no son los mismos botones
## (en el Mus hay más envites posibles que botones).
func _mostrar_acciones(acciones: Array, automaticas: Variant = null) -> void:
	if automaticas == null:
		automaticas = acciones
	if _caja_acciones == null:
		_caja_acciones = VBoxContainer.new()
		_caja_acciones.name = "Acciones"
		_caja_acciones.z_index = 60
		_caja_acciones.add_theme_constant_override("separation", 8)
		add_child(_caja_acciones)
	for hijo in _caja_acciones.get_children():
		_caja_acciones.remove_child(hijo)
		hijo.queue_free()
	for jugada: Dictionary in acciones:
		var boton := Button.new()
		boton.text = _texto_jugada(jugada)
		boton.custom_minimum_size = Vector2(240, 40)
		# El botón de descartarse del Mus lo prepara la parte del Mus.
		if not (_mus and _mus.preparar_boton(boton, jugada)):
			boton.pressed.connect(_on_accion_pulsada.bind(jugada))
		_caja_acciones.add_child(boton)
	_caja_acciones.reset_size()
	_colocar_acciones()
	if autojugar and not automaticas.is_empty():
		_accion_automatica(automaticas)


func _colocar_acciones() -> void:
	if _caja_acciones:
		_caja_acciones.position = Vector2(_tam().x / 2.0 + 330.0, _tam().y - 150.0 - _caja_acciones.size.y / 2.0)


func _on_accion_pulsada(jugada: Dictionary) -> void:
	_mostrar_acciones([])
	jugada_solicitada.emit(jugada)


func _texto_jugada(jugada: Dictionary) -> String:
	if _mus:
		var del_mus := _mus.texto_jugada(jugada)
		if del_mus != "":
			return del_mus
	match jugada["tipo"]:
		MensajesRed.CANTAR:
			if jugada["palo"] == _palo_triunfo:
				return "Cantar las 40"
			return "Cantar las 20 en %s" % jugada["palo"]
		MensajesRed.CANTAR_TUTE:
			return "¡Cantar Tute de %s!" % jugada["figura"]
		MensajesRed.CAMBIAR_SIETE:
			var pinta: Variant = _vista.get("pinta")
			var con_el_dos: bool = _juego == "tute_dos" and pinta is String \
				and valor_de(pinta) not in VALORES_ALTOS_TUTE_DOS
			return "Cambiar el %s por la pinta" % ("2" if con_el_dos else "7")
		MensajesRed.NO_CAMBIAR_SIETE:
			return "No cambiar la pinta"
		MensajesRed.CAPOTE:
			return "Anunciar capote"
	return jugada["tipo"]


## Con autojugar: canta y cambia la pinta si puede (o nunca, sin autocantar).
func _accion_automatica(acciones: Array) -> void:
	var vista_al_pedir := _vista
	await get_tree().create_timer(espera_autojugar_accion).timeout
	# Mientras esperaba ha llegado otro estado, o ya ha echado carta y el
	# servidor aún no ha contestado: esas acciones ya no valen.
	if not is_same(vista_al_pedir, _vista) or _carta_en_vuelo():
		return
	if _mus:
		_on_accion_pulsada(_mus.jugada_automatica(acciones))
		return
	var elegida := {}
	for jugada: Dictionary in acciones:
		var tipo: String = jugada["tipo"]
		var quiere := tipo in [MensajesRed.CANTAR, MensajesRed.CANTAR_TUTE, MensajesRed.CAMBIAR_SIETE] if autocantar \
			else tipo == MensajesRed.NO_CAMBIAR_SIETE
		if quiere and elegida.is_empty():
			elegida = jugada
	if not elegida.is_empty():
		_on_accion_pulsada(elegida)


# --- Marcador y equipos ---

## Arriba a la derecha: las piedras en el Mus, y en la vuelta del Guiñote y del
## Tute de 2, cómo acabaron las idas (el resto del tanteo se lleva de memoria).
## Texto vacío = no se enseña nada.
func _poner_marcador(texto: String) -> void:
	if _texto_marcador == null:
		_texto_marcador = _crear_texto(20)
		_texto_marcador.name = "Marcador"
		_texto_marcador.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_texto_marcador)
	_texto_marcador.text = texto
	_texto_marcador.visible = texto != ""
	_colocar_textos()


func _marcador_de_bazas(vista: Dictionary) -> String:
	var idas: Array = vista.get("tanteo_idas", [])
	if vista.get("mano") != "vuelta" or idas.size() != 2:
		return ""
	return "Vuelta · idas: %s %d · %s %d" % [_nombre_equipo(0), idas[0], _nombre_equipo(1), idas[1]]


func _colocar_textos() -> void:
	if _mus:
		_mus.colocar()
	if _texto_marcador:
		_texto_marcador.reset_size()
		# Por debajo de la fila de etiquetas de arriba, que con nombres largos llega hasta aquí.
		_texto_marcador.position = Vector2(_tam().x - _texto_marcador.size.x - 14.0, 64.0)


## "J1" en la mesa de 2; "Pareja A" en la de 4.
func _nombre_equipo(equipo: int) -> String:
	if num_jugadores == 2:
		return _abreviatura(equipo)
	return "Pareja %s" % "AB"[equipo]


## Mus: al acabar la mano se enseñan las cartas de todos y lo que cobra cada pareja.
func mostrar_fin_de_mano(ultima: Dictionary) -> void:
	if _mus:
		_mus.mostrar_fin_de_mano(ultima)


func _pos_pila() -> Vector2:
	return _centro_baza() + DESPLAZAMIENTO_PILA


## La pila del mazo: la pinta atravesada debajo y encima los dorsos que quedan.
## Cuando se acaba, queda escrito cuál es el triunfo.
func _dibujar_pila(cantidad: int, pinta: String) -> void:
	_pila_actual = [cantidad, pinta]
	if _pila == null:
		_pila = Node2D.new()
		_pila.name = "Pila"
		add_child(_pila)
		_texto_pila = _crear_texto(18)
		add_child(_texto_pila)
	for hijo in _pila.get_children():
		hijo.queue_free()
	_pila.position = _pos_pila()
	if pinta != "":
		var carta_pinta := Sprite2D.new()
		carta_pinta.texture = load(RUTA_CARTAS % pinta)
		carta_pinta.scale = Vector2.ONE * ESCALA_MESA
		carta_pinta.rotation_degrees = 90.0
		carta_pinta.position = Vector2(62, 0)
		_pila.add_child(carta_pinta)
	var boca_abajo := mini(cantidad - (1 if pinta != "" else 0), MAX_DORSOS_PILA)
	for i in boca_abajo:
		var dorso := Sprite2D.new()
		dorso.texture = _textura_dorso
		dorso.scale = Vector2.ONE * ESCALA_MESA
		dorso.position = Vector2(-1.5, -1.5) * i
		_pila.add_child(dorso)
	if cantidad > 0:
		_texto_pila.text = "%d en el mazo" % cantidad
	else:
		_texto_pila.text = "" if _juego == "mus" else "Triunfo: %s" % _palo_triunfo
	_texto_pila.position = _pos_pila() + Vector2(-50, 90)


# --- Dónde va cada cosa, calculado sobre el tamaño real de la ventana ---

func _tam() -> Vector2:
	return get_viewport_rect().size


func _centro_baza() -> Vector2:
	return Vector2(_tam().x / 2.0, _tam().y * 0.40)


func _pos_carta_baza(relativa: int) -> Vector2:
	return _centro_baza() + DESPLAZAMIENTO_BAZA[relativa]


func _centro_mano() -> Vector2:
	return Vector2(_tam().x / 2.0, _tam().y - 140.0)


func _pos_dorsos(relativa: int) -> Vector2:
	match relativa:
		1: return Vector2(_tam().x - 46.0, _centro_baza().y)
		2: return Vector2(_tam().x / 2.0, 38.0)
		3: return Vector2(46.0, _centro_baza().y)
	return Vector2.ZERO


func _pos_etiqueta(relativa: int) -> Vector2:
	match relativa:
		0: return Vector2(14.0, 12.0)
		1: return Vector2(_tam().x - 74.0, _centro_baza().y + 125.0)
		2: return Vector2(_tam().x / 2.0 + 140.0, 22.0)
		3: return Vector2(14.0, _centro_baza().y + 125.0)
	return Vector2.ZERO


func _pos_pinta() -> Vector2:
	return Vector2(_tam().x - 70.0, 80.0)


## Vuelve a colocar todo; se llama al empezar y cada vez que cambia el tamaño de la ventana.
func _recolocar_mesa() -> void:
	# El aviso de cambio de tamaño puede llegar mientras se cierra la pantalla.
	if num_jugadores == 0 or not is_inside_tree():
		return
	for asiento in etiquetas_jugador:
		var etiqueta: PanelContainer = etiquetas_jugador[asiento]
		var pos := _pos_etiqueta(_posicion_relativa(asiento))
		# Con nombre, la etiqueta es más ancha: que no se salga por la derecha.
		pos.x = minf(pos.x, _tam().x - etiqueta.get_combined_minimum_size().x - 10.0)
		etiqueta.position = pos
	for asiento in dorsos:
		_dibujar_dorsos(asiento)
	_colocar_pinta()
	for carta in cartas_otros_en_mesa:
		carta.pos_base = _pos_carta_baza(carta.get_meta("relativa"))
		carta.position = carta.pos_base
	if carta_en_mesa:
		carta_en_mesa.pos_base = global_position + _pos_carta_baza(0) - carta_en_mesa.get_parent().global_position
		carta_en_mesa.position = carta_en_mesa.pos_base
	if _con_mazo and not _pila_actual.is_empty():
		_dibujar_pila(_pila_actual[0], _pila_actual[1])
	_colocar_acciones()
	_colocar_textos()
	reorganizar_mano()


# --- Piezas de la mesa ---

func _crear_fondo() -> void:
	var fondo := TextureRect.new()
	fondo.name = "Fondo"
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fondo.texture = load(RUTA_FONDO) if ResourceLoader.exists(RUTA_FONDO) else _tapete_provisional()
	add_child(fondo)
	move_child(fondo, 0)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Tapete verde con viñeta, para cuando no hay imagen de fondo.
func _tapete_provisional() -> Texture2D:
	var degradado := Gradient.new()
	degradado.set_color(0, Color(0.16, 0.48, 0.26))
	degradado.set_color(1, Color(0.03, 0.16, 0.08))
	var textura := GradientTexture2D.new()
	textura.gradient = degradado
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(1.1, 1.1)
	textura.width = 512
	textura.height = 288
	return textura


func _crear_etiqueta_jugador(asiento: int) -> void:
	if etiquetas_jugador.has(asiento):
		etiquetas_jugador[asiento].queue_free()
	var color: Color = COLOR_PAREJA[asiento % 2]
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color.darkened(0.65), 0.85)
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var activo := normal.duplicate() as StyleBoxFlat
	activo.bg_color = Color(color.darkened(0.25), 0.95)
	activo.border_color = COLOR_TURNO
	activo.set_border_width_all(4)
	activo.shadow_color = Color(COLOR_TURNO, 0.7)
	activo.shadow_size = 6
	var panel := PanelContainer.new()
	panel.name = "Etiqueta%d" % asiento
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", normal)
	panel.set_meta("normal", normal)
	panel.set_meta("activo", activo)
	var texto := _crear_texto(22)
	texto.text = _etiqueta_de(asiento)
	panel.add_child(texto)
	add_child(panel)
	etiquetas_jugador[asiento] = panel


## Resalta la etiqueta de quien juega (borde dorado que late). -1 = nadie.
func marcar_turno(asiento_activo: int) -> void:
	if _tween_turno:
		_tween_turno.kill()
	for asiento in etiquetas_jugador:
		var panel: PanelContainer = etiquetas_jugador[asiento]
		panel.add_theme_stylebox_override("panel", panel.get_meta("activo" if asiento == asiento_activo else "normal"))
	if etiquetas_jugador.has(asiento_activo):
		var activo: StyleBoxFlat = etiquetas_jugador[asiento_activo].get_meta("activo")
		_tween_turno = create_tween().set_loops()
		_tween_turno.tween_property(activo, "shadow_size", 16, 0.5)
		_tween_turno.tween_property(activo, "shadow_size", 4, 0.5)


## Pinta boca abajo las cartas que le quedan a otro jugador, en su lado de la mesa.
func _dibujar_dorsos(asiento: int) -> void:
	var relativa := _posicion_relativa(asiento)
	var grupo: Node2D = dorsos.get(asiento)
	if grupo == null:
		grupo = Node2D.new()
		grupo.name = "Dorsos%d" % asiento
		add_child(grupo)
		dorsos[asiento] = grupo
	for hijo in grupo.get_children():
		grupo.remove_child(hijo)
		hijo.queue_free()
	grupo.position = _pos_dorsos(relativa)
	grupo.rotation_degrees = 180.0 if relativa == 2 else 90.0
	var cuantas: int = restantes.get(asiento, 0)
	for i in cuantas:
		var dorso := Sprite2D.new()
		dorso.texture = _textura_dorso
		dorso.scale = Vector2.ONE * ESCALA_DORSO
		dorso.position = Vector2((i - (cuantas - 1) / 2.0) * SEPARACION_DORSOS, 0)
		grupo.add_child(dorso)


func _colocar_pinta() -> void:
	if cartas_en_mazo.is_empty():
		return
	var pinta = cartas_en_mazo[0]
	pinta.rot_base = 0.0
	pinta.pos_base = global_position + _pos_pinta() - nodo_mazo.global_position
	pinta.position = pinta.pos_base
	pinta.rotation_degrees = 0.0
	pinta.scale = Vector2.ONE * ESCALA_PINTA


func _colocar_carta_de_otro(asiento: int, id_carta: String) -> void:
	var relativa := _posicion_relativa(asiento)
	var nueva_carta = ESCENA_CARTA.instantiate()
	nueva_carta.escala_base = ESCALA_MESA
	nueva_carta.pos_base = _pos_carta_baza(relativa)
	nueva_carta.rot_base = 0.0
	nueva_carta.set_meta("relativa", relativa)
	nueva_carta.set_meta("id_carta", id_carta)
	add_child(nueva_carta)
	nueva_carta.inicializar(id_carta)
	if nueva_carta.tween_actual:
		nueva_carta.tween_actual.kill()
	nueva_carta.position = nueva_carta.pos_base
	nueva_carta.rotation_degrees = 0.0
	nueva_carta.scale = Vector2.ONE * ESCALA_MESA
	nueva_carta.bloqueada = true
	nueva_carta.current_state = CartaMesa.State.IDLE
	nueva_carta.z_index = 1
	cartas_otros_en_mesa.append(nueva_carta)


func _jugar_solo(ids: Array) -> void:
	var vista_al_pedir := _vista
	await get_tree().create_timer(espera_autojugar_carta).timeout
	# Mientras esperaba ha llegado otro estado, o ya hay una carta tuya en la mesa.
	if not is_same(vista_al_pedir, _vista) or carta_en_mesa != null:
		return
	for carta in cartas_en_mano:
		if ids.has(carta.id):
			_jugar_carta_en_mesa(carta)
			return


func _crear_texto(tam_fuente: int) -> Label:
	var etiqueta := Label.new()
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ajustes := LabelSettings.new()
	ajustes.font_size = tam_fuente
	ajustes.outline_size = 6
	ajustes.outline_color = Color.BLACK
	etiqueta.label_settings = ajustes
	return etiqueta


# --- Depuración: panel oculto (F3, solo en builds de depuración) ---

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TECLA_DEPURACION:
		var panel := _obtener_panel_depuracion()
		panel.visible = not panel.visible
		_refrescar_depuracion()


func _obtener_panel_depuracion() -> PanelContainer:
	if _panel_depuracion == null:
		_panel_depuracion = PanelContainer.new()
		_panel_depuracion.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.8)
		estilo.set_content_margin_all(10)
		_panel_depuracion.add_theme_stylebox_override("panel", estilo)
		_panel_depuracion.position = Vector2(10, 60)
		_texto_depuracion = Label.new()
		_texto_depuracion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_texto_depuracion.custom_minimum_size = Vector2(560, 0)
		_panel_depuracion.add_child(_texto_depuracion)
		_panel_depuracion.z_index = 200
		_panel_depuracion.visible = false
		add_child(_panel_depuracion)
	return _panel_depuracion


func _refrescar_depuracion() -> void:
	if _panel_depuracion == null or not _panel_depuracion.visible:
		return
	_texto_depuracion.text = "DEPURACIÓN (F3)\n%s\n%s\n--- últimos avisos ---\n%s" % [
		_info_partida, _marcador, "\n".join(_registro)]


func _depurar(texto: String) -> void:
	_registro.append(texto)
	if _registro.size() > LINEAS_DEPURACION:
		_registro.remove_at(0)
	_refrescar_depuracion()


# --- Utilidades ---

func _es_asiento(asiento: int) -> bool:
	return asiento >= 0 and asiento < num_jugadores


## Hueco de la mesa de quien juega: 0 = tú, 1 = derecha, 2 = enfrente, 3 = izquierda.
## En la mesa de 2 el rival se sienta enfrente, así que usa el hueco 2.
func _posicion_relativa(asiento: int) -> int:
	var relativa := (asiento - mi_asiento + num_jugadores) % num_jugadores
	if num_jugadores == 2 and relativa == 1:
		return 2
	return relativa


## "J3" para el tercer asiento: el número dice el asiento y la pareja.
func _abreviatura(asiento: int) -> String:
	return "J%d" % (asiento + 1)


## La etiqueta del asiento: "J3", o "J3 · Lorenzo" si se sabe su nombre.
func _etiqueta_de(asiento: int) -> String:
	var nombre := _nombre(asiento)
	if nombre == "":
		return _abreviatura(asiento)
	return "%s · %s" % [_abreviatura(asiento), nombre]


func _nombre(asiento: int) -> String:
	return str(nombres[asiento]) if _es_asiento(asiento) and asiento < nombres.size() else ""


func _nombre_o_abreviatura(asiento: int) -> String:
	var nombre := _nombre(asiento)
	return nombre if nombre != "" else _abreviatura(asiento)


## "oros_12" -> "oros".
func _palo_de(id_carta: String) -> String:
	var partes := id_carta.split("_")
	return partes[0] if partes.size() == 2 else "?"


## "oros_12" -> 12.
static func valor_de(id_carta: String) -> int:
	return id_carta.get_slice("_", 1).to_int()


## "oros_12" -> "Rey de oros".
func _nombre_carta(id_carta: String) -> String:
	if id_carta.is_empty():
		return "?"
	return "%s de %s" % [NOMBRE_VALOR.get(valor_de(id_carta), "?"), _palo_de(id_carta)]
