extends Control
## Surveillance-style overlay drawn on top of the LIVE camera feed:
## cool tint, scanlines, a rolling refresh bar, vignette and static.

var noise := 0.0
var time_seconds := 0.0


func configure(noise_level: float) -> void:
	noise = clampf(noise_level, 0.0, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return

	draw_rect(Rect2(0, 0, w, h), Color(0.30, 0.48, 0.76, 0.10))

	var y := 0.0
	while y < h:
		draw_rect(Rect2(0, y, w, 1.0), Color(0, 0, 0, 0.20))
		y += 3.0

	var bar := fmod(time_seconds * 70.0, h + 60.0) - 30.0
	draw_rect(Rect2(0, bar, w, 10.0), Color(1, 1, 1, 0.045))

	draw_rect(Rect2(0, 0, w, 8), Color(0, 0, 0, 0.38))
	draw_rect(Rect2(0, h - 8, w, 8), Color(0, 0, 0, 0.38))
	draw_rect(Rect2(0, 0, 8, h), Color(0, 0, 0, 0.38))
	draw_rect(Rect2(w - 8, 0, 8, h), Color(0, 0, 0, 0.38))

	if noise > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_msec() / 70.0)
		for i in int(noise * 60.0):
			var ny := rng.randf() * h
			draw_line(Vector2(0, ny), Vector2(w, ny), Color(1, 1, 1, rng.randf() * 0.13 * noise), 1.0)

	if noise > 0.35:
		var font := ThemeDB.fallback_font
		var text := "NO SIGNAL"
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, Vector2(w * 0.5 - tw * 0.5, h * 0.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.92, 0.96, 1, 0.85))

	draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.42, 0.5, 0.7), false, 2.0)