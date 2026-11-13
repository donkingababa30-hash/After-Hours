class_name WatchItem
extends Interactable
## Something in the mall that is wrong, and that only a guard standing in front
## of it can settle.
##
## The standing still is the point. Working an incident roots the guard for over
## a second, and in this mall the most expensive thing you can do is stop moving.
## That is what turns "go and press E" into a decision about when it is safe to
## do your job.

signal resolved

const SFX_OPEN := preload("res://assets/generated/audio/shutter.mp3")
## Long enough to be a real cost, short enough not to be a punishment.
const WORK_SECONDS := 1.3

@onready var sprite: Sprite2D = $Sprite
@onready var glow: PointLight2D = $Glow

var report := "Dealt with."
var _busy := false
var _pulse_t := 0.0


## Called before the node enters the tree, so everything lands in _ready().
func setup(texture_path: String, what: String, done_text: String) -> void:
	set_meta("texture_path", texture_path)
	set_meta("done_text", done_text)
	prompt_text = what


func _ready() -> void:
	super._ready()
	add_to_group("watch_item")
	# Above a duty object: an open incident is the live job.
	prompt_priority = 20
	var path := str(get_meta("texture_path", ""))
	if path != "":
		sprite.texture = load(path)
	report = str(get_meta("done_text", report))


func is_available() -> bool:
	return not _busy


## The glow is how the guard finds this at all in a dark wing. It pulses, so it
## reads as "here" rather than as ordinary shop lighting.
func _process(delta: float) -> void:
	_pulse_t += delta
	var pulse := 0.5 + sin(_pulse_t * 3.4) * 0.5
	glow.texture_scale = 0.9 + pulse * 0.5
	glow.energy = 0.5 + pulse * 0.5


func interact(player: Node) -> void:
	if _busy:
		return
	_busy = true
	var walker := player as Player
	if walker != null:
		walker.can_move = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message("Working on it. Do not let anything walk up on you.")
	ZivaSfx.play(self, SFX_OPEN, 0.08, -10.0)

	await get_tree().create_timer(WORK_SECONDS).timeout

	if walker != null and is_instance_valid(walker):
		walker.can_move = true
	if hud != null:
		hud.show_message(report)
	resolved.emit()
	queue_free()