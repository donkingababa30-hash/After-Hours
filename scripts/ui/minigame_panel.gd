extends Control
## Hands-on repair tasks: match the wires, or bring the breakers into line.
##
## The world does NOT pause while this is open. That is the point - you are
## standing still in the dark with your head down, and something can be walking
## up behind you. Solving it is a relief; getting it wrong is noise and danger.

signal finished(success: bool)

const FONT := preload("res://assets/ui/fonts/VT323-Regular.ttf")
const SFX_PLUG := preload("res://assets/generated/audio/camera_beep.mp3")
const SFX_GOOD := preload("res://assets/generated/audio/anomaly_log.mp3")
const SFX_BAD := preload("res://assets/generated/audio/sting.mp3")

const PANEL := Rect2(150.0, 52.0, 340.0, 256.0)
const WIRE_X := 186.0
const SOCKET_X := 454.0
const ROW_Y := [124.0, 168.0, 212.0, 256.0]
const PLATE := Vector2(40.0, 26.0)

const WIRE_COLORS := [
	Color(0.86, 0.28, 0.26),
	Color(0.32, 0.56, 0.92),
	Color(0.92, 0.8, 0.32),
	Color(0.9, 0.9, 0.94),
]
const WIRE_NAMES := ["RED", "BLUE", "YELLOW", "WHITE"]

const MAX_MISTAKES := 3

## Keypad mode: the code flashes up, then you key it in from memory.
const CODE_LEN := 4
const CODE_REVEAL := 2.6
const MAX_CODE_MISTAKES := 2
const KEY_W := 52.0
const KEY_H := 30.0
const KEY_GAP := 6.0
const KEY_LEFT := 236.0
const KEY_TOP := 172.0

## This script sits on the panel surface itself: _draw only runs on a CanvasItem.
@onready var surface: Control = self

var _active := false
var _kind := "wires"
var _title := ""
var _player: Player = null
var _t := 0.0

var _wire_colors: Array[int] = []
var _socket_colors: Array[int] = []
var _links: Array[int] = []
var _held := -1
var _mistakes := 0
var _shake := 0.0

var _switches: Array[bool] = []
var _target: Array[bool] = []
var _switch_count := 6

var _code: Array[int] = []
var _entered: Array[int] = []
var _reveal_t := 0.0
var _code_mistakes := 0


func _ready() -> void:
	add_to_group("minigame")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	surface.gui_input.connect(_on_surface_input)


func is_open() -> bool:
	return _active


func open(kind: String, title: String) -> void:
	_kind = kind
	_title = title
	_active = true
	visible = true
	_t = 0.0
	_shake = 0.0
	if kind == "breakers":
		_setup_breakers()
	elif kind == "codes":
		_setup_codes()
	else:
		_setup_wires()
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player != null:
		_player.can_move = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	surface.queue_redraw()


func close(success: bool) -> void:
	if not _active:
		return
	_active = false
	visible = false
	_held = -1
	if _player != null and is_instance_valid(_player):
		_player.can_move = true
	finished.emit(success)


func _setup_wires() -> void:
	_wire_colors.clear()
	_socket_colors.clear()
	_links.clear()
	for i in WIRE_COLORS.size():
		_wire_colors.append(i)
		_socket_colors.append(i)
		_links.append(-1)
	_socket_colors.shuffle()
	_held = -1
	_mistakes = 0


