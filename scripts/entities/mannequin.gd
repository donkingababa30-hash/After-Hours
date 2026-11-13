class_name Mannequin
extends MallAgent
## A clothing-store display that only creeps while the beam is not on it.
## FSM: HELD while lit, CHASE while unlit. It paths around the racks, so hiding
## behind a shelf no longer saves you.
##
## The beam had to become a real counter. Freezing it in place meant the guard
## could never actually be rid of it: light it, walk away, and it resumed behind
## you, so it trailed people right across the mall - and into the office - with no
## way to end it.
##
## Two readable ways out:
##   1. Hold the beam on it and keep walking. It backs away, slower than the guard
##      walks, and past MANNEQUIN_ESCAPE it gives up for good.
##   2. Reach the security office. It will not cross the threshold, and after a
##      few seconds it loses interest entirely.

## Emitted when it loses interest and leaves. The encounter manager resolves on it.
signal gave_up

const SFX_SCRAPE := preload("res://assets/generated/audio/scrape.mp3")

@export var move_speed := 132.0
## How fast it backs away while the beam is on it. Slower than the guard walks,
## so you can always keep the light on it and push it out.
@export var retreat_speed := 58.0
@export var look_half_angle := 0.9
@export var beam_range := 240.0
## Seconds the guard must hold out inside the office before it gives up.
@export var give_up_seconds := 6.0

@onready var sprite: AnimatedSprite2D = $Sprite

var _scrape_t := 0.9
var _held_out_t := 0.0


func _on_activate_visuals() -> void:
	if sprite != null:
		sprite.play("creep")


func is_frozen() -> bool:
	return state == State.HELD


func _think(delta: float) -> void:
	if target == null:
		return

	# The security office is a safe room, and this is a hard rule rather than a
	# soft one: it gives ground and will not cross the threshold. Holding out for
	# a few seconds makes it lose interest completely - the escape route a guard
	# can work out unaided, and what stops the encounter leaking into the one room
	# they are supposed to be able to use.
	#
	# The orientation dummy is exempt: the tutorial has to be able to stand a
	# mannequin still inside the office and watch it stop.
	if target.in_safe_room and not is_in_group("practice_mannequin"):
		_held_out_t += delta
		set_state(State.HELD)
		_paint(Color(0.7, 0.74, 0.86))
		if _held_out_t >= give_up_seconds:
			_held_out_t = 0.0
			gave_up.emit()
		return
	_held_out_t = 0.0

	if in_beam(look_half_angle, beam_range):
		set_state(State.HELD)
		_paint(Color(0.68, 0.76, 0.95))
	else:
		set_state(State.CHASE)
		_paint(Color(0.85, 0.85, 0.9))
		if target != null:
			note_contact(target.global_position)

	# The scraping is the warning in both states: you hear it before you see it.
	_scrape_t -= delta
	if _scrape_t <= 0.0:
		_scrape_t = 0.9
		ZivaSfx.play(self, SFX_SCRAPE, 0.12, -15.0)


## Being held off is visible rather than simply frozen: it walks backwards, cold
## and pale blue while the beam is on it.
func _paint(col: Color) -> void:
	if sprite == null:
		return
	if not sprite.is_playing():
		sprite.play("creep")
	sprite.modulate = col


func _goal() -> Vector2:
	if target == null:
		return global_position
	if state == State.HELD:
		# Give ground. A short step, re-aimed every frame, so it reads as a steady
		# retreat rather than a lurch.
		var away := global_position - target.global_position
		if away.length() < 1.0:
			away = Vector2.RIGHT
		return global_position + away.normalized() * 72.0
	return target.global_position


func _speed_for_state() -> float:
	if state == State.HELD:
		return retreat_speed
	return move_speed if state == State.CHASE else 0.0
