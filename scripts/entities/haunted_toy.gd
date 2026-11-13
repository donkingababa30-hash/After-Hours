class_name HauntedToy
extends MallAgent
## A wind-up toy in the TOYBOX. FSM: PATROL between the shelves, CHASE while the
## guard's torch is burning anywhere near it.
##
## Surviving rule: it is drawn to light. Kill the flashlight and it winds down
## and loses interest - so the battery in your hand is also your way out.

@export var wander_speed := 54.0
@export var hunt_speed := 108.0
@export var light_sense := 300.0

@onready var sprite: AnimatedSprite2D = $Sprite

var home := Vector2.ZERO


func _on_activate_visuals() -> void:
	if sprite != null:
		sprite.play("walk")


## Patrol loop around wherever the toy was standing.
func set_home(point: Vector2) -> void:
	home = point
	patrol_points = [
		point,
		point + Vector2(150, 70),
		point + Vector2(-140, 96),
		point + Vector2(40, -84),
	]


func _think(_delta: float) -> void:
	var drawn := target != null and target.flashlight_on \
		and global_position.distance_to(target.global_position) <= light_sense
	var close := target != null and global_position.distance_to(target.global_position) <= 130.0
	if drawn or close:
		set_state(State.CHASE)
	else:
		set_state(State.PATROL)
	if sprite != null:
		sprite.modulate = Color(1, 0.82, 0.82) if state == State.CHASE else Color(1, 1, 1)


func _goal() -> Vector2:
	if state == State.CHASE and target != null:
		return target.global_position
	return _patrol_goal()


func _speed_for_state() -> float:
	return hunt_speed if state == State.CHASE else wander_speed