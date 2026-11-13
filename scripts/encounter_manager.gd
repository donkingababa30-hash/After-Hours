class_name EncounterManager
extends Node
## Runs the night: patrol objectives, timed anomalies and the three
## paranormal encounters (Mannequin, Open Store, Shadow).

const MANNEQUIN_SCENE := preload("res://scenes/entities/mannequin.tscn")
const SHADOW_SCENE := preload("res://scenes/entities/shadow_entity.tscn")
const SFX_STING := preload("res://assets/generated/audio/sting.mp3")
const SFX_JUMPSCARE := preload("res://assets/generated/audio/jumpscare.mp3")
const SFX_LOG := preload("res://assets/generated/audio/anomaly_log.mp3")
const SFX_PA := preload("res://assets/generated/audio/pa_chime.mp3")

## The mall's colour at 10 PM, and what it has decayed to by 6 AM.
const MODULATE_FULL := Color(0.17, 0.2, 0.29)
const MODULATE_DEEP := Color(0.075, 0.085, 0.14)
const ANOMALY_SCENE := preload("res://scenes/objects/anomaly.tscn")
const TOY_SCENE := preload("res://scenes/entities/haunted_toy.tscn")
const WARDEN_SCENE := preload("res://scenes/entities/warden.tscn")
const TASK_ITEM_SCENE := preload("res://scenes/objects/task_item.tscn")
const WATCH_ITEM_SCENE := preload("res://scenes/objects/watch_item.tscn")

const TILE := 32
const MIDNIGHT_MINUTES := 120
## 360 was longer than an entire night: night 1 runs 240 minutes and night 2 runs
## 300, so the shadow could only ever exist in the last instant of night 3. It was
## fully implemented and effectively unreachable.
const SHADOW_MINUTES := 165
## Game minutes after which the wind-up toys can wake in the east wing, per night.
## They used to need true midnight (120) AND a return trip to the TOYBOX that no
## night's duty board ever asked for, so the Toy Creeper was almost never seen.
const TOY_FROM := [80, 45, 20]

## --- the night watch -------------------------------------------------------
## Real seconds of quiet between incidents, per night. Night 1 is sparse; by
## night 3 the mall barely leaves the guard alone.
const WATCH_GAP := [90.0, 68.0, 50.0]
## Incidents do not begin until the shift is properly under way.
const WATCH_FROM := [70, 40, 26]
## Game minutes an open incident lasts before it is logged against the guard.
const WATCH_DEADLINE := 20
## Incidents run further apart while the duty board still has rounds on it, so
## the guard is never asked to do two jobs at the same time.
const WATCH_DUTY_MULT := 1.7
## ...and closer together once the board is clear and the night has turned.
const WATCH_FINALE_MULT := 0.7

var mall: Node2D
var hud: GameHud
var player: Player
var objects: Node2D
var entities: Node2D

var mannequin: Mannequin = null
var shadow: ShadowEntity = null
var gamezone_lights: Array[PointLight2D] = []

## Each patrol stop is an ANOMALY to hunt down, not just a room to walk into.
##
## `text` is the short instruction for the objective board and `where` its
## location line; `clue` is the full sentence, which is what the guard actually
## writes in the log. Keeping them separate is what stops the board rendering a
## whole paragraph across the top of the screen.
var patrol_stops := [
	{"room": "Main Atrium", "text": "Inspect the spill", "where": "Main Atrium",
		"clue": "Something is dripping in the Main Atrium.",
		"tex": "res://assets/generated/anomaly_stain.png",
		"msg": "A pool of something dark and warm, spread in a shape that is almost a hand.",
		"glow": Color(0.72, 0.08, 0.08),
		"spots": [Vector2i(33, 25), Vector2i(28, 25)]},
	{"room": "Food Court", "text": "Inspect the scraping chair", "where": "Food Court",
		"clue": "A chair is scraping across the Food Court.",
		"tex": "res://assets/generated/anomaly_note.png",
		"msg": "A note in your handwriting: 'IT IS BEHIND YOU WHEN THE LIGHTS FLICKER.'",
		"glow": Color(0.9, 0.86, 0.62),
		"spots": [Vector2i(32, 38), Vector2i(32, 41)]},
	{"room": "Fashion Hub", "text": "Inspect the moving hangers", "where": "Fashion Hub",
		"clue": "Hangers are moving in the Fashion Hub.",
		"tex": "res://assets/generated/anomaly_stain.png",
		"msg": "Blood between the racks, in a trail that leads toward the back wall.",
		"glow": Color(0.72, 0.08, 0.08),
		"spots": [Vector2i(55, 10), Vector2i(50, 11)]},
	{"room": "Game Zone", "text": "Inspect the live cabinet", "where": "Game Zone, arcade",
		"clue": "An arcade cabinet in the Game Zone is still running.",
		"tex": "res://assets/generated/anomaly_eyes.png",
		"msg": "Two points of light at the back of the aisle. They do not blink.",
		"glow": Color(0.45, 0.85, 1.0),
		"spots": [Vector2i(34, 11), Vector2i(35, 9)]},
	{"room": "Storage Room", "text": "Inspect the drag marks", "where": "Storage Room",
		"clue": "A crate has been dragged in the Storage Room.",
		"tex": "res://assets/generated/anomaly_stain.png",
		"msg": "Something was dragged across the concrete. The trail goes under the shelves.",
		"glow": Color(0.72, 0.08, 0.08),
		"spots": [Vector2i(13, 52), Vector2i(13, 55)]},
	{"room": "TOYBOX", "text": "Find the music box", "where": "TOYBOX, east wing",
		"clue": "A music box is playing in the TOYBOX.",
		"tex": "res://assets/generated/anomaly_note.png",
		"msg": "A child's note, in careful capitals: 'DO NOT WIND THEM UP.'",
		"glow": Color(0.88, 0.7, 0.95),
		"spots": [Vector2i(74, 6), Vector2i(83, 8)]},
]

var logged_anomalies := 0
var active_anomaly: Anomaly = null

## This night's duty list, in order, and how far through it the guard is.
var duties: Array = []
var duty_index := 0
## Set while the guard is carrying a haul duty's item back to the office.
var hauling := false
var haul_kind := ""
## Set once every duty is logged. The rest of the night is a hunt, not dead air.
var finale := false
## Game minute the current duty was handed out, so its deadline can be shown.
var duty_started_at := 0
## World position of the object the current duty put in the mall. The waypoint
## aims HERE rather than at the room's centre: a wall-mounted panel, a spawned
## anomaly and the breaker all sit off to one side of their room, so pointing at
## the room sent the guard to an empty patch of floor with nothing to interact
## with - the reported "waypoint but nothing there".
var duty_point := Vector2.ZERO

## Counts real seconds between forced pressure beats. Keeps the mall busy.
var _pressure_t := 0.0

## The open watch incident, if any, and how long it has been open.
var watch_item: Node2D = null
var watch_started_at := 0
var watch_timer := 0.0
## What the guard failed to deal with, written to the log if the round is missed.
var watch_doom := ""
## Seconds the guard has been clear of the mannequin; see _process.
var _mannequin_escape_t := 0.0

var warden: WardenEntity = null
var warden_active := false

var open_store_active := false
var mannequin_active := false
var shadow_active := false
var toy_active := false
var toys: Array[HauntedToy] = []

## The west wing power failure: a hands-on repair task, not a message.
var power_out_active := false
var _failing := false
var _cam_hint_shown := false
var _presence: Node2D = null
var _t := 0.0

## 0 at 10 PM, 1 at 6 AM. Drives the dark and the volume of the mall.
var _dread := 0.0
var _dread_t := 0.0
var _modulate: CanvasModulate = null

