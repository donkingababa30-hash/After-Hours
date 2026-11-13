class_name MallAgent
extends CharacterBody2D
## Shared brain for everything that hunts the guard.
##
## An agent is always in exactly one state - PATROL, CHASE, ATTACK or HELD - and
## switches on conditions its subclass decides. Movement runs through the mall's
## A* grid, so an agent walks around walls instead of grinding into them.
## Subclasses implement _think(), _goal() and _speed_for_state().

signal caught_player

enum State { PATROL, CHASE, ATTACK, HELD }

@export var patrol_speed := 48.0
@export var chase_speed := 118.0
@export var catch_distance := 26.0
@export var sense_distance := 320.0
@export var repath_interval := 0.35
## Seconds a hunter keeps walking toward the last place it had the guard in view.
##
## Without this, breaking line of sight switched a chase off like a light switch.
## With it, rounding a corner or stepping into a shop buys seconds rather than an
## instant escape - which is what makes the mall's layout a tool the player can
## actually use.
@export var memory_seconds := 6.0

var state: State = State.PATROL
var active := false
var target: Player = null
var patrol_points: Array[Vector2] = []
var patrol_index := 0

## Where the guard was last seen or heard, and how long that memory has left.
var _last_seen := Vector2.ZERO
var _last_seen_t := 0.0

var _mall: Node2D = null
var _path := PackedVector2Array()
var _path_index := 0
var _repath_t := 0.0
## Set by hear_noise(): the agent goes to look at this instead of the player.
var _noise_point := Vector2.ZERO
var _noise_t := 0.0


func _ready() -> void:
	add_to_group("entity")
	collision_layer = 8
	collision_mask = 1
	visible = active
	if active:
		_on_activate_visuals()


## Subclass hook: start the right animation.
func _on_activate_visuals() -> void:
	pass


func activate(player_ref: Player) -> void:
	target = player_ref
	active = true
	visible = true
	state = State.PATROL
	_path = PackedVector2Array()
	_repath_t = 0.0
	# activate() runs before the node is in the tree, so the visuals may not
	# exist yet. _ready() finishes the job in that case.
	if is_node_ready():
		_on_activate_visuals()


func deactivate() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO
	_path = PackedVector2Array()


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_path = PackedVector2Array()
	_path_index = 0
	_repath_t = 0.0


func _physics_process(delta: float) -> void:
	if not active or target == null or not is_instance_valid(target):
		return

	if _noise_t > 0.0:
		_noise_t -= delta

	if _last_seen_t > 0.0:
		_last_seen_t -= delta

	_think(delta)

	if state == State.HELD:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance := global_position.distance_to(target.global_position)
	if distance <= catch_distance and state != State.PATROL:
		# A subclass can turn a catch into something other than a kill.
		if _on_reach_target():
			return
		active = false
		caught_player.emit()
		return

	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = repath_interval
		_walk_path_to(_destination())

	_follow_path(_speed_for_state(), delta)


# --- subclass hooks -------------------------------------------------------

## Called the instant an agent reaches the player. Return true to say "handled":
## the Warden uses this to latch on instead of killing outright.
func _on_reach_target() -> bool:
	return false


## Something made a noise. Agents go and look at it, which is exactly what a
## thrown flare is for.
func hear_noise(at: Vector2, duration: float = 6.0) -> void:
	if not active:
		return
	_noise_point = at
	_noise_t = maxf(_noise_t, duration)


## A noise overrides wherever the subclass wanted to go.
func _destination() -> Vector2:
	if _noise_t > 0.0:
		return _noise_point
	# Losing sight of the guard does not erase them. The hunter walks to where it
	# last had them and then gives up, so a chase has a readable end that the
	# player caused rather than one that just happens.
	#
	# Skipped while HELD: that state means the agent is deliberately giving ground
	# (the mannequin backing away from the beam) and its own goal must win.
	if _last_seen_t > 0.0 and state != State.HELD:
		return _last_seen
	return _goal()

## Decide the next state from the world. Called every physics frame.
func _think(_delta: float) -> void:
	pass


## Where the agent wants to go while in the current state.
func _goal() -> Vector2:
	return target.global_position if target != null else global_position


func _speed_for_state() -> float:
	match state:
		State.PATROL:
			return patrol_speed
		State.CHASE, State.ATTACK:
			return chase_speed
		_:
			return 0.0


# --- movement -------------------------------------------------------------

func _walk_path_to(goal: Vector2) -> void:
	var mall := _mall_ref()
	var found := PackedVector2Array()
	if mall != null and mall.has_method("find_path"):
		found = mall.call("find_path", global_position, goal)
	if found.size() < 2:
		# No route (or the goal sits in a wall): head straight at it and let the
		# next repath pick up a proper route once the way opens up.
		found = PackedVector2Array([goal])
	_path = found
	_path_index = 0


func _follow_path(speed: float, _delta: float) -> void:
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) < 12.0:
		_path_index += 1
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var step: Vector2 = _path[_path_index] - global_position
	velocity = step.normalized() * speed
	move_and_slide()


# --- helpers for subclasses ----------------------------------------------

func _can_sense() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > sense_distance:
		return false
	# SIGHT, not just proximity. Detection used to be pure distance, so a hunter
	# locked on through solid walls and there was no way to break a chase except
	# outrunning it - which made every encounter feel arbitrary.
	return has_line_of_sight(target.global_position)


## Called by a subclass the moment it has the guard in view or in earshot.
func note_contact(at: Vector2) -> void:
	_last_seen = at
	_last_seen_t = memory_seconds


## True when nothing solid stands between the agent and `to`. Samples the same
## grid the A* pathing uses, so a wall, a shop front, or the block of shelving in
## the middle of a store all break the line.
func has_line_of_sight(to: Vector2) -> bool:
	var mall := _mall_ref()
	if mall == null or not mall.has_method("blocks_sight"):
		return true
	var span := to - global_position
	var steps := maxi(2, int(span.length() / 20.0))
	for i in range(1, steps):
		if bool(mall.call("blocks_sight", global_position + span * (float(i) / float(steps)))):
			return false
	return true


## The mall, looked up lazily: agents are built before they enter the tree, so
## the group lookup cannot happen in _ready().
func _mall_ref() -> Node2D:
	if _mall == null or not is_instance_valid(_mall):
		_mall = get_tree().get_first_node_in_group("mall") as Node2D
	return _mall


func _patrol_goal() -> Vector2:
	if patrol_points.is_empty():
		return global_position
	if global_position.distance_to(patrol_points[patrol_index]) < 30.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
	return patrol_points[patrol_index]


func in_beam(half_angle: float, beam_range: float) -> bool:
	if target == null or not target.flashlight_on:
		return false
	var to_self := global_position - target.global_position
	var distance := to_self.length()
	if distance < 1.0:
		return true
	if distance > beam_range:
		return false
	if absf(target.facing.normalized().angle_to(to_self.normalized())) >= half_angle:
		return false
	# A wall stops the beam as surely as it stops the eye. Without this, shining
	# the torch at a shop front froze whatever was standing behind it, and a
	# mannequin on the far side of a wall counted as "held off".
	return has_line_of_sight(target.global_position)