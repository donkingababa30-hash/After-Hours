class_name GameHud
extends CanvasLayer
## In-game heads up display: clock, objective, flashlight state, prompts.

@onready var clock_label: Label = $Clock
@onready var objective_label: Label = $ObjectivePanel/ObjectiveText
@onready var objective_marker: Control = $ObjectivePanel/Marker
@onready var objective_where: Label = $ObjectivePanel/ObjectiveWhere
@onready var objective_deadline: Label = $ObjectivePanel/ObjectiveDeadline
@onready var objective_progress: Label = $ObjectivePanel/Progress
@onready var anomalies_label: Label = $StatusPanel/Anomalies
@onready var flash_label: Label = $StatusPanel/Flashlight
@onready var battery_label: Label = $StatusPanel/Battery
@onready var prompt_label: Label = $Prompt
@onready var location_label: Label = $Location
@onready var message_label: Label = $Message
@onready var danger_rect: ColorRect = $Danger
@onready var fade_rect: ColorRect = $Fade
@onready var waypoint: Control = $Waypoint
@onready var vignette: ColorRect = $Vignette
@onready var vitals: Control = $Vitals
@onready var flares_label: Label = $StatusPanel/Flares
@onready var night_label: Label = $StatusPanel/Night
@onready var missed_label: Label = $Missed
@onready var warning_label: Label = $Warning

var _vignette_material: ShaderMaterial = null

var _player: Player = null
var _mall: Node2D = null
var _tutorial: Node = null
var _danger := false
var _danger_time := 0.0
var _location_time := 0.0
var _message_time := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group("hud")
	set_anomalies(0)
	set_missed(0)
	Game.clock_changed.connect(_on_clock_changed)
	Game.objective_changed.connect(_on_objective_changed)
	clock_label.text = Game.time_text()
	_refresh_objective_board()
	prompt_label.text = ""
	location_label.modulate = Color(1, 1, 1, 0)
	message_label.modulate = Color(1, 1, 1, 0)
	danger_rect.color = Color(0.55, 0.05, 0.08, 0.0)
	waypoint.draw.connect(_draw_waypoint)
	objective_marker.draw.connect(_draw_marker)
	vitals.draw.connect(_draw_vitals)
	_vignette_material = vignette.material as ShaderMaterial
	clock_label.text = _clock_text()
	night_label.text = Game.night_title()
	var fade_tween := create_tween()
	fade_tween.tween_property(fade_rect, "color:a", 0.0, 0.7)


func _on_clock_changed(_text: String) -> void:
	clock_label.text = Game.time_text()
	night_label.text = Game.night_title()


func _clock_text() -> String:
	return Game.time_text()


func _on_objective_changed(_text: String) -> void:
	_refresh_objective_board()


## Draws the whole board, and sizes the panel to the lines it actually has.
##
## The objective is four separate fields rather than one sentence: WHAT to do,
## WHERE to go, BY WHEN, and the position in tonight's list. Each gets its own
## line, so nothing has to word-wrap and nothing can run off the edge of the
## panel - which is exactly what the old single run-on string did. The panel is
## also shrunk to fit: a job with no clock on it no longer leaves a dead strip of
## panel hanging over the mall.
func _refresh_objective_board() -> void:
	# Second line of defence: the board never renders with a header and no
	# instruction under it.
	objective_label.text = Game.current_objective if Game.current_objective.strip_edges() != "" else "Walk your rounds."
	objective_where.text = Game.objective_where
	objective_where.visible = Game.objective_where != ""
	objective_deadline.text = Game.objective_deadline
	objective_deadline.visible = Game.objective_deadline != ""
	if Game.objective_steps > 0:
		objective_progress.text = "%d / %d" % [Game.objective_step, Game.objective_steps]
	else:
		objective_progress.text = ""

	var top := 26.0
	top = _stack_line(objective_label, top, 18.0)
	top = _stack_line(objective_where, top, 14.0)
	top = _stack_line(objective_deadline, top, 14.0)
	# offset_top is 8, so the panel's own bottom edge is the stack plus padding.
	$ObjectivePanel.offset_bottom = top + 6.0


## Places one board line at `top` and returns where the next one starts.
##
## The height is MEASURED, not assumed. The instruction line wraps, so a long one
## takes two rows and the lines under it have to move down or they land on top of
## each other. This is also the fix for the instruction running off the panel: a
## Label with autowrap OFF does not clip, it grows its own rect to fit its text and
## escapes whatever panel is drawn behind it - which is how "Complete your
## orientation to begin your shift." ended up half outside the board.
func _stack_line(label: Label, top: float, minimum: float) -> float:
	if not label.visible:
		return top
	var needed := minimum
	var font := label.get_theme_font("font")
	var width := label.offset_right - label.offset_left
	if font != null and width > 0.0:
		var measured: Vector2 = font.get_multiline_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, width, label.get_theme_font_size("font_size"))
		needed = maxf(minimum, measured.y)
	label.offset_top = top
	label.offset_bottom = top + needed
	return top + needed


