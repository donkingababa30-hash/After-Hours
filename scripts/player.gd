class_name Player
extends CharacterBody2D
## The night-shift security guard. Walks with WASD, carries a flashlight
## and can interact with nearby objects.

const SPEED := 118.0
## How much faster the guard moves while sprinting.
const SPRINT_MULT := 1.8
const BASE_BEAM_ENERGY := 1.55
## Full charge lasts about three minutes of continuous use.
const BATTERY_DRAIN := 0.0055
const FLARE_SCENE := preload("res://scenes/objects/flare.tscn")
const SFX_FOOTSTEP := preload("res://assets/generated/audio/footstep.mp3")
const SFX_CLICK := preload("res://assets/generated/audio/flashlight_click.mp3")
const SFX_BREATH := preload("res://assets/generated/audio/guard_breath.mp3")

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var flashlight: Node2D = $Flashlight
@onready var light: PointLight2D = $Flashlight/Light
@onready var interaction_area: Area2D = $InteractionArea

var can_move := true
var flashlight_on := true
var facing := Vector2.DOWN
## 0.0 to 1.0. Runs down while the torch is on.
var battery := 1.0

## Sprint: runs down while held, refills while you walk. Running is loud, and
## loud is how the things in the mall find you.
var stamina := 1.0
var stamina_max := 1.0
var stamina_drain := 0.20
var stamina_regen := 0.28
var sprinting := false
## Once the tank is dry you cannot run again until you have caught your breath.
## Without this the guard could stutter-sprint forever on an empty bar: stamina
## ticked back just above the old threshold every other frame, so releasing and
## re-pressing SHIFT let you run on nothing.
var exhausted := false
## Fraction of the bar you must get back before running is allowed again.
const SPRINT_RECOVER := 0.45

## Composure: the dark and the things hunting you wear it down; light restores it.
## At zero the guard panics - slower, louder, and unable to run.
var composure := 1.0
var composure_drain := 0.012
var in_safe_room := false
## True while the Warden is riding on the guard's back.
var latched := false

## Flares carried. A flare buys a few seconds and pulls hunters off your trail.
var flares := 0
var _beam_t := 0.0
var _breath_t := 0.0

var active_target: Interactable = null

var _nearby: Array[Interactable] = []
var _step_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	interaction_area.area_entered.connect(_on_area_entered)
	interaction_area.area_exited.connect(_on_area_exited)
	light.enabled = flashlight_on
	sprite.play("idle_down")
	apply_night_config()