# --- mission 1: the open service door -------------------------------------
## Minutes after shift start before the open door turns into a real problem.
## How far the guard must get from the mannequin for the encounter to be over.
const MANNEQUIN_ESCAPE := 470.0
var mission1_active := false
var mission1_briefed := false
var _loader_figure: Node2D = null

## A harmless display figure used by the orientation. It cannot hurt anyone.
var practice_mannequin: Mannequin = null


func setup(mall_ref: Node2D, hud_ref: GameHud, player_ref: Player, objects_ref: Node2D, entities_ref: Node2D) -> void:
	mall = mall_ref
	hud = hud_ref
	player = player_ref
	objects = objects_ref
	entities = entities_ref

	Game.hour_reached.connect(_on_hour_reached)
	Game.night_completed.connect(_on_night_completed)

	Game.tutorial_finished.connect(_on_tutorial_finished)
	_create_gamezone_lights()
	_create_room_triggers()

	var door := get_tree().get_first_node_in_group("service_door")
	if door != null:
		# "closed" rather than "door_closed": the door is a real MallDoor now, and
		# sealing it is a deliberate act the player takes after rerouting the panel
		# beside it - not something that happens during a wire puzzle.
		door.closed.connect(_on_service_door_closed)
	var breaker := get_tree().get_first_node_in_group("breaker")
	if breaker != null:
		breaker.restored.connect(_on_breaker_restored)

	if Game.loading_save:
		_restore_from_save()
	elif Game.tutorial_pending:
		Game.set_objective("Complete your orientation", "", Vector2.ZERO, "Read the briefing card")
		_start_practice()
	else:
		_start_duties()


func _ready() -> void:
	add_to_group("encounter_manager")


## Continue: rebuild the night exactly where the player left it.
func _restore_from_save() -> void:
	logged_anomalies = int(Game.loaded_data.get("evidence", 0))
	hud.set_anomalies(logged_anomalies)
	Game.missed_rounds = int(Game.loaded_data.get("missed", 0))
	hud.set_missed(Game.missed_rounds)
	# This MUST go through _build_duties(), not a raw NightConfig copy. The inspect
	# duties in NightConfig carry only a stop_index; _build_duties() is what copies
	# the clue text and the room across from the anomaly table. Restoring without
	# it left every inspect round with a blank objective, a "Duty:" line with
	# nothing after it in the shift log, and no destination on the board.
	_build_duties()
	duty_index = clampi(int(Game.loaded_data.get("patrol_index", 0)), 0, duties.size())
	# A save taken after the door was sealed must come back sealed. The door is a
	# real solid one now, so restoring it open would leave the guard looking at a
	# duty they had already walked.
	if Game.has_flag("service_door_closed"):
		var sealed_door := get_tree().get_first_node_in_group("service_door")
		if sealed_door != null and sealed_door.has_method("force_closed"):
			sealed_door.call("force_closed")
	if Game.has_flag("warden_active"):
		_start_warden()
	_start_current_duty()
	Game.loading_save = false


func _on_tutorial_finished() -> void:
	_clear_practice()
	_start_duties()


## The orientation's safe dummy: slow, and its catch signal is never connected,
## so the player can learn the mannequin rule without any risk.
func _start_practice() -> void:
	practice_mannequin = MANNEQUIN_SCENE.instantiate()
	practice_mannequin.position = Vector2(37 * TILE + 16, 54 * TILE + 16)
	practice_mannequin.move_speed = 42.0
	practice_mannequin.add_to_group("practice_mannequin")
	practice_mannequin.activate(player)
	entities.add_child.call_deferred(practice_mannequin)


func _clear_practice() -> void:
	if practice_mannequin != null and is_instance_valid(practice_mannequin):
		practice_mannequin.queue_free()
	practice_mannequin = null


func _process(delta: float) -> void:
	_t += delta
	if open_store_active and _presence != null and is_instance_valid(_presence):
		_presence.position = Vector2(32 * TILE, 7 * TILE) + Vector2(cos(_t * 0.9) * 150.0, sin(_t * 1.4) * 95.0)
	if open_store_active and not _cam_hint_shown and Game.has_flag("checked_gamezone_cam"):
		_cam_hint_shown = true
		hud.show_message("CAM 03 shows the Game Zone completely empty. Nothing should be moving in there.")
		Game.set_warning("SOMETHING IS MOVING IN THE GAME ZONE. Do not go in.")

	if mission1_active:
		_tick_service_door()

	# The mannequin is beaten by putting distance between you and it while
	# keeping the beam on it. That works wherever it happens to be standing.
	if mannequin_active and mannequin != null and is_instance_valid(mannequin):
		# The distance has to be HELD, not merely touched. Resolving on a single
		# frame past 470px meant a mannequin that spawned far from the guard was
		# over before it ever appeared on screen.
		if player.global_position.distance_to(mannequin.global_position) > MANNEQUIN_ESCAPE:
			_mannequin_escape_t += delta
			if _mannequin_escape_t > 1.5:
				_mannequin_escape_t = 0.0
				_resolve_mannequin()
		else:
			_mannequin_escape_t = 0.0

	player.in_safe_room = _player_in_safe_room()
	_update_dread(delta)
	_update_director(delta)
	_maybe_start_toy()
	_tick_warden(delta)
	_tick_duty_deadline()
	_tick_watch(delta)


## The first task: what the player sees on the feed changes what they must do.
func _tick_service_door() -> void:
	if not mission1_briefed and Game.has_flag("checked_service_cam"):
		mission1_briefed = true
		hud.show_message("CAM 05: the door is wedged open, and a figure is standing in it.")
		Game.add_log_entry("CAM 05 - service door open. One figure in the doorway.")


## What the tannoy says. It starts as a closing announcement and stops making
## sense long before morning.
var pa_lines := {
	22: "Attention shoppers. Riverview Mall is now closed. Please make your way to the exits.",
	23: "The mall is closed. Please leave the premises.",
	0: "Attention. Attention. Attention.",
	1: "Would the night guard please report to the management office.",
	2: "Thank you for shopping at Riverview.",
	3: "We are open. We are open. We are open.",
	4: "Please do not touch the displays.",
	5: "Is anyone still there.",
}


func _on_hour_reached(hour: int) -> void:
	pa_announce(hour)


## The tannoy keeps talking long after everyone has gone home.
func pa_announce(hour: int) -> void:
	var line: String = pa_lines.get(hour, "")
	if line == "":
		return
	ZivaSfx.play(self, SFX_PA, 0.05, -9.0)
	hud.show_message(line)
	Game.add_log_entry("PA: " + line)


## The mall gets colder and darker hour by hour, and loud enough to notice.
func _update_dread(delta: float) -> void:
	_dread_t += delta
	if _dread_t < 0.4:
		return
	_dread_t = 0.0
	# Each night ramps to full dark by its own end, and starts partly there.
	var progress := clampf(float(Game.elapsed_minutes) / maxf(float(Game.total_minutes), 1.0), 0.0, 1.0)
	var floor_dread := float(NightConfig.for_night(Game.night)["dread_floor"])
	_dread = floor_dread + (1.0 - floor_dread) * progress

	if _modulate == null or not is_instance_valid(_modulate):
		_modulate = mall.get_node_or_null("CanvasModulate") as CanvasModulate
	if _modulate != null:
		var target := MODULATE_FULL.lerp(MODULATE_DEEP, _dread)
		# The office never goes fully dark: it is the one place that feels safe.
		if _player_in_safe_room():
			target = target.lerp(MODULATE_FULL, 0.7)
		_modulate.color = target

	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience is AudioStreamPlayer:
		(ambience as AudioStreamPlayer).volume_db = lerpf(-7.0, -1.0, _dread)


func _player_in_safe_room() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if mall == null or not is_instance_valid(mall):
		return false
	return mall.room_rect_world("Security Office").has_point(player.global_position)


