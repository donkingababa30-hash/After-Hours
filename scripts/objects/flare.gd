class_name Flare
extends Node2D
## A burning road flare.
##
## It throws a wide circle of warm light, and everything that hunts by sound
## comes over to look at it. Dropping one is how the guard buys a few seconds.

const BURN_TIME := 15.0
const LIGHT_RADIUS := 215.0
const NOISE_INTERVAL := 1.4

@onready var light: PointLight2D = $Light
@onready var sprite: Sprite2D = $Sprite

var _t := 0.0
var _noise_t := 0.0


func _ready() -> void:
	add_to_group("flare")
	_broadcast()


func _process(delta: float) -> void:
	_t += delta
	# Sputtering flame, so it never settles into a flat circle of light.
	light.energy = 2.2 * (0.78 + sin(_t * 17.0) * 0.12 + sin(_t * 43.0) * 0.07)
	_noise_t -= delta
	if _noise_t <= 0.0:
		_broadcast()
	if _t >= BURN_TIME:
		queue_free()


## Anything within earshot turns to look. Repeated, so hunters keep coming back
## to the flare instead of following the guard.
func _broadcast() -> void:
	_noise_t = NOISE_INTERVAL
	for node in get_tree().get_nodes_in_group("entity"):
		if node.has_method("hear_noise"):
			node.call("hear_noise", global_position)


## True while this flare is lighting the given point.
func lights(point: Vector2) -> bool:
	return _t < BURN_TIME and global_position.distance_to(point) <= LIGHT_RADIUS