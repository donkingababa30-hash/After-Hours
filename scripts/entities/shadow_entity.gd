class_name ShadowEntity
extends MallAgent
## A shape that works the corridors. FSM: PATROL when it has no idea where you
## are, CHASE once it senses you or you shine a light at it. It walks the
## corridors properly now, so it can cut you off instead of hugging a wall.

@export var lurk_speed := 62.0
@export var charge_speed := 140.0

const SFX_CUE := preload("res://assets/generated/audio/breath.mp3")

@onready var sprite: AnimatedSprite2D = $Sprite

var aggressive := false
var _aggression := 0.0
var _cue_t := 1.2


func _ready() -> void:
	super._ready()
	sense_distance = 520.0


func _on_activate_visuals() -> void:
	if sprite != null:
		sprite.play("float")
	patrol_points = [
		Vector2(320, 528), Vector2(1024, 528), Vector2(1700, 528), Vector2(1990, 528),
		Vector2(1990, 1008), Vector2(1024, 1008), Vector2(320, 1008),
		Vector2(320, 1488), Vector2(1024, 1488), Vector2(1700, 1488),
	]


func _think(delta: float) -> void:
	var lit := in_beam(0.85, 300.0)
	var too_close := target != null and target.flashlight_on \
		and global_position.distance_to(target.global_position) < 80.0 \
		and has_line_of_sight(target.global_position)
	if lit or too_close:
		_aggression = 1.5
	else:
		_aggression = maxf(0.0, _aggression - delta)
	aggressive = _aggression > 0.0

	if aggressive or _can_sense():
		set_state(State.CHASE)
		if target != null:
			note_contact(target.global_position)
	else:
		set_state(State.PATROL)

	if sprite != null:
		sprite.modulate = Color(1, 0.75, 0.75) if aggressive else Color(1, 1, 1)

	# A cold exhalation while it is locked on - the audible half of the red tint,
	# so the player is told their light has been noticed before it closes.
	_cue_t -= delta
	if _cue_t <= 0.0:
		_cue_t = 2.4
		if aggressive:
			ZivaSfx.play(self, SFX_CUE, 0.5, -18.0)


func _goal() -> Vector2:
	if state == State.CHASE and target != null:
		return target.global_position
	return _patrol_goal()


func _speed_for_state() -> float:
	if state == State.PATROL:
		return lurk_speed
	return charge_speed if aggressive else lurk_speed