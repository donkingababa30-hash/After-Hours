extends Control
## The shift log. Everything the guard has seen, heard and recorded tonight,
## plus the objective and where it is, so they are never left wandering.

@onready var summary: Label = $Panel/Summary
@onready var entries: Label = $Panel/Entries

var _open := false
var _player: Player = null


func _ready() -> void:
	add_to_group("shift_log")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	Game.log_updated.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("log"):
		if _other_screen_open():
			return
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif _open and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


## Only one full screen panel at a time, or the HUD becomes a pile of them.
func _other_screen_open() -> bool:
	var cam := get_tree().get_first_node_in_group("camera_interface")
	if cam != null and cam.visible:
		return true
	var pause := get_tree().get_first_node_in_group("pause_menu")
	if pause != null and pause.visible:
		return true
	var map_screen := get_tree().get_first_node_in_group("map_screen")
	return map_screen != null and map_screen.visible


func open() -> void:
	_open = true
	visible = true
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.can_move = false
	_refresh()


func close() -> void:
	_open = false
	visible = false
	if _player != null and is_instance_valid(_player):
		_player.can_move = true


func _refresh() -> void:
	if not _open:
		return
	var destination := Game.objective_room
	if destination == "":
		destination = "-"
	var evidence := 0
	var manager := get_tree().get_first_node_in_group("encounter_manager")
	if manager != null:
		evidence = manager.logged_anomalies
	summary.text = "TIME        %s\nOBJECTIVE   %s\nDESTINATION %s\nEVIDENCE    %d recorded" % [
		Game.time_text(), Game.current_objective, destination, evidence
	]
	if Game.log_entries.is_empty():
		entries.text = "Nothing recorded yet. Check the duty board in the office."
	else:
		entries.text = "\n".join(Game.log_entries)