extends CanvasLayer
## Animated orientation sequence shown at the start of a new shift.
## Each step waits for the player to actually perform the action.

const FONT := preload("res://assets/ui/fonts/VT323-Regular.ttf")

@onready var canvas: Control = $Canvas

var steps := [
	{"title": "MOVEMENT", "sub": "Use W A S D to walk around the mall.", "keys": ["W", "A", "S", "D"], "mouse": false},
	{"title": "YOUR FLASHLIGHT", "sub": "Aim the beam with the mouse.", "keys": [], "mouse": true},
	{"title": "THE SWITCH", "sub": "Press F to turn your flashlight on or off.", "keys": ["F"], "mouse": false},
	{"title": "INTERACTING", "sub": "Press E whenever an interaction prompt appears.", "keys": ["E"], "mouse": false},
	{"title": "RUNNING", "sub": "Hold SHIFT to run. The bar in the corner drains, and running is loud.", "keys": ["SHIFT"], "mouse": false},
	{"title": "FLARES", "sub": "Press Q to drop one. It lights the room and pulls company off your trail.", "keys": ["Q"], "mouse": false},
	{"title": "THE FLOOR PLAN", "sub": "Press M to open the mall map at any time.", "keys": ["M"], "mouse": false},
	{"title": "THE SHIFT LOG", "sub": "Press L to reread your objective and evidence.", "keys": ["L"], "mouse": false},
	{"title": "PRACTICE  —  THE FIGURE", "sub": "Walk up to it with your light ON. It only moves unwatched.", "keys": ["F"], "mouse": false},
	{"title": "THE CAMERAS", "sub": "Walk to the terminal at your desk and press E.", "keys": ["E"], "mouse": false},
	{"title": "10:00 PM  —  SHIFT START", "sub": "Something in this mall is wrong. Find it.", "keys": [], "mouse": false},
]

var _active := false
var _step := 0
var _t := 0.0
var _step_t := 0.0
var _watch_t := 0.0
var _mouse_moved := false


func _ready() -> void:
	add_to_group("tutorial")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	add_to_group("tutorial")
	canvas.draw.connect(_draw_card)
	_active = Game.tutorial_pending
	visible = _active
	if _active:
		Game.set_objective("Complete your orientation", "", Vector2.ZERO, "Read the briefing card")