## Every room now carries a proper world sign (mall.gd._put_sign), so this only
## duplicated it: the big pink HUD glyphs landed directly on top of the sign and
## on the room itself, and the same room name appeared twice on screen. The
## label stays hidden and the method stays so callers keep working.
func show_location(_location_name: String) -> void:
	location_label.visible = false
	_location_time = 0.0


func set_anomalies(count: int) -> void:
	anomalies_label.text = "EVIDENCE %d" % count


## Rounds let expire tonight. Only shown once it matters.
func set_missed(count: int) -> void:
	missed_label.text = "MISSED ROUNDS  %d / %d" % [count, Game.MAX_MISSED_ROUNDS]
	missed_label.visible = count > 0


func show_message(text: String) -> void:
	message_label.text = text
	_message_time = 3.0


func set_danger(on: bool) -> void:
	_danger = on
	if not on:
		_danger_time = 0.0
		danger_rect.color = Color(0.55, 0.05, 0.08, 0.0)


func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player != null:
		var prompt := _player.get_prompt()
		prompt_label.text = ("[E]  " + prompt) if prompt != "" else ""
		flash_label.text = "FLASHLIGHT  ON" if _player.flashlight_on else "FLASHLIGHT  OFF"
		flash_label.modulate = Color(1, 1, 1) if _player.flashlight_on else Color(0.55, 0.58, 0.66)
		battery_label.text = "BATTERY  %d%%" % int(round(_player.battery * 100.0))
		if _player.battery <= 0.0:
			battery_label.modulate = Color(0.92, 0.4, 0.34)
		elif _player.battery < 0.25:
			battery_label.modulate = Color(0.95, 0.68, 0.32)
		else:
			battery_label.modulate = Color(1, 1, 1)
		flares_label.text = "FLARES  %d" % _player.flares
		_update_vignette()
		vitals.queue_redraw()

	_hush_for_tutorial()

	# The live-threat line sits under the objective and never replaces it.
	warning_label.text = Game.objective_warning
	warning_label.visible = Game.objective_warning != ""

	if _location_time > 0.0:
		_location_time -= delta
		location_label.modulate = Color(1, 1, 1, clampf(_location_time, 0.0, 1.0))

	if _message_time > 0.0:
		_message_time -= delta
		message_label.modulate = Color(1, 1, 1, clampf(_message_time, 0.0, 1.0))

	if _danger:
		_danger_time += delta
		var alpha := 0.10 + sin(_danger_time * 5.0) * 0.06
		danger_rect.color = Color(0.55, 0.05, 0.08, alpha)

	prompt_label.modulate = Color(1, 1, 1, 0.78 + sin(_t * 4.0) * 0.22)
	objective_marker.queue_redraw()
	waypoint.queue_redraw()


## The orientation card sits over the same strip of screen as the room banner and
## the message line. During the tutorial those two stand down.
func _hush_for_tutorial() -> void:
	if _tutorial == null or not is_instance_valid(_tutorial):
		_tutorial = get_tree().get_first_node_in_group("tutorial")
	var hushing := false
	if _tutorial != null and _tutorial.has_method("is_active"):
		hushing = bool(_tutorial.call("is_active"))
	location_label.visible = not hushing
	message_label.visible = not hushing


## The view closes in as the guard's nerve goes, and slams shut if something
## is riding on them.
func _update_vignette() -> void:
	if _vignette_material == null or _player == null or not is_instance_valid(_player):
		return
	var stress := clampf(1.0 - _player.composure, 0.0, 1.0)
	var pulse := 0.0
	if _player.latched:
		stress = 1.0
		pulse = 0.5 + sin(_t * 9.0) * 0.5
	else:
		pulse = stress * (0.5 + sin(_t * 1.7) * 0.5)
	_vignette_material.set_shader_parameter("intensity", stress * 0.92)
	_vignette_material.set_shader_parameter("pulse", pulse * 0.6)


## Two bars in the bottom corner: how much running is left, and how much nerve.
func _draw_vitals() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_bar(Vector2(58.0, 1.0), "STAMINA", _player.stamina, _player.stamina_max, Color(0.36, 0.86, 0.46))
	_bar(Vector2(58.0, 23.0), "NERVE", _player.composure, 1.0, Color(0.5, 0.78, 0.95))
	if _player.latched:
		vitals.draw_string(ThemeDB.fallback_font, Vector2(58.0, 44.0), "GET IT OFF",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.32, 0.28))


func _bar(at: Vector2, label: String, value: float, maximum: float, tint: Color) -> void:
	var w := vitals.size.x - at.x - 2.0
	var h := 10.0
	var v := clampf(value / maxf(maximum, 0.001), 0.0, 1.0)
	vitals.draw_string(ThemeDB.fallback_font, Vector2(0.0, at.y + h - 1.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.82, 0.9, 0.9))
	vitals.draw_rect(Rect2(at.x, at.y, w, h), Color(0.04, 0.05, 0.08, 0.75), true)
	# Empty reads as danger; full reads as the bar's own colour.
	var col := Color(0.82, 0.22, 0.2).lerp(tint, v)
	vitals.draw_rect(Rect2(at.x + 1.0, at.y + 1.0, (w - 2.0) * v, h - 2.0), col, true)
	vitals.draw_rect(Rect2(at.x, at.y, w, h), Color(1, 1, 1, 0.16), false, 1.0)


