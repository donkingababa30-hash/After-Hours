class_name Inspectable
extends Interactable
## A prop the player can examine for a line of flavour text.

@export_multiline var message := "Nothing unusual."
@export var prompt_string := "Inspect"
@export var inspect_sound := "res://assets/generated/audio/camera_beep.mp3"


func _ready() -> void:
	super._ready()
	prompt_text = prompt_string


func interact(_player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(message)
	if ResourceLoader.exists(inspect_sound):
		ZivaSfx.play(self, load(inspect_sound), 0.1, -19.0)