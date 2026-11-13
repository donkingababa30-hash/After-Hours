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
## Seconds after it appears before it can actually hunt. The winding-up sound and
## the dimmed sprite are the warning; without this window the toys reached the
## guard in about three seconds and the encounter was over before it was readable.
@export var wake_delay := 2.5

const SFX_WIND := preload("res://assets/generated/audio/scrape.mp3")

@onready var sprite: AnimatedSprite2D = $Sprite

var home := Vector2.ZERO
var _wake_t := 0.0
var _cue_t := 0.0


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


func _think(delta: float) -> void:
	# Wind-up: it must be audible and visible before it can be lethal. The greyed
	# sprite is the tell that it is still winding; once it takes on its angry tint
	# it is hunting.
	if _wake_t < wake_delay:
		_wake_t += delta
		set_state(State.PATROL)
		if sprite != null:
			sprite.modulate = Color(0.7, 0.66, 0.68)
		# A frantic little winding creak: you hear it turning before it comes, so
		# the wind-up window is audible as well as visible.
		_cue_t -= delta
		if _cue_t <= 0.0:
			_cue_t = 0.45
			ZivaSfx.play(self, SFX_WIND, 0.5, -13.0)
		return
	# Both senses need a clear line. A torch burning on the far side of a shop
	# wall used to wind a toy up right through the wall.
	var drawn := target != null and target.flashlight_on \
		and global_position.distance_to(target.global_position) <= light_sense \
		and has_line_of_sight(target.global_position)
	var close := target != null and global_position.distance_to(target.global_position) <= 130.0 \
		and has_line_of_sight(target.global_position)
	if drawn or close:
		set_state(State.CHASE)
		if target != null:
			note_contact(target.global_position)
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