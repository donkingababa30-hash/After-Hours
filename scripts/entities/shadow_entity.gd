class_name ShadowEntity
extends MallAgent
## A shape that works the corridors. FSM: PATROL when it has no idea where you
## are, CHASE once it senses you or you shine a light at it. It walks the
## corridors properly now, so it can cut you off instead of hugging a wall.

@export var lurk_speed := 62.0
@export var charge_speed := 140.0

@onready var sprite: AnimatedSprite2D = $Sprite

var aggressive := false
var _aggression := 0.0


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
	var too_close := target != null and target.flashlight_on and global_position.distance_to(target.global_position) < 80.0
	if lit or too_close:
		_aggression = 1.5
	else:
		_aggression = maxf(0.0, _aggression - delta)
	aggressive = _aggression > 0.0

	if aggressive or _can_sense():
		set_state(State.CHASE)
	else:
		set_state(State.PATROL)

	if sprite != null:
		sprite.modulate = Color(1, 0.75, 0.75) if aggressive else Color(1, 1, 1)


func _goal() -> Vector2:
	if state == State.CHASE and target != null:
		return target.global_position
	return _patrol_goal()


func _speed_for_state() -> float:
	if state == State.PATROL:
		return lurk_speed
	return charge_speed if aggressive else lurk_speed