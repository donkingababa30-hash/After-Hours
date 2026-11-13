class_name MallDoor
extends Interactable
## A real door: solid while it is shut, passable while it is open, and openable.
##
## This is the fix for "objects that look like doors can be walked straight
## through". A doorway used to be drawn with a shut door leaf and given NO
## collision at all, because the game had no way to open a door - so a shut door
## was a lie. The leaf is a real door now: it blocks, it swings, and the picture
## on screen and the collision the player walks into are both written by the same
## _apply(), so they cannot disagree.
##
## The blocker sits on its OWN collision layer that only the player masks, so a
## shut door can never quietly stop a hunter and jam its pathing. The things in
## this mall open doors: the door senses an entity nearby and swings for it, which
## is also worth more than the bug it replaces - a door swinging open down an
## empty corridor is something to be afraid of.

signal opened
signal closed

## Doors block the guard and nobody else. Layer 1 is the world, which every agent
## masks, so a door on layer 1 would have walled the hunters in too.
const DOOR_LAYER := 16

const SFX_DOOR := preload("res://assets/generated/audio/door_slide.mp3")
const TEX_FRAME := "res://assets/generated/door_frame_open.png"
const TEX_STAFF := "res://assets/generated/door_staff.png"
const TEX_SERVICE_OPEN := "res://assets/generated/door_service_open.png"
const TEX_SERVICE_SHUT := "res://assets/generated/door_service_closed.png"

## "staff" | "service". Decides the art, the words on the prompt, and whether the
## door swings on a hinge or swaps between two drawn states.
@export var door_kind := "staff"
## Length of the opening along the wall, in pixels.
@export var door_width := 64.0
## Doors open and shut; this is which it is right now.
var is_open := false
## While set, the door refuses to move.
var locked := false
## Short form, for the prompt line under the guard. The prompt is centred on the
## screen, so a whole sentence there runs straight into the vitals bars.
var locked_prompt := "Locked"
## Full sentence, shown as a message when the player tries the handle anyway.
var locked_reason := ""

var _leaf_pivot: Node2D = null
var _leaf: Sprite2D = null
var _blocker: StaticBody2D = null
var _tween: Tween = null


func _ready() -> void:
	super._ready()
	add_to_group("door")
	if door_kind == "service":
		add_to_group("service_door")
	# An objective door must never lose the prompt to a bin standing beside it.
	prompt_priority = 4
	_build()
	# is_open is read, not forced: the service door is placed already wedged open.
	_apply(is_open, true)


func _build() -> void:
	if door_kind != "service":
		# The frame is the doorway itself - an opening with posts - and it never
		# moves. An open door therefore still reads as a doorway rather than as a
		# hole knocked through the wall.
		var frame_tex := load(TEX_FRAME) as Texture2D
		if frame_tex != null:
			var frame := Sprite2D.new()
			frame.texture = frame_tex
			frame.scale = Vector2(door_width / frame_tex.get_size().x, 1.0)
			add_child(frame)

	# The leaf hangs off a pivot at its hinge, so turning the pivot swings the door
	# rather than spinning it about its own middle.
	_leaf_pivot = Node2D.new()
	_leaf_pivot.position = Vector2(-door_width * 0.5, 0.0)
	add_child(_leaf_pivot)
	_leaf = Sprite2D.new()
	_leaf.texture = load(TEX_STAFF)
	_leaf.offset = Vector2(door_width * 0.5, 0.0)
	_leaf_pivot.add_child(_leaf)

	# Interaction reach covers the whole opening, so the prompt comes up as the
	# guard walks AT the door rather than when they are already standing in it.
	var reach := CollisionShape2D.new()
	var reach_shape := RectangleShape2D.new()
	reach_shape.size = Vector2(door_width + 18.0, 52.0)
	reach.shape = reach_shape
	add_child(reach)

	_blocker = StaticBody2D.new()
	_blocker.collision_layer = DOOR_LAYER
	_blocker.collision_mask = 0
	var block_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(door_width, 22.0)
	block_shape.shape = rect
	_blocker.add_child(block_shape)
	add_child(_blocker)

	var sensor := Area2D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = 8
	var sensor_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 62.0
	sensor_shape.shape = circle
	sensor.add_child(sensor_shape)
	add_child(sensor)
	sensor.body_entered.connect(_on_sensed)


## The ONE place the door's state is written. Everything the player can see or
## walk into is set here, which is what keeps the picture and the collision from
## ever drifting apart.
func _apply(open: bool, instant := false) -> void:
	is_open = open
	if _leaf != null:
		if door_kind == "service":
			# The service door's art already draws both states: two leaves meeting
			# with hazard stripes, and two leaves swung apart with the dark opening
			# between them. Swapping it is the honest state change.
			_leaf.texture = load(TEX_SERVICE_OPEN if open else TEX_SERVICE_SHUT)
			_leaf_pivot.rotation = 0.0
		else:
			_leaf.texture = load(TEX_STAFF)
			var target := deg_to_rad(-74.0) if open else 0.0
			if instant:
				_leaf_pivot.rotation = target
			else:
				if _tween != null and _tween.is_valid():
					_tween.kill()
				_tween = create_tween()
				# Quick. The collision is already gone the instant the door starts
				# moving, so a long swing left the guard walking through a door
				# that still looked shut.
				_tween.tween_property(_leaf_pivot, "rotation", target, 0.11) \
					.set_trans(Tween.TRANS_CUBIC)
	if _blocker != null:
		_blocker.collision_layer = 0 if open else DOOR_LAYER
	prompt_text = _prompt_for()


func _prompt_for() -> String:
	if locked:
		return locked_prompt if locked_prompt != "" else "Locked"
	if is_open:
		return "Seal the door" if door_kind == "service" else "Close the door"
	return "Open the door"


func interact(_player: Node) -> void:
	if locked:
		# Say WHY, and what would change it. A locked door with no explanation is
		# just a wall the player keeps pressing E on.
		_say(locked_reason if locked_reason != "" else locked_prompt)
		ZivaSfx.play(self, SFX_DOOR, 0.05, -16.0)
		return
	set_open(not is_open)


func set_open(open: bool) -> void:
	if open == is_open or locked:
		return
	_apply(open)
	ZivaSfx.play(self, SFX_DOOR, 0.05, -10.0)
	if open:
		opened.emit()
		return
	closed.emit()
	if door_kind == "service":
		# Sealing is a one-way job. Leaving the sealed door offering "Open the
		# door" let the guard undo the duty they had just walked.
		_lock_sealed()


## The sealed state of a service door: shut, and it stays that way.
func _lock_sealed() -> void:
	locked = true
	locked_prompt = "Sealed"
	locked_reason = "It is sealed for the night."
	_apply(is_open)


## Clears the condition the door was waiting on, so it can be worked from now on.
func unlock() -> void:
	if not locked:
		return
	locked = false
	locked_reason = ""
	locked_prompt = ""
	_apply(is_open)
	ZivaSfx.play(self, SFX_DOOR, 0.05, -6.0)


## Used when a loaded save says what state the door was left in.
func force_closed() -> void:
	_apply(false, true)
	if door_kind == "service":
		_lock_sealed()


func _on_sensed(body: Node) -> void:
	if locked or is_open or not (body is MallAgent):
		return
	set_open(true)


func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(text)
