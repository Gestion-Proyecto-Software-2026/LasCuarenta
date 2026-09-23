extends Resource

class_name Carta



@export var id : String = "reverse"
@export var palo :  FuncionesGlobales.palos= FuncionesGlobales.palos.oros
@export_range(0,12,1) var valor := 0
@export var imagen : CompressedTexture2D 