func _draw_marker() -> void:
	var c := objective_marker.size * 0.5
	var pulse := 0.5 + sin(_t * 3.5) * 0.5
	var col := Color(0.95, 0.82, 0.4, 0.55 + pulse * 0.45)
	objective_marker.draw_arc(c, 6.0, 0.0, TAU, 20, Color(0.95, 0.82, 0.4, 0.18), 4.0)
	objective_marker.draw_arc(c, 6.0, 0.0, TAU, 20, col, 1.5)
	objective_marker.draw_circle(c, 2.0, col)


func _draw_waypoint() -> void:
	if _mall == null or not is_instance_valid(_mall):
		_mall = get_tree().get_first_node_in_group("mall")
	if _player == null or not is_instance_valid(_player) or _mall == null:
		return
	var target: Vector2 = _mall.objective_position()
	if target == Vector2.ZERO:
		return
	# An explicit objective point suppresses the arrow when you are already on it.
	if Game.objective_point != Vector2.ZERO:
		if _player.global_position.distance_to(Game.objective_point) < 80.0:
			return
	elif Game.objective_room != "" and _mall.rooms.has(Game.objective_room):
		if _mall.room_rect_world(Game.objective_room).has_point(_player.global_position):
			return

	# Which way to WALK, not which way the target lies.
	#
	# The arrow used to aim straight at the objective, so standing in a shop with
	# the target on the far side of a wall pointed the guard into that wall - the
	# reported "it only points left and sends me at a door I cannot use". It now
	# aims down the first leg of the same A* route the enemies walk, so it follows
	# corridors and doorways because the route does.
	var aim := target
	var route: PackedVector2Array = _mall.find_path(_player.global_position, target)
	for step in route:
		if _player.global_position.distance_to(step) > 56.0:
			aim = step
			break

	var vp := waypoint.size
	# Keep the arrow clear of the objective panel above and the message line below.
	var min_pt := Vector2(34.0, 92.0)
	var max_pt := Vector2(vp.x - 34.0, vp.y - 74.0)
	var center := (min_pt + max_pt) * 0.5
	var half := (max_pt - min_pt) * 0.5
	# get_viewport_transform() hands back WINDOW coordinates (1280x720) because the
	# project upscales a 640x360 viewport. This Control only spans the viewport,
	# so using it doubled every target position and clamped the arrow to the wrong
	# edge, pointing the guard the wrong way. The canvas transform is the right
	# space: world -> the 640x360 viewport this Control actually covers.
	var sp: Vector2 = _player.get_canvas_transform() * target
	var dist: float = _player.global_position.distance_to(target)
	var pulse := 0.55 + sin(_t * 4.0) * 0.45
	var col := Color(0.95, 0.84, 0.42, 0.9)
	var label := "%d m" % int(dist / 32.0)

	if sp.x > min_pt.x and sp.x < max_pt.x and sp.y > min_pt.y and sp.y < max_pt.y:
		waypoint.draw_arc(sp, 11.0, 0.0, TAU, 24, Color(0.95, 0.84, 0.42, 0.18 * pulse), 7.0)
		waypoint.draw_arc(sp, 11.0, 0.0, TAU, 24, col, 2.0)
		_centered_text(waypoint, label, sp + Vector2(0, 22), 14, Color(0.95, 0.9, 0.7, 0.85))
	else:
		# The camera is axis-aligned and unscaled, so a world direction is also the
		# screen direction and the arrow needs no transform to point correctly.
		var dir := aim - _player.global_position
		if dir.length() < 1.0:
			dir = target - _player.global_position
		dir = dir.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var tscale: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var edge: Vector2 = center + dir * tscale
		var a: Vector2 = edge + dir * 11.0
		var b: Vector2 = edge + dir.rotated(2.5) * 11.0
		var c: Vector2 = edge + dir.rotated(-2.5) * 11.0
		waypoint.draw_colored_polygon(PackedVector2Array([a, b, c]), col)
		_centered_text(waypoint, label, edge - dir * 20.0, 14, Color(0.95, 0.9, 0.7, 0.85))


func _centered_text(target: Control, text: String, at: Vector2, size_px: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var origin := at + Vector2(-w * 0.5, 0)
	# The distance label is drawn with a text OUTLINE, never on a backing box. The
	# box was a solid dark rectangle stuck to the middle of the screen - it read as
	# a broken UI element floating over the mall. An outline keeps the digits
	# legible over any floor or sign without hiding what is underneath.
	target.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		size_px, 4, Color(0.02, 0.02, 0.04, 0.9))
	target.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)