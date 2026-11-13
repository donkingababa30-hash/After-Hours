extends Control
## Shown when the player survives until 6:00 AM.


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The evidence counter was decoration until now: this is what it was for.
	($Subtitle as Label).text = \
		"Whatever was here is gone. For now.   Evidence logged: %d." % Game.total_evidence
	$Menu/PlayAgainButton.pressed.connect(_play_again)
	$Menu/MenuButton.pressed.connect(_to_main_menu)
	$Menu/ExitButton.pressed.connect(_quit)
	$Menu/PlayAgainButton.grab_focus()


## A fresh run: back to night 1. Without this the mall reloads on night 3, since
## Game.night is still the night that was just completed.
func _play_again() -> void:
	Game.night = 1
	Game.save_config()
	Game.go_to_mall()


func _to_main_menu() -> void:
	Game.go_to_main_menu()


func _quit() -> void:
	get_tree().quit()