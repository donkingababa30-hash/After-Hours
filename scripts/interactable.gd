class_name Interactable
extends Area2D
## Base class for anything the player can walk up to and press E on.

@export var prompt_text := "Press E to interact"
@export var one_shot := false
## Higher wins when two interactables are both in reach. Objective objects should
## never be blocked by scenery that happens to be standing next to them.
## (Area2D already owns a `priority` property, hence the longer name.)
@export var prompt_priority := 0

var _used := false


func _ready() -> void:
	add_to_group("interactable")
	monitorable = true
	monitoring = false
	collision_layer = 4
	collision_mask = 0


## Override in subclasses to define what happens on interaction.
func interact(_player: Node) -> void:
	pass


func is_available() -> bool:
	return not (one_shot and _used)


func get_prompt() -> String:
	return prompt_text


func mark_used() -> void:
	_used = true