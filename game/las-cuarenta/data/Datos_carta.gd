extends Resource

class_name Carta

enum palos{
	oros, copas, espadas, bastos
}

@export var id : String = "reverse"
@export var palo : palos= palos.oros
@export_range(0,12,1) var valor := 0
@export var imagen : CompressedTexture2D 