## The clock ran out. Either the next night starts, or the whole run is over.
func _on_night_completed() -> void:
	if _failing:
		return
	_failing = true
	if player != null and is_instance_valid(player):
		player.can_move = false
	var last := Game.night >= Game.NIGHT_COUNT
	# Evidence is the run's score, so it has to survive the night that earned it.
	Game.total_evidence += logged_anomalies
	Game.save_config()
	Game.add_log_entry("Shift complete at " + Game.time_text() + ".")
	hud.show_message("Shift over at %s. %s" % [Game.time_text(),
		"You survived all three nights." if last else "One more night."])
	await get_tree().create_timer(3.2).timeout
	if Game.advance_night():
		Game.go_to_mall(false)
	else:
		Game.show_ending()


# --- triggers -------------------------------------------------------------

func _create_room_triggers() -> void:
	for room_name in mall.rooms:
		_add_trigger(mall.room_rect_world(room_name), room_name)
	var hallway := Rect2(2 * TILE, 30 * TILE, 60 * TILE, 3 * TILE)
	_add_trigger(hallway, "Main Hallway")
	var warning := Rect2(24 * TILE, 14 * TILE, 17 * TILE, 5 * TILE)
	_add_trigger(warning, "Game Zone Front")
	var fashion_front := Rect2(46 * TILE, 14 * TILE, 16 * TILE, 5 * TILE)
	_add_trigger(fashion_front, "Fashion Hub Front")


func _add_trigger(world_rect: Rect2, tag: String) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = world_rect.position + world_rect.size * 0.5
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = world_rect.size
	cs.shape = shape
	area.add_child(cs)
	area.body_entered.connect(_on_trigger_enter.bind(tag))
	area.body_exited.connect(_on_trigger_exit.bind(tag))
	add_child(area)
	return area


func _on_trigger_enter(body: Node, tag: String) -> void:
	if body != player or _failing:
		return

	match tag:
		"Fashion Hub":
			if not mannequin_active and not Game.has_flag("mannequin_done") and Game.elapsed_minutes >= MIDNIGHT_MINUTES:
				_start_mannequin()
		"Game Zone":
			if open_store_active:
				_fail("res://assets/generated/shadow_entity.png", "You walked straight into the Game Zone.")
				return
		"Security Office":
			if hauling:
				var filed := haul_kind
				hauling = false
				_complete_duty("Filed the %s." % filed)
				return
			if shadow_active:
				_resolve_shadow()
				return
		"Main Hallway":
			if not shadow_active and not Game.has_flag("shadow_done") and Game.elapsed_minutes >= SHADOW_MINUTES:
				_start_shadow()
				return
		"Game Zone Front":
			if not open_store_active and not Game.has_flag("open_store_done") and Game.elapsed_minutes >= MIDNIGHT_MINUTES:
				_start_open_store()
				return
		"Fashion Hub Front":
			if not mannequin_active and not Game.has_flag("mannequin_done") and not Game.has_flag("mannequin_warned") and Game.elapsed_minutes >= MIDNIGHT_MINUTES:
				Game.set_flag("mannequin_warned")
				hud.show_message("Ceramic scraping, coming from the Fashion Hub. It stops when you look in.")
				Game.add_log_entry("Fashion Hub - scraping heard. Source not seen.")
				return
		"TOYBOX", "CINEMA":
			var toy_gate := int(TOY_FROM[clampi(Game.night - 1, 0, TOY_FROM.size() - 1)])
			if not toy_active and not Game.has_flag("toy_done") and Game.elapsed_minutes >= toy_gate:
				_start_toy()
				return

	if not Game.tutorial_pending and not _any_encounter() and tag == _duty_room():
		hud.show_message("You are in the right room. Find what does not belong.")


func _on_trigger_exit(body: Node, tag: String) -> void:
	if body != player or _failing:
		return
	if tag == "Fashion Hub" and mannequin_active:
		_resolve_mannequin()
	elif tag == "Game Zone Front" and open_store_active:
		_resolve_open_store()
	elif (tag == "TOYBOX" or tag == "CINEMA") and toy_active:
		_resolve_toy()


# --- encounter 1: the mannequin -------------------------------------------

## The director can let this loose anywhere, so it appears near the guard at a
## spot that is genuinely clear, and the rule is stated without naming a room
## the guard may not be standing in.
func _start_mannequin() -> void:
	mannequin_active = true
	Game.set_flag("mannequin_active", true)
	mannequin = MANNEQUIN_SCENE.instantiate()
	# Never lay a hunter down inside the safe room. One that spawns in the office
	# is standing in the one place it is supposed to be unable to reach, and the
	# guard has to watch it back out of their own room - which reads as the rule
	# being broken even though it can never reach them there.
	var spot := _hunter_spawn_near_player()
	var safe: Rect2 = mall.room_rect_world("Security Office").grow(48.0)
	if safe.has_point(spot):
		spot = Vector2(safe.get_center().x, safe.position.y - 40.0)
	mannequin.position = spot
	mannequin.move_speed = _night_speed(mannequin.move_speed)
	mannequin.activate(player)
	mannequin.caught_player.connect(_on_mannequin_caught)
	# The safe-room exit: it gives up rather than camping the office doorway.
	mannequin.gave_up.connect(_on_mannequin_gave_up)
	entities.add_child.call_deferred(mannequin)
	hud.set_danger(true)
	ZivaSfx.play(self, SFX_STING, 0.05, -7.0)
	# The beam is the counter, so say so: it backs away under the light.
	Game.set_warning("A MANNEQUIN IS MOVING. Hold your beam on it - it backs away.")
	hud.show_message("A mannequin is standing nearby, and it was not a moment ago. Put your light on it and keep it there.")
	Game.add_log_entry("A display mannequin is standing where it should not be.")


## True when nothing solid is standing at this spot. A hunter that spawns inside
## a shop display spends the rest of the night grinding against it.
func _spot_is_free(point: Vector2, radius: float = 18.0) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## A clear spot at a fair distance from the guard: near enough to be a real
## threat, far enough that it does not simply appear in their lap.
func _hunter_spawn_near_player(min_dist: float = 260.0, max_dist: float = 520.0) -> Vector2:
	if player == null or not is_instance_valid(player):
		return _shadow_spawn_point()
	var origin: Vector2 = player.global_position
	for i in 28:
		var candidate: Vector2 = origin + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(min_dist, max_dist)
		if _spot_is_free(candidate):
			return candidate
	return _shadow_spawn_point()


func _resolve_mannequin() -> void:
	mannequin_active = false
	Game.set_flag("mannequin_active", false)
	Game.set_flag("mannequin_done", true)
	if mannequin != null:
		mannequin.deactivate()
	hud.set_danger(false)
	Game.set_warning("")
	hud.show_message("You put the rack between you and it. It stops following.")
	_refresh_objective()
	autosave()


func _on_mannequin_caught() -> void:
	_fail("res://assets/generated/mannequin.png", "The mannequin reached you.")


## It gave up at the office threshold. Same cleanup as every other exit route, so
## the encounter cannot be left half-resolved with the thing still on the board.
func _on_mannequin_gave_up() -> void:
	if not mannequin_active:
		return
	_resolve_mannequin()
	hud.show_message("It does not follow you in. It stands in the corridor, and then it is gone.")


# --- encounter 2: the open store ------------------------------------------

func _start_open_store() -> void:
	open_store_active = true
	_cam_hint_shown = false
	Game.set_flag("open_store_active", true)
	for light in gamezone_lights:
		light.enabled = true
	_spawn_presence()
	hud.set_danger(true)
	ZivaSfx.play(self, SFX_STING, 0.05, -7.0)
	Game.set_warning("SOMETHING IS MOVING IN THE GAME ZONE. Do not go in.")
	hud.show_message("The Game Zone lights flicker on. Something is moving between the shelves.")


