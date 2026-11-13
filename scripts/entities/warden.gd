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
const SFX_STEP := preload("res://assets/generated/audio/footstep.mp3")

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
## Cadence of its footfalls. Their volume is the guard's only way to judge how
## close it is, and hearing is the whole of its hunting method - so the tell has
## to be steady and readable rather than decorative.
var _step_t := 0.5
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
		if target != null:
			# Its memory is set by sound as well as sight: it walks to where it
			# last HEARD the guard, not to where the guard is. Standing still
			# therefore does not just stop it closing - it makes the Warden lose
			# the trail, which is the whole counter.
			note_contact(target.global_position)
	else:
		set_state(State.PATROL)
		_tint(Color(0.6, 0.66, 0.8))

	# A heavy footfall whose volume says how near it is. Hearing it is how the
	# guard decides to stand still - so it has to arrive before the catch, not
	# with it.
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.5 if state == State.CHASE else 0.72
		var dist := 800.0
		if target != null and is_instance_valid(target):
			dist = global_position.distance_to(target.global_position)
		ZivaSfx.play(self, SFX_STEP, 0.35, lerpf(-5.0, -27.0, clampf(dist / 800.0, 0.0, 1.0)))


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


## How far through the latch it is, in seconds, so the HUD can count down. A
## countdown is the difference between "I am going to die and I do not know when"
## and "I have nine seconds to reach the office" - and only the second one is a
## decision the player can make.
func latch_progress() -> float:
	return _latch_t


func _tint(colour: Color) -> void:
	if sprite != null:
		sprite.modulate = colour