extends Node
## Global game state: the night clock, story flags and scene flow.
## Registered as the "Game" autoload.

signal clock_changed(time_text: String)
signal objective_changed(text: String)
signal hour_reached(hour_24: int)
signal night_failed
signal night_completed
signal tutorial_finished
signal log_updated

const CONFIG_PATH := "user://after_hours.cfg"
const SAVE_PATH := "user://after_hours_save.json"
## Bump this whenever the save layout changes. Older files are refused, not read
## half-way and corrupted.
const SAVE_VERSION := 1

const MALL_SCENE := "res://scenes/main/mall.tscn"
const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const GAME_OVER_SCENE := "res://scenes/main/game_over.tscn"
const ENDING_SCENE := "res://scenes/main/ending.tscn"

const START_HOUR := 22          # every night starts at 10:00 PM
const NIGHT_COUNT := 3
## Rounds you may let expire in one night before you are relieved of duty.
const MAX_MISSED_ROUNDS := 3

## Replaced from NightConfig by start_night(): nights get longer and tick faster.
var total_minutes := 240
var seconds_per_minute := 2.0
## Which of the three nights is being played, 1-based.
var night := 1
## Furthest night ever reached, kept between runs for the menu.
var best_night := 0
## Evidence logged across every night survived so far. This is the run's score.
var total_evidence := 0

var elapsed_minutes := 0
var clock_running := false
var flags: Dictionary = {}
var current_objective := ""
var objective_room := ""
## When set, the waypoint arrow aims here instead of the objective room's centre.
var objective_point := Vector2.ZERO
## A live threat, shown UNDER the objective rather than replacing it. An encounter
## used to overwrite the objective outright, which read as "my task just vanished
## and now it is telling me about a room I am not in".
var objective_warning := ""
## Rounds the guard let expire this night. Three and they are relieved of duty.
var missed_rounds := 0
var tutorial_done := false
var tutorial_pending := false
## Newest-first list of timestamped lines shown on the shift log screen.
var log_entries: Array[String] = []

## Set while the mall is rebuilding itself after Continue, so systems can restore
## their own state instead of starting a fresh shift.
var loading_save := false
var loaded_data: Dictionary = {}
var pending_player_position := Vector2.ZERO
var has_pending_position := false

var _accumulator := 0.0
var _last_hour := -1
var _ended := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		tutorial_done = cfg.get_value("progress", "tutorial_done", false)
		best_night = int(cfg.get_value("progress", "best_night", 0))
		total_evidence = int(cfg.get_value("progress", "total_evidence", 0))
		night = clampi(int(cfg.get_value("progress", "night", 1)), 1, NIGHT_COUNT)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
	cfg.set_value("progress", "best_night", best_night)
	cfg.set_value("progress", "night", night)
	cfg.set_value("progress", "total_evidence", total_evidence)
	cfg.save(CONFIG_PATH)


func finish_tutorial() -> void:
	tutorial_pending = false
	tutorial_done = true
	save_config()
	tutorial_finished.emit()


func _process(delta: float) -> void:
	if not clock_running or _ended or get_tree().paused:
		return
	_accumulator += delta
	while _accumulator >= seconds_per_minute:
		_accumulator -= seconds_per_minute
		elapsed_minutes += 1
		_check_hour()
		if elapsed_minutes >= total_minutes:
			_finish_shift()
			return
	clock_changed.emit(time_text())


## Returns the current hour on a 24 hour clock (0 to 23).
func current_hour() -> int:
	return (START_HOUR + int(elapsed_minutes / 60.0)) % 24


func time_text() -> String:
	return time_text_at(elapsed_minutes)


## Formats any minute mark on the same 24 hour clock, so a duty can name the time
## it has to be finished by.
func time_text_at(minute_mark: int) -> String:
	var h24 := (START_HOUR + int(minute_mark / 60.0)) % 24
	var mins := minute_mark % 60
	var suffix := "AM" if h24 < 12 else "PM"
	var h12 := h24 % 12
	if h12 == 0:
		h12 = 12
	return "%02d:%02d %s" % [h12, mins, suffix]


func _check_hour() -> void:
	var h := current_hour()
	if h != _last_hour:
		_last_hour = h
		hour_reached.emit(h)


## Jump the clock forward to the start of the given 24 hour hour.
func skip_to_hour(hour_24: int) -> void:
	var diff := (hour_24 - current_hour() + 24) % 24
	if diff == 0:
		diff = 24
	elapsed_minutes += diff * 60
	_check_hour()
	clock_changed.emit(time_text())


## Adds a timestamped line to the shift log. Newest entries are first.
func add_log_entry(text: String) -> void:
	log_entries.push_front("%s   %s" % [time_text(), text])
	if log_entries.size() > 60:
		log_entries.resize(60)
	log_updated.emit()


## Raises or clears the live-threat line. The objective itself is left alone, so
## the guard keeps their round while something is hunting them.
func set_warning(text: String) -> void:
	objective_warning = text


func set_flag(flag_name: String, value: bool = true) -> void:
	flags[flag_name] = value


func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)


