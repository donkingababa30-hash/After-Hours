class_name Mannequin
extends MallAgent
## A clothing-store display that only creeps while the beam is not on it.
## FSM: HELD while lit, CHASE while unlit. It paths around the racks, so hiding
## behind a shelf no longer saves you.
##
## The beam had to become a real counter. Freezing it in place meant the guard
## could never actually be rid of it: light it, walk away, and it resumed behind
## you, so it trailed people right across the mall with no way to end it. While
## lit it now gives ground, and driving it off is what finishes the encounter.

const SFX_SCRAPE := preload("res://assets/generated/audio/scrape.mp3")

@export var move_speed := 132.0
## How fast it backs away while the beam is on it. Slower than the guard walks,
## so you can always keep the light on it and push it out.
@export var retreat_speed := 58.0
@export var look_half_angle := 0.9
@export var beam_range := 240.0

@onready var sprite: AnimatedSprite2D = $Sprite

var _scrape_t := 0.9


func _on_activate_visuals() -> void:
	if sprite != null:
		sprite.play("creep")


func is_frozen() -> bool:
	return state == State.HELD


func _think(delta: float) -> void:
	if in_beam(look_half_angle, beam_range):
		set_state(State.HELD)
	else:
		set_state(State.CHASE)
		# The scraping is the warning: you hear it before you see it.
		_scrape_t -= delta
		if _scrape_t <= 0.0:
			_scrape_t = 0.9
			ZivaSfx.play(self, SFX_SCRAPE, 0.12, -15.0)
	if sprite == null:
		return
	if not sprite.is_playing():
		sprite.play("creep")
	# Being under the beam is now visible rather than simply frozen: it walks
	# backwards, and it runs cold and pale blue while it does it.
	if state == State.HELD:
		sprite.modulate = Color(0.68, 0.76, 0.95)
	else:
		sprite.modulate = Color(0.85, 0.85, 0.9)


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