## Something that only exists in the room - never on the security feed.
func _spawn_presence() -> void:
	_presence = Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/generated/shadow_entity.png")
	spr.modulate = Color(0.8, 0.8, 0.9)
	_presence.add_child(spr)
	_presence.position = Vector2(32 * TILE, 7 * TILE)
	_presence.add_to_group("camera_shy")
	entities.add_child.call_deferred(_presence)


func _resolve_open_store() -> void:
	open_store_active = false
	Game.set_flag("open_store_active", false)
	Game.set_flag("open_store_done", true)
	for light in gamezone_lights:
		light.enabled = false
	if _presence != null and is_instance_valid(_presence):
		_presence.queue_free()
		_presence = null
	hud.set_danger(false)
	Game.set_warning("")
	hud.show_message("Behind you the Game Zone goes dark. Whatever was in there is still in there.")
	_refresh_objective()
	autosave()


# --- encounter 3: the shadow ----------------------------------------------

func _start_shadow() -> void:
	shadow_active = true
	Game.set_flag("shadow_active", true)
	shadow = SHADOW_SCENE.instantiate()
	shadow.position = _shadow_spawn_point()
	shadow.chase_speed = _night_speed(shadow.chase_speed)
	shadow.patrol_speed = _night_speed(shadow.patrol_speed)
	shadow.activate(player)
	shadow.caught_player.connect(_on_shadow_caught)
	entities.add_child.call_deferred(shadow)
	_dim_lights(true)
	hud.set_danger(true)
	ZivaSfx.play(self, SFX_STING, 0.05, -7.0)
	# Say the rule, not the mood. Players were dying to this without ever working
	# out that the light is what feeds it, or that a flare is an escape.
	Game.set_warning("TURN YOUR TORCH OFF. It hunts the light. Walk to the office.")
	hud.show_message("It charges at torchlight. Kill your light and it loses you - and a flare pulls it off your trail completely.")


## A point in a corridor lane that is guaranteed to be on walkable floor.
##
## The old code clamped x to the map edge (MAP_W*TILE-96 = 2720), but the corridor
## only reaches x about 2551 - so a hunter released from the far east was dropped
## inside solid wall and ground against it for the rest of the night. This walks
## the lane until it finds real floor instead of trusting a number.
func _lane_point(lane_y: float, want_x: float) -> Vector2:
	var edge := float(mall.MAP_W * TILE) - 96.0
	var x := clampf(want_x, 96.0, edge)
	if mall.is_walkable(Vector2(x, lane_y)):
		return Vector2(x, lane_y)
	for i in 40:
		var left := clampf(x - 32.0 * float(i), 96.0, edge)
		if mall.is_walkable(Vector2(left, lane_y)):
			return Vector2(left, lane_y)
		var right := clampf(x + 32.0 * float(i), 96.0, edge)
		if mall.is_walkable(Vector2(right, lane_y)):
			return Vector2(right, lane_y)
	return Vector2(1024.0, lane_y)


## Drops the shadow into the corridor lane nearest the player, a good distance
## away, on floor that actually exists.
func _shadow_spawn_point() -> Vector2:
	var px: float = player.global_position.x
	var py: float = player.global_position.y
	var lanes := [528.0, 1008.0, 1488.0]
	var lane: float = lanes[0]
	for candidate in lanes:
		if absf(candidate - py) < absf(lane - py):
			lane = candidate
	var dir := -1.0 if px > 1024.0 else 1.0
	return _lane_point(lane, px + dir * 460.0)


func _resolve_shadow() -> void:
	shadow_active = false
	Game.set_flag("shadow_active", false)
	Game.set_flag("shadow_done", true)
	if shadow != null:
		shadow.deactivate()
	_dim_lights(false)
	hud.set_danger(false)
	Game.set_warning("")
	hud.show_message("You shut the office door behind you. The footsteps stop.")
	_refresh_objective()
	autosave()


func _on_shadow_caught() -> void:
	_fail("res://assets/generated/shadow_entity.png", "The shadow caught up with you.")


# --- mission 1: the open service door -------------------------------------

# --- the power failure: a hands-on repair ---------------------------------

## 2 AM. The west wing drops out. There is a way to fix it, and it is hands-on.
func _start_power_out() -> void:
	power_out_active = true
	duty_point = _breaker_position()
	_dim_lights(true)
	hud.show_message("Every light in the west wing dies at once.")
	Game.add_log_entry("Power lost in the west wing.")
	ZivaSfx.play(self, SFX_STING, 0.05, -12.0)


## The breaker is a fixed fitting on the Storage Room wall, so its own position is
## the objective point - the room's centre is a different place entirely.
func _breaker_position() -> Vector2:
	var breaker := get_tree().get_first_node_in_group("breaker") as Node2D
	if breaker == null:
		return Vector2.ZERO
	return breaker.global_position


func _on_breaker_restored() -> void:
	if not power_out_active:
		return
	power_out_active = false
	_dim_lights(false)
	hud.show_message("The breakers bite, and light crawls back down the corridor.")
	_complete_duty("Breaker reset. West wing power restored.")


## A mis-wired door panel costs real minutes off the deadline.
func on_door_fumbled() -> void:
	if not mission1_active:
		return
	Game.elapsed_minutes += 10
	Game.add_log_entry("Fumbled the door panel. Ten minutes lost.")
	hud.show_message("Sparks, and ten minutes off the clock.")


# --- encounter 4: the haunted toys ----------------------------------------

## The TOYBOX is the far end of the east wing, and it is the one place where
## carrying a burning torch is what gets you killed.
func _start_toy() -> void:
	toy_active = true
	Game.set_flag("toy_active", true)
	toys.clear()
	# Spawn in the east wing near the guard rather than at three fixed TOYBOX cells.
	# Fixed cells meant that if the guard was in the CINEMA (the other east-wing
	# room, a wall away) the toys woke in a room the guard was not in and could not
	# reach them - so the encounter could pass entirely unseen. Spawning nearby
	# guarantees the encounter actually happens wherever in the east wing they are.
	for i in 2:
		var haunted := TOY_SCENE.instantiate()
		var spot := _hunter_spawn_near_player(300.0, 520.0)
		haunted.position = spot
		haunted.set_home(spot)
		haunted.wake_delay = 2.5
		haunted.hunt_speed = _night_speed(haunted.hunt_speed)
		haunted.activate(player)
		haunted.caught_player.connect(_on_toy_caught)
		entities.add_child.call_deferred(haunted)
		toys.append(haunted)
	Game.set_flag("toy_warned")
	hud.set_danger(true)
	ZivaSfx.play(self, SFX_STING, 0.05, -7.0)
	Game.set_warning("THE TOYS ARE AWAKE. They come toward torchlight.")
	hud.show_message("Something small is winding up between the shelves. They come toward the light.")
	Game.add_log_entry("TOYBOX - a wind-up toy is walking on its own.")


## The toy gate, checked EVERY FRAME rather than only on the room-entry edge.
##
## It used to fire only when the guard walked through a TOYBOX/CINEMA door after
## the minute mark. A guard who was restored into the east wing by a save, or who
## was simply already standing in the room when the minute ticked over, never
## generated an entry event at all - so the whole encounter was silently skipped
## for that night, which is exactly how a player finishes three shifts without
## ever seeing the Toy Creeper.
func _maybe_start_toy() -> void:
	if toy_active or Game.has_flag("toy_done"):
		return
	var gate := int(TOY_FROM[clampi(Game.night - 1, 0, TOY_FROM.size() - 1)])
	if Game.elapsed_minutes < gate:
		return
	var room := _room_at_player()
	if room == "TOYBOX" or room == "CINEMA":
		_start_toy()