## Reads the current night's rules for stamina, nerve and supplies.
func apply_night_config() -> void:
	var cfg := NightConfig.for_night(Game.night)
	stamina_max = float(cfg["stamina_max"])
	stamina_drain = float(cfg["stamina_drain"])
	stamina_regen = float(cfg["stamina_regen"])
	composure_drain = float(cfg["composure_drain"])
	flares = int(cfg["flares"])
	stamina = stamina_max
	composure = 1.0


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if can_move:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var wants_sprint := dir.length() > 0.1 and Input.is_action_pressed("sprint") and not exhausted
	sprinting = wants_sprint and composure > 0.08

	var speed := SPEED
	if sprinting:
		speed *= SPRINT_MULT
	# Frayed nerves slow the legs, and so does something riding on your back.
	speed *= lerpf(1.0, 0.84, 1.0 - composure)
	if latched:
		speed *= 0.72
	velocity = dir * speed
	move_and_slide()

	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		facing = to_mouse.normalized()

	_beam_t += delta
	_update_animation(dir, delta)
	_update_flashlight(delta)
	_update_battery(delta)
	_update_stamina(delta)
	_update_breathing(delta)
	_update_composure(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event.is_action_pressed("flare"):
		throw_flare()
	elif event.is_action_pressed("interact"):
		_try_interact()


func toggle_flashlight() -> void:
	set_flashlight(not flashlight_on)


func set_flashlight(on: bool) -> void:
	if on == flashlight_on:
		return
	if on and battery <= 0.0:
		_show_hud_message("The torch is dead. Find a battery.")
		ZivaSfx.play(self, SFX_CLICK, 0.04, -14.0)
		return
	flashlight_on = on
	light.enabled = on
	ZivaSfx.play(self, SFX_CLICK, 0.04, -9.0)


## Called by a battery pickup. Topping up mid-run is part of the loop.
func recharge_battery(amount: float) -> void:
	battery = clampf(battery + amount, 0.0, 1.0)
	_show_hud_message("Fresh cell in. Torch at %d%%." % int(battery * 100.0))


func _update_battery(delta: float) -> void:
	if flashlight_on and battery > 0.0:
		var drain := BATTERY_DRAIN
		# Something riding on your back leans on the switch as well.
		if latched:
			drain += 0.02
		battery = maxf(0.0, battery - drain * delta)
		if battery <= 0.0:
			flashlight_on = false
			light.enabled = false
			ZivaSfx.play(self, SFX_CLICK, 0.04, -13.0)
			_show_hud_message("The flashlight dies in your hand.")
	# The beam visibly weakens before it goes, so the player gets warning.
	var health := 1.0
	if battery < 0.25:
		health = 0.35 + battery * 2.6
		health *= 0.92 + sin(_beam_t * 22.0) * 0.08
	light.energy = BASE_BEAM_ENERGY * health


## Sprinting burns stamina; standing still refills it. Blow the whole bar and
## you are winded: you walk until you have caught your breath back up past
## SPRINT_RECOVER, and getting there is deliberately slower than normal regen.
func _update_stamina(delta: float) -> void:
	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		if stamina <= 0.0 and not exhausted:
			exhausted = true
			_show_hud_message("Legs gone. Stop and get your breath back.")
		return
	var rate := stamina_regen * (0.5 if exhausted else 1.0)
	stamina = minf(stamina_max, stamina + rate * delta)
	if exhausted and stamina >= stamina_max * SPRINT_RECOVER:
		exhausted = false
		_show_hud_message("Breath back. You can run again.")


## Footsteps. Running is faster and louder, and the running steps are kept tight
## in pitch on purpose: a sprint should read as one determined rhythm. Wide
## random pitch on every step is exactly what made the old sprint sound chaotic.
func _update_footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if sprinting:
		_step_timer = 0.27
		ZivaSfx.play(self, SFX_FOOTSTEP, 0.06, -13.0)
	else:
		_step_timer = 0.42
		ZivaSfx.play(self, SFX_FOOTSTEP, 0.16, -17.0)


## The GUARD'S OWN breathing, and nothing else.
##
## It is tied strictly to two states the HUD is already showing: out of breath
## (amber STAMINA bar, "legs gone") and the Warden riding on your back ("GET IT
## OFF"). The sound therefore always has a visible cause on screen.
##
## It used to fire on low nerve as well. Low nerve is a long, quiet state with
## nothing on screen explaining it, so for most of a bad night the guard panted
## for no reason the player could see - which is exactly the "unexplained
## background noise" this was reported as.
func _update_breathing(delta: float) -> void:
	if sprinting or not (exhausted or latched) or get_tree().paused:
		_breath_t = 0.0
		return
	if not Game.has_flag("breath_explained"):
		Game.set_flag("breath_explained")
		_show_hud_message("That is you breathing hard - and anything hunting you can hear it.")
	_breath_t -= delta
	if _breath_t > 0.0:
		return
	_breath_t = 0.72 if latched else 0.95
	ZivaSfx.play(self, SFX_BREATH, 0.05, -22.0)


## The dark eats at the guard's nerve; light and safety put it back.
func _update_composure(delta: float) -> void:
	var drain := composure_drain
	if not flashlight_on:
		drain *= 2.2
	if latched:
		drain *= 7.0
	drain *= 1.0 + float(_nearby_hunters()) * 0.7
	composure = clampf(composure - drain * delta, 0.0, 1.0)

	if in_safe_room:
		composure = minf(1.0, composure + 0.20 * delta)
	elif flashlight_on:
		composure = minf(1.0, composure + 0.05 * delta)


## How much noise the guard is making, 0 to 1. Running feet carry a long way, and
## so does ragged breathing. Standing still in the dark is silent.
## Hunters that listen (the Warden) use this as their hearing range.
func noise_level() -> float:
	if not can_move:
		return 0.0
	var level := 0.0
	if velocity.length() > 8.0:
		level = 0.35
	if sprinting:
		level = 1.0
	if composure < 0.3:
		level = maxf(level, 0.5)
	return level


## How many hunters are close enough to be felt. They do not have to see you.
func _nearby_hunters() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("entity"):
		if node is MallAgent and (node as MallAgent).active:
			if global_position.distance_to(node.global_position) < 260.0:
				count += 1
	return count


## Drops a flare at the guard's feet. Costs one of a very small supply.
func throw_flare() -> void:
	if flares <= 0:
		_show_hud_message("No flares left.")
		ZivaSfx.play(self, SFX_CLICK, 0.05, -18.0)
		return
	flares -= 1
	var flare := FLARE_SCENE.instantiate()
	flare.position = global_position + facing * 30.0
	get_tree().current_scene.add_child(flare)
	ZivaSfx.play(self, SFX_CLICK, 0.05, -6.0)
	_show_hud_message("Flare down. It will not burn forever.")


func _show_hud_message(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_message(text)


func _update_flashlight(delta: float) -> void:
	if facing.length() < 0.1:
		return
	var target := facing.angle()
	flashlight.rotation = lerp_angle(flashlight.rotation, target, clampf(delta * 14.0, 0.0, 1.0))


func _update_animation(dir: Vector2, delta: float) -> void:
	var moving := dir.length() > 0.15
	var name_dir := "down"
	if absf(facing.x) > absf(facing.y):
		name_dir = "left"
	elif facing.y < 0.0:
		name_dir = "up"
	var anim := ("walk_" if moving else "idle_") + name_dir
	if sprite.animation != anim:
		sprite.play(anim)
	if name_dir == "left":
		sprite.flip_h = facing.x > 0.0
	else:
		sprite.flip_h = false

	_update_footsteps(delta, moving)


func _try_interact() -> void:
	if active_target == null:
		return
	if not active_target.is_available():
		return
	active_target.interact(self)
	if active_target.one_shot:
		active_target.mark_used()
		_nearby.erase(active_target)
		_refresh_target()


func _on_area_entered(area: Area2D) -> void:
	if area is Interactable:
		if not _nearby.has(area):
			_nearby.append(area)
		_refresh_target()


func _on_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_nearby.erase(area)
		_refresh_target()


func _refresh_target() -> void:
	var best: Interactable = null
	var best_priority := -1
	var best_dist := INF
	for item in _nearby:
		if not is_instance_valid(item) or not item.is_available():
			continue
		var d := global_position.distance_to(item.global_position)
		# Objective objects beat flavour objects; distance only breaks the tie.
		if item.prompt_priority > best_priority or (item.prompt_priority == best_priority and d < best_dist):
			best_priority = item.prompt_priority
			best_dist = d
			best = item
	active_target = best


func get_prompt() -> String:
	if active_target == null:
		return ""
	return active_target.get_prompt()