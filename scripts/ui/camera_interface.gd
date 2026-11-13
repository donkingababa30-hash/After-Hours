extends CanvasLayer
## The surveillance terminal screen. Shows one camera at a time and can be
## cycled with the arrow keys or the on screen buttons.

signal closed

const SFX_BEEP := preload("res://assets/generated/audio/camera_beep.mp3")

const CAMERAS := [
	{"id": "CAM 01", "name": "MAIN ATRIUM", "pos": Vector2(1040, 750), "zoom": 0.60},
	{"id": "CAM 02", "name": "FASHION HUB", "pos": Vector2(1728, 256), "zoom": 0.60},
	{"id": "CAM 03", "name": "GAME ZONE", "pos": Vector2(1040, 256), "zoom": 0.60},
	{"id": "CAM 04", "name": "FOOD COURT", "pos": Vector2(1040, 1240), "zoom": 0.64},
	{"id": "CAM 05", "name": "SERVICE CORRIDOR", "pos": Vector2(1040, 1496), "zoom": 0.80},
	{"id": "CAM 06", "name": "MAIN ENTRANCE", "pos": Vector2(1024, 1880), "zoom": 0.72},
]

@onready var overlay: Control = $Panel/FeedFrame/Overlay
@onready var feed_viewport: SubViewport = $Panel/FeedFrame/FeedContainer/FeedViewport
@onready var feed_camera: Camera2D = $Panel/FeedFrame/FeedContainer/FeedViewport/FeedCamera
@onready var title_label: Label = $Panel/Title
@onready var location_label: Label = $Panel/Location
@onready var time_label: Label = $Panel/Time
@onready var rec_label: Label = $Panel/Rec

var index := 0
var active := false
var _player: Player = null
var _t := 0.0
var _noise := 0.0


func _ready() -> void:
	add_to_group("camera_interface")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	Game.clock_changed.connect(_on_clock_changed)
	$Panel/PrevButton.pressed.connect(previous)
	$Panel/NextButton.pressed.connect(next)
	$Panel/ExitButton.pressed.connect(close)


func open() -> void:
	active = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.can_move = false
	feed_viewport.world_2d = get_viewport().world_2d
	feed_camera.make_current()
	_set_camera_shy(false)
	_set_camera_only(true)
	ZivaSfx.play(self, SFX_BEEP, 0.05, -9.0)
	_refresh()


func close() -> void:
	if not active:
		return
	active = false
	visible = false
	if _player != null and is_instance_valid(_player):
		_player.can_move = true
	_set_camera_shy(true)
	_set_camera_only(false)
	closed.emit()


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	overlay.time_seconds = _t
	overlay.queue_redraw()


## "Camera shy" things cannot be seen through the security cameras.
func _set_camera_shy(shown: bool) -> void:
	for node in get_tree().get_nodes_in_group("camera_shy"):
		if node is CanvasItem:
			node.visible = shown


## "Camera only" things are never visible in the room, only on the feed.
func _set_camera_only(shown: bool) -> void:
	for node in get_tree().get_nodes_in_group("camera_only"):
		if node is CanvasItem:
			node.visible = shown


func next() -> void:
	index = (index + 1) % CAMERAS.size()
	ZivaSfx.play(self, SFX_BEEP, 0.05, -12.0)
	_refresh()


func previous() -> void:
	index = (index - 1 + CAMERAS.size()) % CAMERAS.size()
	ZivaSfx.play(self, SFX_BEEP, 0.05, -12.0)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		previous()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _on_clock_changed(text: String) -> void:
	if active:
		time_label.text = text


func _refresh() -> void:
	var cam: Dictionary = CAMERAS[index]
	title_label.text = cam["id"]
	location_label.text = cam["name"]
	time_label.text = Game.time_text()
	feed_camera.position = cam["pos"]
	var z: float = cam["zoom"]
	feed_camera.zoom = Vector2(z, z)

	if cam["id"] == "CAM 05":
		Game.set_flag("checked_service_cam")

	_noise = 0.0
	if cam["id"] == "CAM 03" and Game.has_flag("open_store_active"):
		# The Game Zone feed always looks empty, even when something moves.
		_noise = 0.5
		Game.set_flag("checked_gamezone_cam")
	elif Game.current_hour() >= 1 and Game.current_hour() < 6:
		_noise = 0.2

	overlay.configure(_noise)
	rec_label.visible = _noise < 0.35