func _setup_breakers() -> void:
	_switches.clear()
	_target.clear()
	for i in _switch_count:
		_switches.append(randf() < 0.5)
		_target.append(randf() < 0.5)
	if _switches == _target:
		_switches[0] = not _switches[0]


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("pause"):
		close(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("flashlight"):
		# The torch is unusable with your hands inside the panel.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		surface.queue_redraw()


func _on_surface_input(event: InputEvent) -> void:
	if not _active or not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := button.position
	if _kind == "breakers":
		_click_breakers(point)
	elif _kind == "codes":
		_click_codes(point)
	else:
		_click_wires(point)


# --- wire mode ------------------------------------------------------------

func _click_wires(point: Vector2) -> void:
	for i in _wire_colors.size():
		if _wire_colors[i] < 0:
			continue
		if Rect2(Vector2(WIRE_X, ROW_Y[i]) - PLATE * 0.5, PLATE).has_point(point):
			_held = i
			ZivaSfx.play(self, SFX_PLUG, 0.05, -10.0)
			surface.queue_redraw()
			return
	if _held < 0:
		return
	for j in _socket_colors.size():
		if Rect2(Vector2(SOCKET_X, ROW_Y[j]) - PLATE * 0.5, PLATE).has_point(point):
			_try_link(_held, j)
			return
	_held = -1
	surface.queue_redraw()


func _try_link(wire: int, socket: int) -> void:
	if _links.has(socket):
		pass
	_held = -1
	if _socket_colors[socket] == _wire_colors[wire]:
		_links[wire] = socket
		ZivaSfx.play(self, SFX_PLUG, 0.06, -6.0)
		surface.queue_redraw()
		if _wires_done():
			ZivaSfx.play(self, SFX_GOOD, 0.05, -4.0)
			close(true)
	else:
		_mistakes += 1
		_shake = 0.35
		ZivaSfx.play(self, SFX_BAD, 0.05, -12.0)
		if _mistakes >= MAX_MISTAKES:
			close(false)
	surface.queue_redraw()


func _wires_done() -> bool:
	for link in _links:
		if link < 0:
			return false
	return true


# --- breaker mode ---------------------------------------------------------

func _click_breakers(point: Vector2) -> void:
	for i in _switch_count:
		var rect := Rect2(Vector2(PANEL.position.x + 34.0 + i * 44.0, 190.0), Vector2(34.0, 74.0))
		if rect.has_point(point):
			_switches[i] = not _switches[i]
			ZivaSfx.play(self, SFX_PLUG, 0.05, -9.0)
			surface.queue_redraw()
			if _switches == _target:
				ZivaSfx.play(self, SFX_GOOD, 0.05, -4.0)
				close(true)
			return


# --- keypad mode ----------------------------------------------------------

func _setup_codes() -> void:
	_code.clear()
	_entered.clear()
	for i in CODE_LEN:
		_code.append(randi() % 9 + 1)
	_reveal_t = CODE_REVEAL
	_code_mistakes = 0


func _key_rect(col: int, row: int) -> Rect2:
	return Rect2(
		Vector2(KEY_LEFT + col * (KEY_W + KEY_GAP), KEY_TOP + row * (KEY_H + KEY_GAP)),
		Vector2(KEY_W, KEY_H))


func _click_codes(point: Vector2) -> void:
	for row in 3:
		for col in 3:
			if _key_rect(col, row).has_point(point):
				_press_digit(row * 3 + col + 1)
				return


func _press_digit(digit: int) -> void:
	if _reveal_t > 0.0 or _entered.size() >= CODE_LEN:
		return
	_entered.append(digit)
	var index := _entered.size() - 1
	if _code[index] != digit:
		_code_mistakes += 1
		_shake = 0.35
		_entered.clear()
		# A wrong digit earns one more look at the code.
		_reveal_t = CODE_REVEAL * 0.6
		ZivaSfx.play(self, SFX_BAD, 0.05, -12.0)
		if _code_mistakes >= MAX_CODE_MISTAKES:
			close(false)
		surface.queue_redraw()
		return
	ZivaSfx.play(self, SFX_PLUG, 0.05, -9.0)
	if _entered.size() == CODE_LEN:
		ZivaSfx.play(self, SFX_GOOD, 0.05, -4.0)
		close(true)
	surface.queue_redraw()


# --- drawing --------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	_shake = maxf(0.0, _shake - delta)
	_reveal_t = maxf(0.0, _reveal_t - delta)
	surface.queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var vp := surface.size
	surface.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.01, 0.015, 0.025, 0.72))

	var shake_offset := Vector2.ZERO
	if _shake > 0.0:
		shake_offset = Vector2(sin(_t * 90.0), cos(_t * 74.0)) * 3.0
	var panel := PANEL
	panel.position += shake_offset

	surface.draw_rect(panel, Color(0.055, 0.065, 0.09, 1.0))
	surface.draw_rect(panel, Color(0.5, 0.55, 0.65, 0.9), false, 2.0)
	# A thin header bar so the panel reads as a piece of machinery.
	surface.draw_rect(Rect2(panel.position + Vector2(0, 0), Vector2(panel.size.x, 30.0)),
		Color(0.09, 0.1, 0.14, 1.0))

	_draw_text(_title, panel.position + Vector2(16, 21), 17, Color(0.93, 0.82, 0.47))
	_draw_text("ESC  GIVE UP", panel.position + Vector2(panel.size.x - 96, 21), 13,
		Color(0.55, 0.6, 0.7))

	if _kind == "breakers":
		_draw_breakers(panel)
	elif _kind == "codes":
		_draw_codes(panel)
	else:
		_draw_wires(panel)


