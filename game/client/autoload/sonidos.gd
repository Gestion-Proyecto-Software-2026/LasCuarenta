extends Node
## Sonidos del cliente (PBI-21): una carta al repartir, robar y jugarla, y un
## aviso cuando te toca. Aquí solo se sabe hacerlos sonar; cuándo toca cada uno
## en la mesa lo decide client/ui/mesa/sonidos_mesa.gd.
##
## Los ficheros están en client/assets/sonidos/ (Kenney, CC0); de dónde sale
## cada uno está en su CREDITOS.md. Con el ajuste "Sonido" desactivado no suena
## nada, y si se desactiva mientras suena algo, se para.

## Ha empezado a sonar [param nombre] (una de las constantes de abajo). Para
## los tests: en headless no se oye nada, pero se sabe qué habría sonado.
signal reproducido(nombre: String)

const REPARTIR := "repartir"
const ROBAR := "robar"
const CARTA := "carta"
const TURNO := "turno"

## Las variantes de cada sonido: cada vez suena una al azar, para que diez
## cartas seguidas no suenen todas igual.
const RUTAS := {
	REPARTIR: ["res://client/assets/sonidos/repartir.ogg"],
	ROBAR: [
		"res://client/assets/sonidos/robar_1.ogg",
		"res://client/assets/sonidos/robar_2.ogg",
		"res://client/assets/sonidos/robar_3.ogg",
	],
	CARTA: [
		"res://client/assets/sonidos/carta_1.ogg",
		"res://client/assets/sonidos/carta_2.ogg",
		"res://client/assets/sonidos/carta_3.ogg",
		"res://client/assets/sonidos/carta_4.ogg",
	],
	TURNO: ["res://client/assets/sonidos/turno.ogg"],
}
## Cuántos sonidos pueden sonar a la vez: la carta del rival y tu robo llegan
## casi juntos y no deben cortarse el uno al otro.
const VOCES := 4

## Inyectable en tests (una instancia de ajustes.gd con una ruta temporal).
var ajustes = Ajustes:
	set(nuevos):
		_desconectar_ajustes()
		ajustes = nuevos
		_conectar_ajustes()

var _variantes: Dictionary = {}  # nombre -> Array[AudioStream]
var _voces: Array[AudioStreamPlayer] = []
var _siguiente_voz := 0


func _ready() -> void:
	for nombre: String in RUTAS:
		var streams: Array[AudioStream] = []
		for ruta: String in RUTAS[nombre]:
			var stream := load(ruta) as AudioStream
			if stream:
				streams.append(stream)
		_variantes[nombre] = streams
	for i in VOCES:
		var voz := AudioStreamPlayer.new()
		voz.name = "Voz%d" % i
		add_child(voz)
		_voces.append(voz)
	_conectar_ajustes()


## Hace sonar una variante de [param nombre]. Devuelve false (y no suena ni
## emite nada) si el sonido está desactivado o no hay ningún sonido con ese nombre.
func reproducir(nombre: String) -> bool:
	if not is_instance_valid(ajustes) or not ajustes.sonido:
		return false
	var variantes: Array = _variantes.get(nombre, [])
	if variantes.is_empty():
		return false
	var voz := _voz_libre()
	voz.stream = variantes.pick_random()
	voz.play()
	reproducido.emit(nombre)
	return true


## Calla todo lo que esté sonando.
func parar() -> void:
	for voz in _voces:
		voz.stop()


func sonando() -> bool:
	return _voces.any(func(voz: AudioStreamPlayer) -> bool: return voz.playing)


## La primera voz callada; si suenan todas, se van cortando por turnos.
func _voz_libre() -> AudioStreamPlayer:
	for voz in _voces:
		if not voz.playing:
			return voz
	var voz := _voces[_siguiente_voz]
	_siguiente_voz = (_siguiente_voz + 1) % _voces.size()
	return voz


func _on_ajuste_cambiado(clave: String, valor: Variant) -> void:
	if clave == "sonido" and not valor:
		parar()


func _conectar_ajustes() -> void:
	if is_instance_valid(ajustes) and not ajustes.cambiado.is_connected(_on_ajuste_cambiado):
		ajustes.cambiado.connect(_on_ajuste_cambiado)


func _desconectar_ajustes() -> void:
	if is_instance_valid(ajustes) and ajustes.cambiado.is_connected(_on_ajuste_cambiado):
		ajustes.cambiado.disconnect(_on_ajuste_cambiado)
