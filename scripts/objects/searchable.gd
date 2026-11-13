class_name Searchable
extends Interactable
## A cabinet, drawer or locker you can go through.
##
## Searching takes a moment and leaves you standing still, and most of these
## hold nothing at all. The few supplies in this mall are hidden, not handed
## out, so finding a cell actually means something.

signal searched_loot(kind: String)

const SFX_OPEN := preload("res://assets/generated/audio/shutter.mp3")
const SEARCH_SECONDS := 0.9
const RESPAWN_MINUTES := 150

const EMPTY_LINES := [
	"Old receipts and a dried-out pen.",
	"Cleaning supplies. Nothing useful.",
	"Someone's lunch, gone grey.",
	"Pipes, fuse wire, dust.",
	"Empty. It has been empty a long time.",
]

@onready var sprite: Sprite2D = $Sprite

## "battery", "note:<text>" or "empty".
var loot := "empty"
var label := "cabinet"
var respawns := false

var looted := false
var _busy := false
var _respawn_at := 0
var _texture_path := ""


## The warm glow shown when the torch is low.
##
## Two approaches failed before this one. Tinting the cabinet sprite did nothing
## because modulate multiplies - a near-black cabinet stays near-black. A glowing
## sprite did nothing either, because the whole mall sits under a CanvasModulate
## of (0.17, 0.2, 0.29) that multiplies every canvas item, so pixels cannot out-
## shine it. Only actual light survives that, which is why this is a PointLight2D.
var _glow: PointLight2D = null


func _ready() -> void:
	super._ready()
	add_to_group("searchable")
	_build_glow()
	_apply()


func _build_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture = load("res://assets/generated/light_glow.png")
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.texture_scale = 0.7
	_glow.color = Color(1.0, 0.8, 0.42)
	_glow.energy = 0.0
	_glow.enabled = false
	add_child(_glow)


## Called right after instantiate, before the node enters the tree.
func setup(texture_path: String, loot_kind: String, what: String, can_respawn: bool = false) -> void:
	_texture_path = texture_path
	loot = loot_kind
	label = what
	respawns = can_respawn
	if is_node_ready():
		_apply()


func _apply() -> void:
	if _texture_path != "":
		sprite.texture = load(_texture_path)
	prompt_text = "Search the " + label


func is_available() -> bool:
	if _busy:
		return false
	if not looted:
		return true
	return respawns and Game.elapsed_minutes >= _respawn_at


func interact(player: Node) -> void:
	if not is_available():
		return
	_busy = true
	var walker := player as Player
	if walker != null:
		walker.can_move = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message("Going through the %s..." % label)
	ZivaSfx.play(self, SFX_OPEN, 0.08, -9.0)

	await get_tree().create_timer(SEARCH_SECONDS).timeout

	_busy = false
	if walker != null and is_instance_valid(walker):
		walker.can_move = true
	_reveal(walker)


func _reveal(player: Player) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	# Do not burn a cell on a torch that is already nearly full. Taking it used to
	# top up from the cap and waste almost the whole charge, which made finding
	# one feel like a punishment. The stash stays put, so coming back when the
	# torch is actually low still works.
	if loot == "battery" and player != null and is_instance_valid(player) and player.battery > 0.85:
		if hud != null:
			hud.show_message("A cell - but your torch is nearly full. Leave it for later.")
		return
	looted = true
	if respawns:
		_respawn_at = Game.elapsed_minutes + RESPAWN_MINUTES
	sprite.modulate = Color(0.52, 0.53, 0.6)

	if loot == "battery":
		if player != null and is_instance_valid(player):
			player.recharge_battery(0.5)
		if hud != null:
			hud.show_message("A spare cell, tucked behind the shelf. Half a charge.")
		Game.add_log_entry("Found a spare battery in the %s." % label)
	elif loot.begins_with("note:"):
		var text := loot.substr(5)
		if hud != null:
			hud.show_message(text)
		Game.add_log_entry("Read a note in the %s." % label)
	else:
		if hud != null:
			hud.show_message(EMPTY_LINES[randi() % EMPTY_LINES.size()])
	searched_loot.emit(loot)


func _process(_delta: float) -> void:
	_update_highlight()
	if not looted or not respawns:
		return
	if Game.elapsed_minutes >= _respawn_at and sprite.modulate != Color(1, 1, 1):
		looted = false
		sprite.modulate = Color(1, 1, 1)


## When the torch is running low, a container that still holds a cell glows. There
## are a dozen of these around the mall and they are ordinary-looking furniture,
## so without some signal there was no way to know which were worth the standstill
## of opening one.
func _update_highlight() -> void:
	if _glow == null:
		return
	var walker := get_tree().get_first_node_in_group("player") as Player
	var wanted := not looted and loot == "battery" and walker != null and walker.battery < 0.35
	_glow.enabled = wanted
	if not wanted:
		return
	var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.0035) * 0.5
	_glow.texture_scale = 0.6 + pulse * 0.35
	_glow.energy = 0.6 + pulse * 0.5