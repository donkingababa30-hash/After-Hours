class_name BreakerPanel
extends Interactable
## The west wing breaker. Mid-shift the wing drops out, and the only way to get
## the lights back is to line the switches up by hand - in the dark.

signal restored

const SFX_BEEP := preload("res://assets/generated/audio/camera_beep.mp3")

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	super._ready()
	add_to_group("breaker")
	prompt_text = "Open the breaker panel"


func interact(_player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("minigame")
	if panel == null:
		restored.emit()
		return
	panel.call("open", "breakers", "WEST WING BREAKERS")
	var result: Variant = await panel.finished
	var solved := false
	if typeof(result) == TYPE_ARRAY:
		solved = bool(result[0])
	else:
		solved = bool(result)
	if solved:
		ZivaSfx.play(self, SFX_BEEP, 0.05, -4.0)
		restored.emit()