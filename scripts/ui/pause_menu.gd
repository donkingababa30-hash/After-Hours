extends CanvasLayer
## Pause overlay. Freezes the game and offers restart / quit options.

@onready var resume_button: Button = $Menu/ResumeButton
@onready var save_button: Button = $Menu/SaveButton
@onready var save_note: Label = $Menu/SaveNote
@onready var restart_button: Button = $Menu/RestartButton
@onready var menu_button: Button = $Menu/MenuButton
@onready var exit_button: Button = $Menu/ExitButton


func _ready() -> void:
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(resume)
	save_button.pressed.connect(_save_game)
	restart_button.pressed.connect(restart)
	menu_button.pressed.connect(_to_main_menu)
	exit_button.pressed.connect(_quit)


func _save_game() -> void:
	var manager := get_tree().get_first_node_in_group("encounter_manager")
	if manager == null:
		save_note.text = "There is nothing to save yet."
		return
	if manager.is_save_blocked():
		save_note.text = "You cannot save while something is hunting you."
		return
	manager.autosave()
	save_note.text = "Shift progress saved."


func _open_state() -> void:
	var manager := get_tree().get_first_node_in_group("encounter_manager")
	if manager != null and manager.is_save_blocked():
		save_button.disabled = true
		save_note.text = "Saving is blocked during an encounter."
	else:
		save_button.disabled = false
		save_note.text = "Autosaves when a task is completed."


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _camera_is_open():
		return
	if visible:
		resume()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open_state()
	resume_button.grab_focus()


func resume() -> void:
	visible = false
	get_tree().paused = false


func restart() -> void:
	get_tree().paused = false
	Game.go_to_mall()


func _to_main_menu() -> void:
	Game.go_to_main_menu()


func _quit() -> void:
	get_tree().quit()


func _camera_is_open() -> bool:
	var cam := get_tree().get_first_node_in_group("camera_interface")
	return cam != null and cam.visible