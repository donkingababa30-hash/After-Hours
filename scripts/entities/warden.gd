class_name WardenEntity
extends MallAgent
## The Warden does not kill on contact. It CLINGS.
##
## Once it reaches the guard it latches onto their back and starts burning
## through them: the view closes in, the guard slows down, and the torch drains
## twice as fast. It will not let go on its own.
##
## Two things make it let go, and both are things the player already has:
##   - standing in a lit room, above all the security office
##   - dropping a flare at your own feet
## Light makes it slow while it rides, so keeping the torch ON buys time - even
## though a burning torch is what every other hunter in the mall is watching for.

signal latched_on
signal shaken_off

const SFX_WHISPER := preload("res://assets/generated/audio/warden_whisper.mp3")
const SFX_STING := preload("res://assets/generated/audio/sting.mp3")

## How long it can ride the guard before it finishes the job.
const LATCH_LIMIT := 13.0
## How far behind the guard it clings.
const RIDE_OFFSET := 22.0

## It hunts by ear as much as by sight: running feet carry a long way.
@export var hear_distance := 430.0

@onready var sprite: AnimatedSprite2D = $Sprite

var latched := false

var _latch_t := 0.0
var _whisper_t := 0.0
## Set when it is driven off: it backs away and gives the guard a few seconds.
var _stagger := 0.0


func _on_activate_visuals() -> void:
	if sprite != null:
		sprite.play("walk")


func _think(delta: float) -> void:
	if latched:
		_tick_latch(delta)
		return

	if _stagger > 0.0:
		_stagger -= delta
		set_state(State.PATROL)
		_tint(Color(0.5, 0.55, 0.7))
		return

	var noise: float = target.noise_level() if target != null else 0.0
	var hearing: float = hear_distance * (0.55 + noise * 0.75)
	var heard: bool = target != null and global_position.distance_to(target.global_position) <= hearing
	if heard or _can_sense():
		set_state(State.CHASE)
		_tint(Color(0.78, 0.86, 1.0))
	else:
		set_state(State.PATROL)
		_tint(Color(0.6, 0.66, 0.8))


## A catch is not a kill: it grabs hold instead.
func _on_reach_target() -> bool:
	if not latched:
		_latch()
	return true


func _latch() -> void:
	latched = true
	_latch_t = 0.0
	_whisper_t = 0.0
	set_state(State.HELD)
	ZivaSfx.play(self, SFX_STING, 0.02, -5.0)
	ZivaSfx.play(self, SFX_WHISPER, 0.05, -6.0)
	latched_on.emit()


## Riding the guard: it follows them, whispers, and counts down.
func _tick_latch(delta: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position - target.facing * RIDE_OFFSET
		# Light hurts it, so a torch left burning makes it slower.
		_latch_t += delta * (0.55 if target.flashlight_on else 1.0)

	_whisper_t -= delta
	if _whisper_t <= 0.0:
		_whisper_t = 2.4
		ZivaSfx.play(self, SFX_WHISPER, 0.09, -9.0)

	if sprite != null:
		sprite.modulate = Color(1.0, 0.72, 0.72)

	if _latch_t >= LATCH_LIMIT:
		latched = false
		active = false
		caught_player.emit()


## Driven off by light or a flare. It peels away and keeps its distance a while.
func release() -> void:
	if not latched:
		return
	latched = false
	_latch_t = 0.0
	_stagger = 5.0
	set_state(State.PATROL)
	shaken_off.emit()


func _tint(colour: Color) -> void:
	if sprite != null:
		sprite.modulate = colour