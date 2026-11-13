class_name SlidingDoor
extends Area2D
## Automatic glass doors. They part when the player walks up and close again
## a moment after the player leaves.

const SFX_SLIDE := preload("res://assets/generated/audio/door_slide.mp3")

## Same door layer the solid doors use: only the player masks it, so a shut
## storefront never blocks a hunter's pathing.
const DOOR_LAYER := 16

@export var door_width := 128.0

@onready var left: Sprite2D = $Left
@onready var right: Sprite2D = $Right
@onready var reach: CollisionShape2D = $Reach

var _open := false
var _tween: Tween = null
var _blocker: StaticBody2D = null


func _ready() -> void:
	add_to_group("sliding_door")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_configure()


func _configure() -> void:
	var panel_w := door_width * 0.5
	var sx := panel_w / 64.0
	left.scale = Vector2(sx, 22.0 / 24.0)
	right.scale = Vector2(sx, 22.0 / 24.0)
	left.position = Vector2(-panel_w * 0.5, 0)
	right.position = Vector2(panel_w * 0.5, 0)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(door_width + 20.0, 58.0)
	reach.shape = rect

	# The glass is solid while it is drawn shut.
	#
	# These doors are automatic: the reach rectangle is wider than the door, so
	# the guard trips the sensor and the panels part BEFORE they can touch the
	# glass. Without this the door was drawn closed and could be walked straight
	# through, which is the mismatch this whole pass exists to remove. The layer
	# comes off the instant the door starts opening, not when the slide finishes,
	# so a guard walking briskly is never stopped by their own door.
	_blocker = StaticBody2D.new()
	_blocker.collision_layer = DOOR_LAYER
	_blocker.collision_mask = 0
	var block_shape := CollisionShape2D.new()
	var glass := RectangleShape2D.new()
	glass.size = Vector2(door_width, 20.0)
	block_shape.shape = glass
	_blocker.add_child(block_shape)
	add_child(_blocker)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_set_open(true)


func _on_body_exited(body: Node) -> void:
	if not (body is Player):
		return
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self) and not _player_inside():
		_set_open(false)


func _player_inside() -> bool:
	for b in get_overlapping_bodies():
		if b is Player:
			return true
	return false


func _set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	if _blocker != null:
		_blocker.collision_layer = 0 if open else DOOR_LAYER
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var panel_w := door_width * 0.5
	var slide := panel_w * 0.94
	var target_l := Vector2(-panel_w * 0.5 - (slide if open else 0.0), 0.0)
	var target_r := Vector2(panel_w * 0.5 + (slide if open else 0.0), 0.0)
	var alpha := 0.12 if open else 1.0

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(left, "position", target_l, 0.22).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(right, "position", target_r, 0.22).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(left, "modulate:a", alpha, 0.18)
	_tween.tween_property(right, "modulate:a", alpha, 0.18)
	ZivaSfx.play(self, SFX_SLIDE, 0.05, -13.0)