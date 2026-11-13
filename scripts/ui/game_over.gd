extends Control
## Shown when the player fails an encounter.

const SFX_GAME_OVER := preload("res://assets/generated/audio/game_over.mp3")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ZivaSfx.play(self, SFX_GAME_OVER, 0.0, -5.0)
	# Each night ends at a different hour (2, 3 then 4 AM), so name the right one
	# instead of a hard-coded 6:00 AM.
	($Subtitle as Label).text = "%s never came." % Game.time_text_at(Game.total_minutes)
	$Menu/RetryButton.pressed.connect(_retry)
	$Menu/MenuButton.pressed.connect(_to_main_menu)
	$Menu/RetryButton.grab_focus()


func _retry() -> void:
	Game.go_to_mall()


func _to_main_menu() -> void:
	Game.go_to_main_menu()