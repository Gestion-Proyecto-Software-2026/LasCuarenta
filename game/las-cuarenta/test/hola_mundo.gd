extends Node2D

@onready var Label_carta : Label = $Sprite2D/Label
var pulsado : bool = false
var dentro : bool = false
# Called when the node enters the scene tree for the first time.
func _ready():
	Label_carta.text = "Hola mundo"
	

func _on_area_2d_mouse_entered():
	Label_carta.text = "ratón entra"
	dentro = true

func _on_area_2d_mouse_exited():
	Label_carta.text = "ratón sale"
	dentro = false
