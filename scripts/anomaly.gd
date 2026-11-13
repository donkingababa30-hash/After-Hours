class_name Anomaly
extends Interactable
## Something that should not be there. The player has to find it and inspect it.

signal logged(anomaly: Anomaly)

var message := "You found it."

@onready var sprite: Sprite2D = $Sprite
@onready var glow: PointLight2D = $Glow

var _t := 0.0
var _done := false
var _tex := ""
var _msg := ""
var _col := Color(0.72, 0.08, 0.08)


func _ready() -> void:
	super._ready()
	prompt_text = "Inspect"
	one_shot = true
	add_to_group("anomaly")
	_apply()


func setup(texture_path: String, found_message: String, glow_color: Color) -> void:
	_tex = texture_path
	_msg = found_message
	_col = glow_color
	if is_node_ready():
		_apply()


func _apply() -> void:
	if _tex != "":
		sprite.texture = load(_tex)
	glow.color = _col
	if _msg != "":
		message = _msg


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	glow.energy = 0.22 + sin(_t * 1.6) * 0.10
	glow.texture_scale = 0.85 + sin(_t * 1.6) * 0.05


func interact(_player: Node) -> void:
	if _done:
		return
	_done = true
	glow.enabled = false
	logged.emit(self)