## The name of the room the guard is standing in, or "" for a corridor.
func _room_at_player() -> String:
	if player == null or not is_instance_valid(player) or mall == null:
		return ""
	for room_name in mall.rooms:
		if mall.room_rect_world(room_name).has_point(player.global_position):
			return room_name
	return ""


func _resolve_toy() -> void:
	toy_active = false
	Game.set_flag("toy_active", false)
	Game.set_flag("toy_done", true)
	for haunted in toys:
		if is_instance_valid(haunted):
			haunted.deactivate()
	toys.clear()
	hud.set_danger(false)
	Game.set_warning("")
	hud.show_message("You leave the toys winding down behind you.")
	_refresh_objective()
	autosave()


func _on_toy_caught() -> void:
	_fail("res://assets/generated/toy_creeper.png", "The toy caught you at ankle height.")


## Starts the shift. The east wing is dark until the service door is sealed.
func _start_service_door_mission() -> void:
	mission1_active = true
	mission1_briefed = false
	_dim_lights(true)
	_spawn_loader_figure()
	hud.show_message("The east wing lights drop out. Something is at the service door.")
	Game.add_log_entry("Shift start. East service door alarm tripped.")


func _on_service_door_closed() -> void:
	if not mission1_active:
		return
	mission1_active = false
	Game.set_flag("service_door_closed")
	_dim_lights(false)
	_clear_loader_figure()
	hud.show_message("The bolt catches. The east wing lights hum back up.")
	_complete_duty("Service door sealed. East wing power restored.")


## Ignoring the first task costs the player light and lets something inside.
func _service_door_missed() -> void:
	mission1_active = false
	Game.set_flag("service_door_missed")
	_clear_loader_figure()
	Game.add_log_entry("Service door left open. Something got in.")
	hud.show_message("Too late. The service door is still open, and something came through it.")
	# The night carries on without the duty - and with whatever came in. A failure
	# is not evidence, so nothing is banked for it.
	_complete_duty("")
	if not shadow_active and not Game.has_flag("shadow_done"):
		_start_shadow()


## A figure that exists only on the security feed.
func _spawn_loader_figure() -> void:
	if _loader_figure != null and is_instance_valid(_loader_figure):
		return
	_loader_figure = Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/generated/shadow_entity.png")
	spr.modulate = Color(0.55, 0.6, 0.7)
	spr.scale = Vector2(0.9, 0.9)
	_loader_figure.add_child(spr)
	_loader_figure.position = Vector2(34 * TILE + 16, 46 * TILE + 16)
	_loader_figure.add_to_group("camera_only")
	_loader_figure.visible = false
	entities.add_child.call_deferred(_loader_figure)


func _clear_loader_figure() -> void:
	if _loader_figure != null and is_instance_valid(_loader_figure):
		_loader_figure.queue_free()
	_loader_figure = null


## True while something is hunting the player; saving is refused then, because a
## reload would drop them into the middle of it.
func is_save_blocked() -> bool:
	return _any_encounter() or _failing


## Writes the shift to disk so Continue can resume it.
func autosave() -> void:
	if player == null or not is_instance_valid(player) or is_save_blocked():
		return
	Game.write_save(player.global_position, {
		"evidence": logged_anomalies,
		"patrol_index": duty_index,
		"missed": Game.missed_rounds,
	})


## Records a piece of evidence and writes it to the shift log.
func add_evidence(label: String) -> void:
	logged_anomalies += 1
	hud.set_anomalies(logged_anomalies)
	if label != "":
		Game.add_log_entry(label)


# --- helpers --------------------------------------------------------------

func _refresh_objective() -> void:
	# An open incident owns the board while it stands: it is the one job on the
	# shift with a clock actively running against it. The duty it interrupted
	# comes straight back the moment the round is walked.
	if _watch_open():
		return
	# Finishing the list does NOT end the night - it starts the worst part of it.
	if _current_duty().is_empty():
		if not finale:
			_start_finale()
			return
		if not _any_encounter():
			_finale_objective()
		return
	if _any_encounter():
		return
	if hauling:
		Game.set_objective("Carry the %s back" % haul_kind, "Security Office", Vector2.ZERO,
			"Security Office", "", duty_index + 1, duties.size())
		return
	var duty := _current_duty()
	# Name the time the round has to be walked by, so the deadline is legible.
	var limit := int(NightConfig.for_night(Game.night)["duty_deadline"])
	# Aim at the thing itself, wherever the duty spawned it, and fall back to the
	# door for the door duty (which stands in a corridor, not in a room).
	var point := duty_point
	if str(duty["kind"]) == "door":
		point = _door_position()
	# Four separate fields rather than one sentence: what to do, where to go, by
	# when, and how far through tonight's list. The board draws each on its own
	# line, so nothing has to wrap and nothing can run off the panel.
	Game.set_objective(str(duty.get("text", "")), str(duty.get("room", "")), point,
		str(duty.get("where", "")), "by " + Game.time_text_at(duty_started_at + limit),
		duty_index + 1, duties.size())


## Where the service door actually is. It stands in the corridor, not in Storage,
## so pointing the arrow at a room name sent the guard the wrong way.
func _door_position() -> Vector2:
	var door := get_tree().get_first_node_in_group("service_door") as Node2D
	if door == null:
		return Vector2(1040.0, 1448.0)
	return door.global_position


# --- duty deadlines: the teeth behind the list ----------------------------
# Sitting in the office and letting the night pass is a way to LOSE. Every round
# has a window; miss three and management pulls you off the shift.

func _tick_duty_deadline() -> void:
	if _failing or finale or _any_encounter():
		return
	if _current_duty().is_empty():
		return
	var limit := int(NightConfig.for_night(Game.night)["duty_deadline"])
	if Game.elapsed_minutes - duty_started_at < limit:
		return
	_duty_expired()


func _duty_expired() -> void:
	var duty := _current_duty()
	if duty.is_empty():
		return
	Game.missed_rounds += 1
	hud.set_missed(Game.missed_rounds)
	Game.add_log_entry("MISSED ROUND: " + str(duty.get("detail", duty.get("text", ""))))
	ZivaSfx.play(self, SFX_STING, 0.05, -5.0)
	if Game.missed_rounds >= Game.MAX_MISSED_ROUNDS:
		_dereliction()
		return
	if str(duty["kind"]) == "door":
		# Losing the first job lets something in as well as costing a strike.
		_service_door_missed()
		return
	hud.show_message("That round went unwalked. Management has logged it.")
	# Word gets around: something is let loose on the strength of it.
	_release_hunter()
	duty_index += 1
	_start_current_duty()
	autosave()


## Three missed rounds and the shift is over, however alive you still are.
func _dereliction() -> void:
	if _failing:
		return
	_failing = true
	if player != null and is_instance_valid(player):
		player.can_move = false
		player.latched = false
	hud.set_danger(false)
	hud.show_message("Three rounds missed. You are relieved of duty.")
	Game.add_log_entry("Relieved of duty for neglect.")
	Game.fail_night()
	await get_tree().create_timer(3.0).timeout
	Game.show_game_over()


## Every duty is logged. Rather than let the shift go quiet, the mall finishes it
## for you: the lights drop and it comes looking. However fast the guard cleared
## the list, the night still has teeth.
func _start_finale() -> void:
	finale = true
	_dim_lights(true)
	_finale_objective()
	hud.show_message("That was the last of it. Something in here knows you are finished.")
	Game.add_log_entry("All duties logged. The west wing lights go out.")
	ZivaSfx.play(self, SFX_STING, 0.05, -6.0)
	_release_hunter()