func _draw_wires(panel: Rect2) -> void:
	_draw_text("MATCH EACH WIRE TO ITS SOCKET", panel.position + Vector2(16, 52), 14,
		Color(0.78, 0.83, 0.9))

	for i in _wire_colors.size():
		var color: Color = WIRE_COLORS[_wire_colors[i]]
		if _wire_colors[i] < 0:
			color = Color(0.2, 0.22, 0.28)
		var at := Vector2(WIRE_X, ROW_Y[i]) + (panel.position - PANEL.position)
		surface.draw_line(at, at + Vector2(30, 0), color, 5.0)
		surface.draw_rect(Rect2(at + Vector2(-14, -12), Vector2(28, 24)), Color(0.14, 0.16, 0.2, 1))
		surface.draw_rect(Rect2(at + Vector2(-14, -12), Vector2(28, 24)), color, false, 2.0)

	for j in _socket_colors.size():
		var color: Color = WIRE_COLORS[_socket_colors[j]]
		var at := Vector2(SOCKET_X, ROW_Y[j]) + (panel.position - PANEL.position)
		surface.draw_line(at, at - Vector2(30, 0), color, 5.0)
		surface.draw_rect(Rect2(at + Vector2(-13, -12), Vector2(26, 24)), Color(0.14, 0.16, 0.2, 1))
		surface.draw_rect(Rect2(at + Vector2(-13, -12), Vector2(26, 24)), color, false, 2.0)

	# Connected runs sag between the columns.
	for i in _links.size():
		var socket: int = _links[i]
		if socket < 0:
			continue
		var a := Vector2(WIRE_X + 16, ROW_Y[i]) + (panel.position - PANEL.position)
		var b := Vector2(SOCKET_X - 16, ROW_Y[socket]) + (panel.position - PANEL.position)
		_draw_wire_curve(a, b, WIRE_COLORS[_wire_colors[i]])

	if _held >= 0:
		var from := Vector2(WIRE_X + 16, ROW_Y[_held]) + (panel.position - PANEL.position)
		_draw_wire_curve(from, surface.get_local_mouse_position(), WIRE_COLORS[_wire_colors[_held]])

	_draw_text("MISTAKES  %d / %d" % [_mistakes, MAX_MISTAKES],
		panel.position + Vector2(16, panel.size.y - 14), 14,
		Color(0.92, 0.5, 0.45) if _mistakes > 0 else Color(0.6, 0.65, 0.74))


func _draw_wire_curve(a: Vector2, b: Vector2, color: Color) -> void:
	var mid := (a + b) * 0.5 + Vector2(0, 26.0)
	var points := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		points.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	surface.draw_polyline(points, color, 4.0)


func _draw_breakers(panel: Rect2) -> void:
	_draw_text("BRING EVERY BREAKER INTO LINE", panel.position + Vector2(16, 52), 14,
		Color(0.78, 0.83, 0.9))

	var target_x := panel.position.x + 34.0
	for i in _switch_count:
		var x := target_x + i * 44.0
		# Wanted position, shown above the switch.
		var want: Color = Color(0.55, 0.9, 0.6) if _target[i] else Color(0.32, 0.36, 0.44)
		surface.draw_rect(Rect2(Vector2(x, 116.0), Vector2(34.0, 12.0)), want)
		_draw_text("ON" if _target[i] else "OFF", Vector2(x + 7, 110.0), 12,
			Color(0.7, 0.75, 0.84))

		var rect := Rect2(Vector2(x, 190.0), Vector2(34.0, 74.0))
		var ok: bool = _switches[i] == _target[i]
		var body := Color(0.12, 0.14, 0.18, 1)
		surface.draw_rect(rect, body)
		surface.draw_rect(rect, Color(0.55, 0.9, 0.6) if ok else Color(0.5, 0.55, 0.65), false, 2.0)
		var lever := Rect2(Vector2(x + 5.0, 196.0 if _switches[i] else 232.0), Vector2(24.0, 26.0))
		surface.draw_rect(lever, Color(0.75, 0.78, 0.85) if _switches[i] else Color(0.35, 0.38, 0.46))
		_draw_text("ON" if _switches[i] else "OFF", Vector2(x + 4, 288.0), 13,
			Color(0.8, 0.85, 0.92))


func _draw_codes(panel: Rect2) -> void:
	_draw_text("MEMORIZE THE CODE. THEN KEY IT IN.", panel.position + Vector2(16, 52), 13,
		Color(0.78, 0.83, 0.9))

	# One line serves both jobs: the code while it is showing, then your progress.
	var shown := ""
	if _reveal_t > 0.0:
		for digit in _code:
			shown += str(digit)
	else:
		for i in CODE_LEN:
			shown += str(_entered[i]) if i < _entered.size() else "_"
	_centered(shown, Vector2(panel.position.x + panel.size.x * 0.5, 146.0), 26,
		Color(0.98, 0.88, 0.5) if _reveal_t > 0.0 else Color(0.72, 0.8, 0.92))

	for row in 3:
		for col in 3:
			var rect := _key_rect(col, row)
			surface.draw_rect(rect, Color(0.14, 0.16, 0.21, 1))
			surface.draw_rect(rect, Color(0.42, 0.47, 0.58, 0.9), false, 2.0)
			_centered(str(row * 3 + col + 1),
				rect.position + Vector2(rect.size.x * 0.5, 23.0), 20,
				Color(0.88, 0.91, 0.97))

	_draw_text("WRONG ENTRIES  %d / %d" % [_code_mistakes, MAX_CODE_MISTAKES],
		panel.position + Vector2(16, panel.size.y - 16), 13,
		Color(0.92, 0.5, 0.45) if _code_mistakes > 0 else Color(0.6, 0.65, 0.74))


func _centered(text: String, at: Vector2, size_px: int, color: Color) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_draw_text(text, at + Vector2(-width * 0.5, 0), size_px, color)


func _draw_text(text: String, at: Vector2, size_px: int, color: Color) -> void:
	surface.draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)