func _input(event: InputEvent) -> void:
	if not _active:
		return
	# ESC skips the orientation without opening the pause menu.
	if event.is_action_pressed("pause"):
		_finish()
		get_viewport().set_input_as_handled()
		return
	# While the orientation runs it owns M and L, so the map and the shift log
	# cannot open on top of the card. _process still reads the same actions.
	if event.is_action_pressed("map") or event.is_action_pressed("log"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if absf(m.relative.x) + absf(m.relative.y) > 1.0:
			_mouse_moved = true
	elif event is InputEventMouseButton and event.pressed:
		_mouse_moved = true


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	_step_t += delta
	canvas.queue_redraw()

	match _step:
		0:
			if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.2:
				_advance()
		1:
			if _mouse_moved:
				_advance()
		2:
			if Input.is_action_just_pressed("flashlight"):
				_advance()
		3:
			if Input.is_action_just_pressed("interact"):
				_advance()
		4:
			if Input.is_action_pressed("sprint"):
				_advance()
		5:
			if Input.is_action_just_pressed("flare"):
				_advance()
		6:
			if Input.is_action_just_pressed("map"):
				_advance()
		7:
			if Input.is_action_just_pressed("log"):
				_advance()
		8:
			# Safe practice: get close with the flashlight on and watch it stop.
			var dummy := get_tree().get_first_node_in_group("practice_mannequin")
			var walker := get_tree().get_first_node_in_group("player") as Player
			if dummy != null and walker != null and walker.flashlight_on:
				if walker.global_position.distance_to(dummy.global_position) < 130.0:
					_watch_t += delta
					if _watch_t > 1.2:
						_advance()
				else:
					_watch_t = 0.0
		9:
			if Game.has_flag("used_cameras"):
				_advance()
		10:
			if _step_t > 3.0:
				_finish()


func _advance() -> void:
	_step = mini(_step + 1, steps.size() - 1)
	_step_t = 0.0
	_watch_t = 0.0
	_mouse_moved = false


## True while the orientation owns the screen. The HUD hushes itself so its own
## banners do not fight the card for the same pixels.
func is_active() -> bool:
	return _active


func _finish() -> void:
	_active = false
	visible = false
	Game.finish_tutorial()


func _draw_card() -> void:
	var w := canvas.size.x
	var h := canvas.size.y
	canvas.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.32))

	var slide := 26.0 * (1.0 - clampf(_step_t / 0.30, 0.0, 1.0))
	var alpha := clampf(_step_t / 0.25, 0.0, 1.0)
	# Sits clear of the vitals bars and the interaction prompt underneath.
	var card := Rect2(108.0, h - 220.0 + slide, w - 216.0, 146.0)

	canvas.draw_rect(card, Color(0.035, 0.045, 0.07, 0.94 * alpha))
	canvas.draw_rect(card, Color(0.87, 0.76, 0.42, 0.8 * alpha), false, 2.0)

	var data: Dictionary = steps[_step]

	canvas.draw_string(FONT, card.position + Vector2(18, 32), str(data["title"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.93, 0.82, 0.47, alpha))

	if data["mouse"]:
		_draw_mouse(card.position + Vector2(card.size.x * 0.5, 68.0), alpha)
	else:
		_draw_keys(data["keys"], card.position + Vector2(card.size.x * 0.5, 68.0), alpha)

	# draw_string never wraps, so a long line used to spill straight out through
	# the card's border. draw_multiline_string wraps and centres it inside.
	canvas.draw_multiline_string(FONT, card.position + Vector2(16.0, 102.0), str(data["sub"]),
		HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 32.0, 16, 2,
		Color(0.78, 0.83, 0.9, alpha))

	var skip_text := "ESC  SKIP"
	var skip_w := FONT.get_string_size(skip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	canvas.draw_string(FONT, card.position + Vector2(card.size.x - 20.0 - skip_w, card.size.y - 10.0), skip_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.6, 0.7, alpha))

	# Progress pips run along the bottom, so a long title cannot run into them.
	var pip_x := card.position.x + 18.0
	var pip_y := card.position.y + card.size.y - 17.0
	for i in steps.size():
		var c := Color(0.87, 0.76, 0.42, alpha) if i <= _step else Color(0.28, 0.32, 0.4, alpha)
		canvas.draw_rect(Rect2(pip_x + i * 14.0, pip_y, 9.0, 6.0), c)


func _draw_keys(keys: Array, center: Vector2, alpha: float) -> void:
	if keys.is_empty():
		return
	var height := 32.0
	var gap := 9.0
	# Each cap is sized to its own label, so a word like SHIFT cannot spill out
	# of a box that was built for a single letter.
	var widths: Array[float] = []
	var total := 0.0
	for key in keys:
		var label := str(key)
		var w: float = maxf(34.0, FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 20.0)
		widths.append(w)
		total += w
	total += gap * float(maxi(keys.size() - 1, 0))
	var x := center.x - total * 0.5
	var active := int(_t * 2.5) % keys.size()
	for i in keys.size():
		var lift := -3.0 if i == active else 0.0
		var rect := Rect2(Vector2(x, center.y - height * 0.5 + lift), Vector2(widths[i], height))
		canvas.draw_rect(rect, Color(0.1, 0.115, 0.165, 0.96 * alpha))
		var glow := 0.55 + sin(_t * 6.0) * 0.45 if i == active else 0.0
		canvas.draw_rect(rect, Color(0.87, 0.76, 0.42, (0.35 + glow * 0.6) * alpha), false, 2.0)
		var key := str(keys[i])
		var kw := FONT.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		canvas.draw_string(FONT, rect.position + Vector2(widths[i] * 0.5 - kw * 0.5, height * 0.5 + 7.0), key,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.95, 0.93, 0.85, alpha))
		x += widths[i] + gap


func _draw_mouse(center: Vector2, alpha: float) -> void:
	var body := Rect2(center - Vector2(13, 18), Vector2(26, 36))
	canvas.draw_rect(body, Color(0.1, 0.115, 0.165, 0.96 * alpha))
	canvas.draw_rect(body, Color(0.87, 0.76, 0.42, 0.6 * alpha), false, 2.0)
	canvas.draw_rect(Rect2(center.x - 1.5, center.y - 12.0, 3.0, 8.0),
		Color(0.87, 0.76, 0.42, (0.6 + sin(_t * 6.0) * 0.4) * alpha))

	# rotating flashlight beam
	var a := _t * 1.6
	var dir := Vector2(cos(a), sin(a) * 0.55)
	var tip := center + dir * 34.0
	canvas.draw_line(center, tip, Color(0.95, 0.9, 0.65, 0.5 * alpha), 3.0)
	canvas.draw_circle(tip, 4.0, Color(1, 0.95, 0.75, 0.8 * alpha))
	canvas.draw_arc(tip, 9.0, 0.0, TAU, 16, Color(0.95, 0.9, 0.65, 0.35 * alpha), 2.0)