func _finale_objective() -> void:
	# The last stretch has a real destination rather than a mood: the office is
	# the one room nothing will follow you into, so the arrow points there.
	Game.set_objective("Survive to the end of your shift", "Security Office", Vector2.ZERO,
		"Get back to the Security Office", "", 0, 0)


# --- the night watch ------------------------------------------------------
# Clearing the duty board does not end the shift, it changes it. From then until
# dawn the guard is doing the actual job - watching the mall - and the mall keeps
# handing them something to watch. A round left unwalked costs a missed round
# exactly like a missed duty, so the security office stays safe from the things
# that chase you and is never safe from the work itself. That was the hole: a
# guard who cleared the list could sit in the office until morning and nothing
# anywhere in the game objected.

## Everything that can be wrong tonight. Each entry has the same shape: somewhere,
## a thing, the words on the prompt, what the guard writes afterwards, and what
## goes in the log if nobody ever goes.
const WATCH_KINDS := [
	{"room": "Techworld", "tex": "prop_shutter",
		"text": "Close the open shutter", "where": "Techworld",
		"clue": "A store shutter is up in Techworld.",
		"prompt": "Pull the shutter down",
		"done": "The shutter was up. Nothing inside, but the till drawer was open.",
		"doom": "That shutter stood open all night."},
	{"room": "Beauty Co.", "tex": "prop_breaker",
		"text": "Cut the Beauty Co. lights", "where": "Beauty Co.",
		"clue": "The Beauty Co. lights are on after closing.",
		"prompt": "Cut the circuit",
		"done": "The lights cut. The mirrors stayed lit a moment longer than the ceiling did.",
		"doom": "Beauty Co. burned its lights until dawn."},
	{"room": "Food Court", "tex": "anomaly_note",
		"text": "Confirm the scraping chair", "where": "Food Court",
		"clue": "A chair is scraping across the Food Court.",
		"prompt": "Confirm the report",
		"done": "One chair, pushed back from a table laid for two.",
		"doom": "Nobody walked the Food Court."},
	{"room": "Storage Room", "tex": "prop_crate",
		"text": "Check the moved crate", "where": "Storage Room",
		"clue": "A crate has moved in Storage.",
		"prompt": "Check the crate",
		"done": "Open and empty. The manifest says it was never filled.",
		"doom": "The crate in Storage was left standing open."},
	{"room": "Restrooms", "tex": "prop_wastebin",
		"text": "Shut off the running water", "where": "Restrooms",
		"clue": "Water is running in the Restrooms.",
		"prompt": "Shut the water off",
		"done": "Every tap was running. One of them stopped when you touched it.",
		"doom": "The restrooms ran all night."},
	{"room": "TOYBOX", "tex": "prop_rockinghorse",
		"text": "Wind down the music box", "where": "TOYBOX, east wing",
		"clue": "A music box is playing in the TOYBOX.",
		"prompt": "Wind it down",
		"done": "It ran down. It was still warm.",
		"doom": "The TOYBOX played to an empty wing."},
	{"room": "CINEMA", "tex": "prop_dollhouse",
		"text": "Kill the running projector", "where": "CINEMA, east wing",
		"clue": "The CINEMA projector is running to an empty screen.",
		"prompt": "Kill the projector",
		"done": "Still running. The reel was never threaded.",
		"doom": "The CINEMA showed its film to nobody."},
	# Not every report sends the guard away from the office. One of them is the
	# desk itself, which is what makes the cameras worth walking back for.
	{"room": "Security Office", "tex": "terminal",
		"text": "Review the camera log", "where": "Security Office, your desk",
		"clue": "The camera server has logged a fault. Review the feed.",
		"prompt": "Review the camera log",
		"done": "Four minutes of the west wing corridor are missing from the recording.",
		"doom": "Nobody reviewed the camera log."},
]


func _watch_open() -> bool:
	return watch_item != null and is_instance_valid(watch_item)


func _tick_watch(delta: float) -> void:
	if _failing or Game.tutorial_pending:
		return
	var night := clampi(Game.night - 1, 0, WATCH_FROM.size() - 1)
	if Game.elapsed_minutes < int(WATCH_FROM[night]):
		return
	if _watch_open():
		# Open incident: the only question is whether the guard got there.
		if Game.elapsed_minutes - watch_started_at >= WATCH_DEADLINE:
			_watch_expired()
		return
	# Never lay a fresh incident on top of something already hunting the guard.
	# The night should be varied, not a pile-up.
	if _any_encounter():
		return
	watch_timer -= delta
	if watch_timer > 0.0:
		return
	_start_watch()


func _start_watch() -> void:
	var entry: Dictionary = WATCH_KINDS[randi() % WATCH_KINDS.size()]
	var room := str(entry["room"])
	if not mall.rooms.has(room):
		return
	watch_doom = str(entry["doom"])
	var spot := _clear_spot(_duty_spot(room, Vector2.ZERO))
	var item := WATCH_ITEM_SCENE.instantiate()
	item.position = spot
	item.setup("res://assets/generated/%s.png" % entry["tex"],
		str(entry["prompt"]), str(entry["done"]))
	item.resolved.connect(_on_watch_resolved)
	objects.add_child(item)
	watch_item = item
	watch_started_at = Game.elapsed_minutes
	Game.set_objective(str(entry["text"]), room, spot, str(entry.get("where", room)),
		"by " + Game.time_text_at(watch_started_at + WATCH_DEADLINE), 0, 0)
	hud.show_message(str(entry["clue"]))
	Game.add_log_entry("Report: " + str(entry["clue"]))
	ZivaSfx.play(self, SFX_STING, 0.05, -15.0)
	_arm_watch_timer()


## Rest between incidents. Longer while the board still has rounds on it, shorter
## once it is clear and the mall has the guard to itself.
func _arm_watch_timer() -> void:
	var night := clampi(Game.night - 1, 0, WATCH_GAP.size() - 1)
	var gap := float(WATCH_GAP[night])
	if not _current_duty().is_empty():
		gap *= WATCH_DUTY_MULT
	elif finale:
		gap *= WATCH_FINALE_MULT
	watch_timer = gap


func _on_watch_resolved() -> void:
	watch_item = null
	watch_doom = ""
	add_evidence("Logged a round: the mall was walked.")
	hud.show_message("Round logged. Evidence is mounting.")
	_arm_watch_timer()
	_refresh_objective()
	autosave()


## The round went unwalked. Same teeth as a missed duty, and for the same reason:
## the office is allowed to be safe, but it is not allowed to be idle.
func _watch_expired() -> void:
	if _watch_open():
		watch_item.queue_free()
	watch_item = null
	Game.missed_rounds += 1
	hud.set_missed(Game.missed_rounds)
	Game.add_log_entry("MISSED ROUND: " + watch_doom)
	ZivaSfx.play(self, SFX_STING, 0.05, -6.0)
	watch_doom = ""
	if Game.missed_rounds >= Game.MAX_MISSED_ROUNDS:
		_dereliction()
		return
	hud.show_message("That report went unwalked. Management has logged it.")
	_release_hunter()
	_arm_watch_timer()
	_refresh_objective()
	autosave()


# --- the duty board -------------------------------------------------------
# A night is an ordered list of duties from NightConfig. The board spawns what
# each one needs, points the guard at it, then moves on. A list that never
# repeats is what stops the shift feeling like the same errand forever.

## A nudge so a spawned task never lands on the room's own permanent fixture.
const DUTY_NUDGE := {
	"Security Office": Vector2(0.0, 58.0),
	"Storage Room": Vector2(0.0, 40.0),
}


func _start_duties() -> void:
	_build_duties()
	duty_index = 0
	_start_current_duty()


