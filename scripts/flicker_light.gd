class_name FlickerLight
extends PointLight2D
## A ceiling light that hums and occasionally stutters.

@export var base_energy := 0.35
@export var flicker_speed := 6.0
@export var flicker_amount := 0.35
@export var blackout_chance := 0.02

var _t := 0.0


func _ready() -> void:
	add_to_group("mall_light")
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := sin(_t) * 0.5 + sin(_t * 2.3 + 1.7) * 0.3 + sin(_t * 5.1) * 0.2
	var e := base_energy + n * flicker_amount * base_energy
	if randf() < blackout_chance:
		e = 0.0
	energy = maxf(e, 0.0)