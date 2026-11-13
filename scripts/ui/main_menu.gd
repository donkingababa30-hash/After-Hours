extends Control
## Title screen.

@onready var new_game_button: Button = $Menu/NewGameButton
@onready var continue_button: Button = $Menu/ContinueButton
@onready var tutorial_button: Button = $Menu/TutorialButton
@onready var settings_button: Button = $Menu/SettingsButton
@onready var exit_button: Button = $Menu/ExitButton
@onready var save_note: Label = $Menu/SaveNote
@onready var settings_panel: Panel = $SettingsPanel
@onready var fullscreen_box: CheckBox = $SettingsPanel/Fullscreen
@onready var volume_slider: HSlider = $SettingsPanel/Volume
@onready var close_button: Button = $SettingsPanel/Close
@onready var confirm_panel: Panel = $ConfirmPanel
@onready var confirm_button: Button = $ConfirmPanel/Confirm
@onready var cancel_button: Button = $ConfirmPanel/Cancel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings_panel.visible = false
	confirm_panel.visible = false
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	tutorial_button.pressed.connect(_on_tutorial)
	settings_button.pressed.connect(_toggle_settings)
	exit_button.pressed.connect(_quit)
	confirm_button.pressed.connect(_confirm_new_game)
	cancel_button.pressed.connect(_cancel_new_game)
	close_button.pressed.connect(_toggle_settings)
	fullscreen_box.toggled.connect(_set_fullscreen)
	volume_slider.value_changed.connect(_set_volume)
	fullscreen_box.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	_refresh_save_state()
	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()


## Continue stays dark until there is a save we can actually read.
func _refresh_save_state() -> void:
	var data := Game.read_save()
	var available := not data.is_empty()
	continue_button.disabled = not available
	if available:
		save_note.text = "SAVED SHIFT  %s  -  %s" % [str(data.get("clock", "?")), str(data.get("objective", ""))]
	elif Game.has_save():
		save_note.text = "SAVED SHIFT UNREADABLE"
	else:
		save_note.text = "NO SAVED SHIFT"


func _on_new_game() -> void:
	if Game.has_save():
		confirm_panel.visible = true
		confirm_button.grab_focus()
	else:
		Game.start_new_game()


func _confirm_new_game() -> void:
	confirm_panel.visible = false
	Game.start_new_game()


func _cancel_new_game() -> void:
	confirm_panel.visible = false
	new_game_button.grab_focus()


func _on_continue() -> void:
	Game.continue_game()


func _on_tutorial() -> void:
	Game.go_to_mall(true)


func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible


func _set_fullscreen(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(value, 0.0001, 1.0)))


func _quit() -> void:
	get_tree().quit()