## Inspect duties inherit their clue straight from the anomaly table, so the two
## can never drift apart.
func _build_duties() -> void:
	duties = NightConfig.for_night(Game.night)["duties"].duplicate(true)
	for duty in duties:
		if str(duty["kind"]) == "inspect":
			var stop: Dictionary = patrol_stops[int(duty["stop_index"])]
			# Short instruction and location for the board, full sentence for the
			# log. The clue used to be written straight into `text`, which is why
			# an inspect round put a whole sentence on the board.
			duty["text"] = stop["text"]
			duty["where"] = stop["where"]
			duty["detail"] = stop["clue"]
			duty["room"] = stop["room"]


func _current_duty() -> Dictionary:
	if duty_index >= duties.size():
		return {}
	return duties[duty_index]


func _duty_room() -> String:
	var duty := _current_duty()
	return "" if duty.is_empty() else str(duty.get("room", ""))


## Spawns whatever the current duty needs and points the guard at it.
func _start_current_duty() -> void:
	_clear_duty_objects()
	var duty := _current_duty()
	if duty.is_empty():
		_refresh_objective()
		return
	duty_started_at = Game.elapsed_minutes
	match str(duty["kind"]):
		"door":
			_start_service_door_mission()
		"breaker":
			_start_power_out()
		"wires":
			_spawn_task(duty, "wires", "CAMERA JUNCTION",
				"res://assets/generated/prop_breaker.png", Vector2.ZERO, true)
		"codes":
			_spawn_task(duty, "codes", "CAMERA SERVER",
				"res://assets/generated/terminal.png", Vector2.ZERO, true)
		"inspect":
			_spawn_anomaly(patrol_stops[int(duty["stop_index"])])
		"haul":
			_spawn_carry(duty)
	_refresh_objective()
	hud.show_message(str(duty.get("detail", duty.get("text", ""))))
	Game.add_log_entry("Duty: " + str(duty.get("detail", duty.get("text", ""))))


## Marks the duty done, banks the evidence and moves the shift on.
func _complete_duty(evidence: String) -> void:
	if _current_duty().is_empty():
		return
	mission1_active = false
	power_out_active = false
	_dim_lights(false)
	if evidence != "":
		add_evidence(evidence)
	duty_index += 1
	_start_current_duty()
	hud.show_message("Duty logged. %d of %d done." % [mini(duty_index, duties.size()), duties.size()])
	autosave()


## Clears anything the last duty left standing in the mall.
func _clear_duty_objects() -> void:
	if active_anomaly != null and is_instance_valid(active_anomaly):
		active_anomaly.queue_free()
	active_anomaly = null
	duty_point = Vector2.ZERO
	hauling = false
	haul_kind = ""
	for node in get_tree().get_nodes_in_group("task_item"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("duty_carry"):
		node.queue_free()


## Where a duty's object goes. Falls back to the room's own centre, which the
## guard can always walk to.
func _duty_spot(room: String, at: Vector2) -> Vector2:
	if at != Vector2.ZERO:
		return at
	if room == "" or not mall.rooms.has(room):
		return player.global_position
	var spot: Vector2 = mall.room_rect_world(room).get_center()
	if DUTY_NUDGE.has(room):
		spot += DUTY_NUDGE[room]
	return spot


## Two interactables on one tile fight over the prompt, and the guard presses E
## on the wrong one. Walk outward until the spot is clear.
func _clear_spot(spot: Vector2) -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2.ZERO, Vector2(0, 46), Vector2(0, -46), Vector2(46, 0), Vector2(-46, 0),
		Vector2(46, 46), Vector2(-46, -46), Vector2(0, 92), Vector2(92, 0),
	]
	for offset in offsets:
		var candidate := spot + offset
		if not _occupied(candidate):
			return candidate
	return spot


