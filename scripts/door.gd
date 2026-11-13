class_name Door
extends Interactable
## A storefront shutter the player can open and close.

const SFX_SHUTTER := preload("res://assets/generated/audio/shutter.mp3")

@export var starts_open := false

@onready var shape: CollisionShape2D = $Blocker/Shape
@onready var visual: Sprite2D = $Visual

var is_open := false


func _ready() -> void:
	super._ready()
	is_open = starts_open
	_apply()


func interact(_player: Node) -> void:
	is_open = not is_open
	_apply()
	ZivaSfx.play(self, SFX_SHUTTER, 0.06, -10.0)


func _apply() -> void:
	shape.disabled = is_open
	visual.visible = not is_open
	prompt_text = "Close the shutter" if is_open else "Open the shutter"