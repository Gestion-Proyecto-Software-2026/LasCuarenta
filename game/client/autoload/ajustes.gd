extends Node
## Preferencias del jugador en este ordenador (PBI-21): de momento, si suenan
## los sonidos. Se guardan con ConfigFile en [constant RUTA_POR_DEFECTO] (en
## Windows, %APPDATA%/Godot/app_userdata/Cartas Online/ajustes.cfg) para que se
## recuerden al volver a abrir la aplicación. No van al backend: son de este
## ordenador, no de la cuenta.
##
## Quien necesite un ajuste lo lee de aquí y escucha [signal cambiado] para
## enterarse si el jugador lo cambia mientras está abierto (p. ej. el autoload
## Sonidos se calla al desactivarlo). Lo cambia el panel de ajustes
## (client/ui/ajustes/panel_ajustes.gd).

## Un ajuste ha cambiado: [param clave] es su nombre ("sonido") y [param valor] el nuevo.
signal cambiado(clave: String, valor: Variant)

const RUTA_POR_DEFECTO := "user://ajustes.cfg"
const SECCION := "cliente"

## Dónde se guardan. Los tests usan su propia instancia con una ruta temporal,
## para no tocar los ajustes de verdad de quien los ejecuta.
var ruta := RUTA_POR_DEFECTO
## Si suenan los sonidos de la mesa (PBI-21).
var sonido := true


func _ready() -> void:
	cargar()


## Lee [member ruta]. Si no existe (primera vez) o no se puede leer, se quedan
## los valores por defecto: no es un error, solo que aún no se ha cambiado nada.
func cargar() -> void:
	sonido = true
	var archivo := ConfigFile.new()
	if not FileAccess.file_exists(ruta) or archivo.load(ruta) != OK:
		return
	sonido = _leer_bool(archivo, "sonido", true)


## Escribe todos los ajustes en [member ruta].
func guardar() -> void:
	var archivo := ConfigFile.new()
	archivo.set_value(SECCION, "sonido", sonido)
	var error := archivo.save(ruta)
	if error != OK:
		# Sin poder guardar se sigue jugando igual: solo no se recordará.
		push_warning("No se han podido guardar los ajustes en %s (error %d)" % [ruta, error])


func poner_sonido(activado: bool) -> void:
	if sonido == activado:
		return
	sonido = activado
	guardar()
	cambiado.emit("sonido", activado)


## Un valor del fichero solo vale si es del tipo esperado (lo puede haber
## tocado alguien a mano); si no, el de por defecto.
static func _leer_bool(archivo: ConfigFile, clave: String, por_defecto: bool) -> bool:
	var valor: Variant = archivo.get_value(SECCION, clave, por_defecto)
	return valor if valor is bool else por_defecto
