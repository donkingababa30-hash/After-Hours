class_name TaskItem
extends Interactable
## One configurable world object that covers every hands-on duty.
##
##   "wires" / "breaker" / "codes"  - opens that repair panel, emits `solved`
##   "carry"                        - can be picked up, emits `picked_up`
##
## The duty board spawns these where a night's list needs them, so adding a new
## kind of task means adding a case here, not a new scene.

signal solved
signal picked_up

const SFX_BEEP := preload("res://assets/generated/audio/camera_beep.mp3")

@onready var sprite: Sprite2D = $Sprite

var kind := "codes"
var title := "REPAIR PANEL"
var carry_kind := ""


## Called before the node is in the tree, so everything is applied in _ready().
func setup(task_kind: String, panel_title: String, texture_path: String, carry: String = "") -> void:
	kind = task_kind
	title = panel_title
	carry_kind = carry
	set_meta("texture_path", texture_path)


func _ready() -> void:
	super._ready()
	add_to_group("task_item")
	# A duty object must never lose the prompt to a nearby desk or duty log.
	prompt_priority = 10
	var path := str(get_meta("texture_path", ""))
	if path != "":
		sprite.texture = load(path)
	if kind == "carry":
		prompt_text = "Take the %s" % carry_kind
	else:
		prompt_text = title.capitalize()


func interact(_player: Node) -> void:
	if kind == "carry":
		picked_up.emit()
		queue_free()
		return

	var panel := get_tree().get_first_node_in_group("minigame")
	if panel == null:
		solved.emit()
		return
	panel.call("open", kind, title)
	var result: Variant = await panel.finished
	var ok := false
	if typeof(result) == TYPE_ARRAY:
		ok = bool(result[0])
	else:
		ok = bool(result)
	if ok:
		ZivaSfx.play(self, SFX_BEEP, 0.05, -7.0)
		solved.emit()