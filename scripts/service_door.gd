class_name ServiceDoor
extends Interactable
## The east service door. It spends the start of the night wedged open, which
## killed the power to the east wing. Closing it is the first task of the shift.

signal door_closed

const SFX_CLOSE := preload("res://assets/generated/audio/shutter.mp3")
const TEX_OPEN := "res://assets/generated/door_service_open.png"
const TEX_CLOSED := "res://assets/generated/door_service_closed.png"

@onready var sprite: Sprite2D = $Sprite

var is_open := true


func _ready() -> void:
	super._ready()
	add_to_group("service_door")
	# NOT one_shot: the wire panel can be failed or abandoned, and the guard has
	# to be able to come back and try again.
	one_shot = false
	_apply()


func _apply() -> void:
	if is_open:
		sprite.texture = load(TEX_OPEN)
		_apply_prompt()
	else:
		sprite.texture = load(TEX_CLOSED)
		prompt_text = "Sealed"


func _apply_prompt() -> void:
	prompt_text = "Reroute the door control"


## Used when a loaded save says the door was already sealed.
func force_closed() -> void:
	is_open = false
	_apply()


func interact(_player: Node) -> void:
	if not is_open:
		return
	prompt_text = "Reroute the door control"
	var wired := await _run_wire_task()
	if not wired:
		# A mis-wired panel trips the alarm and wastes the guard's time.
		ZivaSfx.play(self, SFX_CLOSE, 0.05, -2.0)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null:
			hud.show_message("The panel sparks and resets. The door stays open.")
		var manager := get_tree().get_first_node_in_group("encounter_manager")
		if manager != null and manager.has_method("on_door_fumbled"):
			manager.call("on_door_fumbled")
		prompt_text = "Reroute the door control"
		_apply()
		_apply_prompt()
		return
	is_open = false
	_apply()
	ZivaSfx.play(self, SFX_CLOSE, 0.05, -5.0)
	door_closed.emit()


## Hands the player the wire panel and waits for the result.
func _run_wire_task() -> bool:
	var panel := get_tree().get_first_node_in_group("minigame")
	if panel == null:
		return true
	panel.call("open", "wires", "SERVICE DOOR CONTROL")
	var result: Variant = await panel.finished
	if typeof(result) == TYPE_ARRAY:
		return bool(result[0])
	return bool(result)