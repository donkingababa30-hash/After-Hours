extends CanvasLayer
## Live mall map. Press M to open; shows the layout, the player's position
## and a pulsing marker on the current objective.

const FONT := preload("res://assets/ui/fonts/VT323-Regular.ttf")
const SFX_OPEN := preload("res://assets/generated/audio/camera_beep.mp3")

@onready var canvas: Control = $Canvas

var mall: Node2D = null
var player: Node2D = null
var _open := false
var _t := 0.0


func _ready() -> void:
	add_to_group("map_screen")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	canvas.draw.connect(_draw_map)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
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


func open() -> void:
	_open = true
	visible = true
	mall = get_tree().get_first_node_in_group("mall")
	player = get_tree().get_first_node_in_group("player")
	ZivaSfx.play(self, SFX_OPEN, 0.06, -16.0)


func close() -> void:
	_open = false
	visible = false


func _other_screen_open() -> bool:
	var cam := get_tree().get_first_node_in_group("camera_interface")
	if cam != null and cam.visible:
		return true
	var pause := get_tree().get_first_node_in_group("pause_menu")
	if pause != null and pause.visible:
		return true
	var log_screen := get_tree().get_first_node_in_group("shift_log")
	return log_screen != null and log_screen.visible


func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	canvas.queue_redraw()


func _rect(r: Rect2i, xform: Transform2D) -> Rect2:
	var p0 := xform * Vector2(r.position)
	var p1 := xform * Vector2(r.position + r.size)
	return Rect2(p0, p1 - p0)


func _draw_map() -> void:
	var vp := canvas.size
	# Fully opaque: a translucent panel let the HUD show through and the two
# layers of text overlapped each other.
	canvas.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.015, 0.02, 0.035, 1.0))
	canvas.draw_string(FONT, Vector2(34, 30), "RIVERVIEW MALL  //  FLOOR PLAN",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.85, 0.58))

	if mall == null or player == null:
		return

	var tile := float(mall.TILE)
	var map_size := Vector2(mall.MAP_W, mall.MAP_H)
	var area := Rect2(30, 44, vp.x - 60, vp.y - 92)
	var sc: float = minf(area.size.x / map_size.x, area.size.y / map_size.y)
	var origin := area.position + (area.size - map_size * sc) * 0.5
	var xform := Transform2D(0.0, Vector2(sc, sc), 0.0, origin)

	for c in mall.corridors:
		canvas.draw_rect(_rect(c, xform), Color(0.12, 0.145, 0.2, 1.0))
	for d in mall.doorways:
		canvas.draw_rect(_rect(d, xform), Color(0.42, 0.46, 0.55, 1.0))

	for room_name in mall.rooms:
		var r: Rect2i = mall.rooms[room_name]
		var rr := _rect(r, xform)
		canvas.draw_rect(rr, Color(0.17, 0.2, 0.28, 1.0))
		canvas.draw_rect(rr, Color(0.3, 0.36, 0.47, 1.0), false, 1.0)

	# objective highlight
	if Game.objective_room != "" and mall.rooms.has(Game.objective_room):
		var pulse := 0.45 + sin(_t * 4.0) * 0.25
		var orr := _rect(mall.rooms[Game.objective_room], xform)
		canvas.draw_rect(orr.grow(2.0), Color(0.95, 0.82, 0.35, pulse), false, 2.0)
		var oc := orr.get_center()
		canvas.draw_line(oc + Vector2(-6, -6), oc + Vector2(6, 6), Color(0.95, 0.82, 0.35, pulse), 2.0)
		canvas.draw_line(oc + Vector2(6, -6), oc + Vector2(-6, 6), Color(0.95, 0.82, 0.35, pulse), 2.0)

	# room labels
	for room_name in mall.rooms:
		var center: Vector2 = xform * (mall.room_rect_world(room_name).get_center() / tile)
		var label := (room_name as String).to_upper()
		var w := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		canvas.draw_string(FONT, center - Vector2(w * 0.5, -4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.69, 0.79))

	# player marker
	var pp := xform * (player.global_position / tile)
	var blink := 0.6 + sin(_t * 6.0) * 0.4
	canvas.draw_circle(pp, 4.0, Color(0.55, 0.95, 0.6, blink))
	canvas.draw_circle(pp, 1.6, Color(1, 1, 1, 1))
	var aim: Vector2 = player.facing.normalized()
	canvas.draw_line(pp, pp + aim * 12.0, Color(0.55, 0.95, 0.6, blink), 2.0)

	canvas.draw_string(FONT, Vector2(34, vp.y - 24), "M / ESC — CLOSE    ● YOU    ✕ OBJECTIVE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.65, 0.74))