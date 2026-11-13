class_name BatteryPickup
extends Interactable
## A spare cell for the torch. The battery runs down over the shift, so finding
## replacements is part of the loop. Taken cells come back after a while, so the
## player can never end up permanently stranded in the dark.

const SFX_TAKE := preload("res://assets/generated/audio/camera_beep.mp3")
const CHARGE := 0.6
const RESPAWN_MINUTES := 150

@onready var sprite: Sprite2D = $Sprite

var available := true
var _respawn_at := 0


func _ready() -> void:
	super._ready()
	prompt_text = "Take the battery"


func is_available() -> bool:
	return available


func get_prompt() -> String:
	if not available:
		return ""
	return prompt_text


func interact(player: Node) -> void:
	if not available or not (player is Player):
		return
	(player as Player).recharge_battery(CHARGE)
	available = false
	monitorable = false
	sprite.visible = false
	_respawn_at = Game.elapsed_minutes + RESPAWN_MINUTES
	ZivaSfx.play(self, SFX_TAKE, 0.08, -4.0)


func _process(_delta: float) -> void:
	if available:
		return
	if Game.elapsed_minutes >= _respawn_at:
		available = true
		monitorable = true
		sprite.visible = true