class_name ServicePanel
extends Interactable
## The service door's control panel, mounted on the wall BESIDE the door.
##
## It is deliberately a DIFFERENT object from the door. The door and its control
## used to be the same node, so there was no sequence for the player to
## understand: you walked at a door and the game played a wire puzzle at you, and
## the report was that the objective never said which object to use. Now the panel
## is the puzzle and the door is the door, the objective names both, and the door
## says out loud that it is waiting on the panel.
##
## Its art is an electrical cabinet with the door swung open on rows of breakers,
## which cannot be mistaken for a door at a glance.

signal rerouted

const SFX_BEEP := preload("res://assets/generated/audio/camera_beep.mp3")

@onready var sprite: Sprite2D = $Sprite

var done := false


func _ready() -> void:
	super._ready()
	add_to_group("service_panel")
	# An objective object: it must never lose the prompt to a bin beside it.
	prompt_priority = 6
	_refresh()


func _refresh() -> void:
	if done:
		prompt_text = "Control rerouted"
		# Stand down. The panel and the door are close enough that both are in
		# reach at once, and while the panel outranks the door the guard cannot
		# take the step the panel just unlocked.
		prompt_priority = 0
		if sprite != null:
			sprite.modulate = Color(0.7, 1.0, 0.76)
	else:
		prompt_text = "Reroute the door control"
		prompt_priority = 6
		if sprite != null:
			sprite.modulate = Color(1, 1, 1)


func interact(_player: Node) -> void:
	if done:
		_say("The control is already rerouted. Seal the door.")
		return
	var panel := get_tree().get_first_node_in_group("minigame")
	if panel != null:
		panel.call("open", "wires", "SERVICE DOOR CONTROL")
		var result: Variant = await panel.finished
		var solved := false
		if typeof(result) == TYPE_ARRAY:
			solved = bool(result[0])
		else:
			solved = bool(result)
		if not solved:
			_say("The panel sparks and resets. Try again.")
			return
	done = true
	_refresh()
	ZivaSfx.play(self, SFX_BEEP, 0.05, -4.0)
	_say("Control rerouted. The service door will answer now.")
	rerouted.emit()


func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(text)
