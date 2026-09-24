extends Resource

class_name Carta

enum Palo { OROS, COPAS, ESPADAS, BASTOS }



@export var id : String = "reverse"
@export var palo : Palo = Palo.OROS
@export_range(0,12,1) var valor := 0
@export var imagen : CompressedTexture2D 