func _occupied(point: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node2D and (node as Node2D).global_position.distance_to(point) < 44.0:
			return true
	return false


## Wall-mounted fittings have to stand against a wall. A camera junction or a
## server box dropped at the room's centre reads as an outlet floating in
## mid-air, unattached to anything - which is exactly how it read on screen.
##
## The room rectangles in mall.gd already describe every room's bounds, so the
## object goes on the nearest edge of its own room, just inside the wall. (A ray
## cast is no good here: furniture and the walls' Blocker nodes share collision
## layer 1, and "Blocker" is also the name of the bodies inside doors and
## breakers, so a hit cannot be told apart from a shelf.)
func _snap_to_wall(spot: Vector2, room: String) -> Vector2:
	if room == "" or not mall.rooms.has(room):
		return spot
	var rect: Rect2 = mall.room_rect_world(room)
	const INSET := 22.0
	var to_left := absf(spot.x - rect.position.x)
	var to_right := absf(spot.x - rect.end.x)
	var to_top := absf(spot.y - rect.position.y)
	var to_bottom := absf(spot.y - rect.end.y)
	var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if nearest == to_left:
		return Vector2(rect.position.x + INSET, spot.y)
	if nearest == to_right:
		return Vector2(rect.end.x - INSET, spot.y)
	if nearest == to_top:
		return Vector2(spot.x, rect.position.y + INSET)
	return Vector2(spot.x, rect.end.y - INSET)


func _spawn_task(duty: Dictionary, kind: String, title: String, texture: String, at: Vector2, wall_mount: bool = false) -> void:
	var item := TASK_ITEM_SCENE.instantiate()
	var spot := _clear_spot(_duty_spot(str(duty.get("room", "")), at))
	if wall_mount:
		spot = _snap_to_wall(spot, str(duty.get("room", "")))
	item.position = spot
	duty_point = spot
	item.setup(kind, title, texture)
	item.solved.connect(_on_task_solved)
	objects.add_child.call_deferred(item)


func _on_task_solved() -> void:
	_complete_duty("Repair finished.")


func _spawn_carry(duty: Dictionary) -> void:
	var item := TASK_ITEM_SCENE.instantiate()
	item.position = _clear_spot(_duty_spot(str(duty.get("room", "")), Vector2.ZERO))
	duty_point = item.position
	item.add_to_group("duty_carry")
	item.setup("carry", "LOG", "res://assets/generated/anomaly_note.png",
		str(duty.get("carry", "item")))
	item.picked_up.connect(_on_carry_picked_up)
	objects.add_child.call_deferred(item)


func _on_carry_picked_up() -> void:
	var duty := _current_duty()
	if duty.is_empty():
		return
	hauling = true
	haul_kind = str(duty.get("carry", "item"))
	hud.show_message("Taken. Get it back to the security office.")
	Game.add_log_entry("Picked up the " + haul_kind + ".")
	_refresh_objective()


# --- the threat director --------------------------------------------------
# From night 2 on, the mall is never allowed to be empty: every hunter_gap
# seconds another hunter is released, up to the night's cap.

func _update_director(delta: float) -> void:
	if _failing:
		return
	var cfg := NightConfig.for_night(Game.night)
	var cap := int(cfg["threats_max"])
	var gap := float(cfg["hunter_gap"])
	if finale:
		# Once the paperwork is done the mall stops pretending and comes hunting.
		cap += 1
		gap *= 0.45
	if cap <= 0:
		return
	# While the night's cap is already loose, hold the timer at zero so the next
	# release still waits a full gap after this one is dealt with.
	if _hunter_count() >= cap:
		_pressure_t = 0.0
		return
	_pressure_t += delta
	if _pressure_t < gap:
		return
	_pressure_t = 0.0
	_release_hunter()


func _hunter_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("entity"):
		if node is MallAgent and (node as MallAgent).active \
				and not node.is_in_group("practice_mannequin"):
			count += 1
	return count


## Releases the nastiest hunter the night allows. The scripted set-pieces are the
## pool - they were always in the game, they just rarely got the chance to run.
func _release_hunter() -> void:
	var cfg := NightConfig.for_night(Game.night)
	# The Warden is gated by a minute mark, not by a whole night. Tying it to night
	# 3 alone meant a player had to survive two full shifts before they could ever
	# see it; now night 2 grows one late in the shift and night 3 gets it almost at
	# once. -1 means the night never grows one.
	var warden_from := int(cfg.get("warden_from", -1))
	if warden_from >= 0 and not warden_active and Game.elapsed_minutes >= warden_from:
		_start_warden()
		return
	# Night 1 leads with the gentlest rule there is: a mannequin that light can
	# freeze. The shadow's "put your torch out and run" comes second.
	var order := ["mannequin", "shadow"] if Game.night == 1 else ["shadow", "mannequin"]
	for kind in order:
		if kind == "mannequin" and not mannequin_active and not Game.has_flag("mannequin_done"):
			_start_mannequin()
			return
		if kind == "shadow" and not shadow_active and not Game.has_flag("shadow_done"):
			_start_shadow()
			return
	if not open_store_active and not Game.has_flag("open_store_done"):
		_start_open_store()
		return
	# Everything scripted has already run tonight. Put the mannequin back out on
	# the floor rather than letting the night go quiet.
	Game.set_flag("mannequin_done", false)
	_start_mannequin()


# --- the Warden -----------------------------------------------------------

## Night speed scaling for everything that hunts.
func _night_speed(base: float) -> float:
	return base * float(NightConfig.for_night(Game.night)["threat_speed"])


func _start_warden() -> void:
	warden_active = true
	Game.set_flag("warden_active", true)
	warden = WARDEN_SCENE.instantiate()
	warden.position = _shadow_spawn_point()
	warden.patrol_points = _warden_patrol()
	warden.chase_speed = _night_speed(warden.chase_speed)
	warden.patrol_speed = _night_speed(warden.patrol_speed)
	warden.activate(player)
	warden.latched_on.connect(_on_warden_latched)
	warden.shaken_off.connect(_on_warden_shaken)
	warden.caught_player.connect(_on_warden_caught)
	entities.add_child.call_deferred(warden)
	hud.set_danger(true)
	ZivaSfx.play(self, SFX_STING, 0.05, -6.0)
	Game.set_warning("SOMETHING TALL IS WALKING THE CORRIDORS. It hunts by sound.")
	hud.show_message("Something tall is walking the corridors. It hunts by sound.")
	Game.add_log_entry("The Warden is awake.")


## When it has nothing to follow it walks the three corridor lanes, so it is
## always somewhere in the building rather than standing in a corner.
func _warden_patrol() -> Array[Vector2]:
	var px := player.global_position.x
	var points: Array[Vector2] = []
	for lane in [528.0, 1008.0, 1488.0]:
		points.append(_lane_point(lane, px + 300.0))
		points.append(_lane_point(lane, px - 300.0))
	return points


func _on_warden_latched() -> void:
	player.latched = true
	hud.show_message("IT HAS YOU. Reach the security office, or drop a flare.")
	Game.set_warning("IT IS ON YOUR BACK. Reach the office, or drop a flare with Q.")
	Game.add_log_entry("The Warden latched on.")
	hud.set_danger(true)


func _on_warden_shaken() -> void:
	player.latched = false
	add_evidence("Shook the Warden off its back.")
	Game.set_warning("")
	hud.show_message("It peels off your back and backs away into the dark.")
	hud.set_danger(_any_encounter())
	_refresh_objective()


func _on_warden_caught() -> void:
	warden_active = false
	player.latched = false
	_fail("res://assets/generated/warden.png", "The Warden finished what it started.")


## Light is the only thing it cannot hold on through.
func _tick_warden(delta: float) -> void:
	if warden == null or not is_instance_valid(warden) or not warden.latched:
		return
	# Riding the guard burns the cell as well as the nerve.
	player.battery = maxf(0.0, player.battery - 0.02 * delta)
	# A live countdown. The latch has always had a time limit, but the guard had
	# no way to see it, so being grabbed read as a death sentence rather than a
	# thirteen-second window with two ways out of it.
	var left := maxi(0, int(ceil(WardenEntity.LATCH_LIMIT - warden.latch_progress())))
	Game.set_warning("IT IS ON YOUR BACK - %d. Reach the office, or drop a flare with Q." % left)
	if _player_in_safe_room():
		warden.release()
		return
	for node in get_tree().get_nodes_in_group("flare"):
		if node is Flare and (node as Flare).lights(player.global_position):
			warden.release()
			return


func _spawn_anomaly(stop: Dictionary) -> void:
	var spots: Array = stop["spots"]
	var cell: Vector2i = spots[randi() % spots.size()]
	active_anomaly = ANOMALY_SCENE.instantiate()
	active_anomaly.position = Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)
	duty_point = active_anomaly.position
	active_anomaly.setup(stop["tex"], stop["msg"], stop["glow"])
	active_anomaly.logged.connect(_on_anomaly_logged)
	objects.add_child.call_deferred(active_anomaly)


func _on_anomaly_logged(anomaly: Anomaly) -> void:
	hud.show_message(anomaly.message)
	ZivaSfx.play(self, SFX_LOG, 0.05, -7.0)
	anomaly.queue_free()
	active_anomaly = null
	_complete_duty("Evidence logged: " + anomaly.message)


func _any_encounter() -> bool:
	return open_store_active or mannequin_active or shadow_active or toy_active


func _create_gamezone_lights() -> void:
	var spots := [Vector2(32 * TILE, 7 * TILE), Vector2(29 * TILE, 11 * TILE), Vector2(35 * TILE, 11 * TILE)]
	for pos in spots:
		var light := PointLight2D.new()
		light.texture = load("res://assets/generated/light_glow.png")
		light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		light.texture_scale = 3.2
		light.color = Color(1, 0.93, 0.75)
		light.energy = 0.85
		light.position = pos
		light.enabled = false
		objects.add_child(light)
		gamezone_lights.append(light)


func _dim_lights(dim: bool) -> void:
	for node in get_tree().get_nodes_in_group("mall_light"):
		if node is FlickerLight:
			var light: FlickerLight = node
			if not light.has_meta("orig_energy"):
				light.set_meta("orig_energy", light.base_energy)
			if dim:
				light.base_energy = float(light.get_meta("orig_energy")) * 0.4
				light.blackout_chance = 0.06
			else:
				light.base_energy = float(light.get_meta("orig_energy"))
				light.blackout_chance = 0.012


func _fail(texture_path: String, reason: String) -> void:
	if _failing:
		return
	_failing = true
	hud.set_danger(false)
	hud.show_message(reason)
	player.can_move = false
	player.velocity = Vector2.ZERO
	Game.clock_running = false
	_play_jumpscare(texture_path)


func _play_jumpscare(texture_path: String) -> void:
	ZivaSfx.play(self, SFX_JUMPSCARE, 0.0, 0.0)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var spr := Sprite2D.new()
	spr.texture = load(texture_path)
	spr.position = Vector2(320, 190)
	spr.scale = Vector2(0.4, 0.4)
	layer.add_child(spr)

	var shake := Sprite2D.new()
	shake.texture = spr.texture
	shake.position = Vector2(320, 190)
	shake.modulate = Color(1, 0.1, 0.1)
	shake.scale = Vector2(0.4, 0.4)
	layer.add_child(shake)

	var tween := create_tween()
	tween.tween_property(spr, "scale", Vector2(7.0, 7.0), 0.35).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(shake, "scale", Vector2(7.0, 7.0), 0.5).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(bg, "color:a", 1.0, 1.1)
	tween.parallel().tween_property(shake, "modulate:a", 0.0, 0.6)
	tween.tween_interval(0.4)
	tween.tween_callback(_after_fail)


func _after_fail() -> void:
	Game.fail_night()
	Game.show_game_over()