## `point` overrides the room centre for the waypoint arrow. Some objectives are
## a thing standing in a corridor rather than a room, and pointing at the room
## they are nominally "in" sends the guard the wrong way.
func set_objective(text: String, room: String = "", point: Vector2 = Vector2.ZERO) -> void:
	if current_objective == text and objective_room == room and objective_point == point:
		return
	current_objective = text
	objective_room = room
	objective_point = point
	objective_changed.emit(text)


## Returns the night's display title, e.g. "NIGHT 2 - THE ROUNDS".
func night_title() -> String:
	return "NIGHT %d  -  %s" % [night, NightConfig.for_night(night)["subtitle"]]


func night_label() -> String:
	return "NIGHT %d/%d" % [night, NIGHT_COUNT]


## Moves on to the next night. False means the run is over and the ending plays.
func advance_night() -> bool:
	if night >= NIGHT_COUNT:
		return false
	night += 1
	best_night = maxi(best_night, night)
	save_config()
	return true


## Resets the clock for a night. Pass a night number to switch nights.
func start_night(night_number: int = -1) -> void:
	if night_number > 0:
		night = clampi(night_number, 1, NIGHT_COUNT)
	var cfg := NightConfig.for_night(night)
	total_minutes = int(cfg["end_minutes"])
	seconds_per_minute = float(cfg["seconds_per_minute"])
	elapsed_minutes = 0
	_accumulator = 0.0
	_ended = false
	clock_running = true
	flags.clear()
	log_entries.clear()
	missed_rounds = 0
	current_objective = ""
	objective_room = ""
	objective_point = Vector2.ZERO
	objective_warning = ""
	log_updated.emit()
	_last_hour = current_hour()
	clock_changed.emit(time_text())


func fail_night() -> void:
	if _ended:
		return
	_ended = true
	clock_running = false
	night_failed.emit()


func _finish_shift() -> void:
	if _ended:
		return
	_ended = true
	clock_running = false
	night_completed.emit()


func go_to_mall(force_tutorial: bool = false) -> void:
	start_night()
	loading_save = false
	loaded_data = {}
	has_pending_position = false
	tutorial_pending = force_tutorial or not tutorial_done
	get_tree().paused = false
	get_tree().change_scene_to_file(MALL_SCENE)


# --- save / load ----------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Builds the full snapshot. "extra" carries state owned by other systems.
func build_save(player_position: Vector2, extra: Dictionary = {}) -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"clock": time_text(),
		"elapsed_minutes": elapsed_minutes,
		"objective": current_objective,
		"objective_room": objective_room,
		"flags": flags.duplicate(),
		"log": log_entries.duplicate(),
		"tutorial_done": tutorial_done,
		"night": night,
		"player_x": player_position.x,
		"player_y": player_position.y,
	}
	for key in extra:
		data[key] = extra[key]
	return data


func write_save(player_position: Vector2, extra: Dictionary = {}) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open the save file for writing.")
		return false
	file.store_string(JSON.stringify(build_save(player_position, extra), "  "))
	file.close()
	return true


## Returns {} when there is no save, it is unreadable, or it is a version we do
## not understand. A broken file is never deleted.
func read_save() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is not valid JSON. Ignoring it.")
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("Save file version mismatch. Ignoring it.")
		return {}
	return data


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


## Starts a fresh shift with the orientation. Always replaces the old save; the
## main menu asks for confirmation before calling this.
func start_new_game() -> void:
	delete_save()
	night = 1
	tutorial_done = false
	save_config()
	go_to_mall(true)


## Resumes the most recent save. Falls back to a new shift when there is none.
func continue_game() -> bool:
	var data := read_save()
	if data.is_empty():
		go_to_mall(false)
		return false
	apply_save(data)
	return true


func apply_save(data: Dictionary) -> void:
	night = clampi(int(data.get("night", 1)), 1, NIGHT_COUNT)
	start_night(night)
	best_night = maxi(best_night, night)
	loading_save = true
	loaded_data = data
	elapsed_minutes = int(data.get("elapsed_minutes", 0))
	flags.clear()
	var saved_flags: Variant = data.get("flags", {})
	if typeof(saved_flags) == TYPE_DICTIONARY:
		for key in saved_flags:
			flags[str(key)] = bool(saved_flags[key])
	log_entries.clear()
	var saved_log: Variant = data.get("log", [])
	if typeof(saved_log) == TYPE_ARRAY:
		for line in saved_log:
			log_entries.append(str(line))
	tutorial_done = bool(data.get("tutorial_done", tutorial_done))
	tutorial_pending = false
	current_objective = str(data.get("objective", ""))
	objective_room = str(data.get("objective_room", ""))
	var px := float(data.get("player_x", 0.0))
	var py := float(data.get("player_y", 0.0))
	pending_player_position = Vector2(px, py)
	has_pending_position = px > 1.0 and py > 1.0
	_last_hour = current_hour()
	get_tree().paused = false
	clock_changed.emit(time_text())
	objective_changed.emit(current_objective)
	log_updated.emit()
	get_tree().change_scene_to_file(MALL_SCENE)


func go_to_main_menu() -> void:
	clock_running = false
	_ended = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func show_game_over() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_OVER_SCENE)


func show_ending() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(ENDING_SCENE)