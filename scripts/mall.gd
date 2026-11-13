class_name Mall
extends Node2D
## Builds RIVERVIEW MALL at runtime: floor, walls, props, lights,
## room name triggers and the player. Also wires up the encounter manager.

const TILE := 32
const MAP_W := 88
const MAP_H := 62

const SRC_FLOOR := 0
const SRC_CARPET := 1
## How many tiles of wall to draw around the walkable space.
const WALL_BORDER := 2

const PLAYER_SPAWN := Vector2i(32, 52)

const DOOR_SCENE := preload("res://scenes/objects/door.tscn")
const TERMINAL_SCENE := preload("res://scenes/objects/security_terminal.tscn")
const SLIDING_DOOR_SCENE := preload("res://scenes/objects/sliding_door.tscn")
const SERVICE_DOOR_SCENE := preload("res://scenes/objects/service_door.tscn")
const SEARCHABLE_SCENE := preload("res://scenes/objects/searchable.tscn")
const BREAKER_SCENE := preload("res://scenes/objects/breaker.tscn")

## Walkable map data and the pathfinding grid built from it.
var map_grid: Array = []
var astar: AStarGrid2D = null

var rooms := {
	"Techworld": Rect2i(2, 2, 17, 12),
	"Game Zone": Rect2i(26, 2, 13, 12),
	"Fashion Hub": Rect2i(46, 2, 16, 12),
	"Books & More": Rect2i(2, 19, 17, 10),
	"Main Atrium": Rect2i(26, 19, 13, 10),
	"Beauty Co.": Rect2i(46, 19, 16, 10),
	"Coffee Shop": Rect2i(2, 34, 17, 10),
	"Food Court": Rect2i(26, 34, 13, 10),
	"Sports Zone": Rect2i(46, 34, 16, 10),
	"Storage Room": Rect2i(2, 49, 17, 8),
	"Security Office": Rect2i(26, 49, 13, 8),
	"Restrooms": Rect2i(46, 49, 16, 8),
	## East wing, reached down the long corridor past the Fashion Hub.
	"TOYBOX": Rect2i(69, 2, 17, 12),
	"CINEMA": Rect2i(69, 19, 17, 10),
}

## Which TileSet source each room floor uses.
var room_floor := {
	"Techworld": 2, "Game Zone": 2, "Sports Zone": 2,
	"Fashion Hub": 1, "Books & More": 1, "Beauty Co.": 1, "Coffee Shop": 1,
	"Storage Room": 3,
	"Security Office": 0, "Main Atrium": 0, "Food Court": 0, "Restrooms": 0,
	"TOYBOX": 2, "CINEMA": 3,
}

var corridors := [
	## Corridors 1 and 2 run on east past the vertical link to reach the doors of
	## the east wing. Anything shorter leaves the TOYBOX sealed off.
	Rect2i(2, 15, 77, 3),
	Rect2i(2, 30, 77, 3),
	Rect2i(2, 45, 63, 3),
	Rect2i(21, 2, 3, 58),
	Rect2i(41, 2, 3, 58),
	Rect2i(64, 2, 3, 58),
	Rect2i(21, 58, 23, 2),
]

var doorways := [
	Rect2i(7, 14, 4, 1), Rect2i(31, 14, 4, 1), Rect2i(52, 14, 4, 1),
	Rect2i(8, 18, 2, 1), Rect2i(31, 18, 4, 1), Rect2i(52, 18, 4, 1),
	Rect2i(24, 20, 2, 2), Rect2i(39, 20, 2, 2),
	Rect2i(19, 25, 2, 2), Rect2i(44, 25, 2, 2),
	Rect2i(31, 29, 4, 1),
	Rect2i(8, 33, 2, 1), Rect2i(31, 33, 4, 1), Rect2i(53, 33, 2, 1),
	Rect2i(24, 38, 2, 2), Rect2i(39, 38, 2, 2),
	Rect2i(31, 44, 4, 1),
	Rect2i(8, 48, 2, 1), Rect2i(31, 48, 4, 1), Rect2i(52, 48, 4, 1),
	Rect2i(74, 14, 4, 1), Rect2i(74, 18, 4, 1), Rect2i(74, 29, 4, 1),
]

@onready var floor_layer: TileMapLayer = $Floor
@onready var walls_layer: TileMapLayer = $Walls
@onready var objects: Node2D = $Objects
@onready var entities: Node2D = $Entities
@onready var player: Player = $Player
@onready var hud: GameHud = $HUD
@onready var encounter_manager: EncounterManager = $EncounterManager


func _ready() -> void:
	add_to_group("mall")
	if not Game.clock_running:
		Game.start_night()
	_build_map()
	_place_props()
	_place_furniture()
	_place_furniture_extra()
	_place_furniture_dense()
	_place_lights()
	_place_doors()
	_place_sliding_doors()
	_place_inspectables()
	_place_terminal()
	_place_signs()
	_place_service_door()
	_place_searchables()
	_place_breaker()
	_place_room_triggers()
	_setup_player()

	encounter_manager = $EncounterManager
	encounter_manager.setup(self, hud, player, objects, entities)

	_start_ambience()

	hud.show_location("Security Office")
	hud.show_message("Shift starts at 10:00 PM. Stay alert.")


func _start_ambience() -> void:
	var music := AudioStreamPlayer.new()
	var stream: AudioStream = load("res://assets/generated/audio/ambience_drone.mp3")
	if stream is AudioStreamMP3:
		stream.loop = true
	music.stream = stream
	# This has to sit clearly under everything else without being a nuisance.
	# It used to be -16 dB, which read as silence on laptop speakers.
	music.volume_db = -7.0
	music.add_to_group("ambience")
	add_child(music)
	music.play()


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


func room_rect_world(room_name: String) -> Rect2:
	var r: Rect2i = rooms[room_name]
	return Rect2(Vector2(r.position.x * TILE, r.position.y * TILE), Vector2(r.size.x * TILE, r.size.y * TILE))


## World position of the current objective, or Vector2.ZERO when there is none.
func objective_position() -> Vector2:
	# An explicit point wins: the objective may be a door in a corridor rather
	# than anything a room name can describe.
	if Game.objective_point != Vector2.ZERO:
		return Game.objective_point
	if Game.objective_room == "" or not rooms.has(Game.objective_room):
		return Vector2.ZERO
	return room_rect_world(Game.objective_room).get_center()


func _build_map() -> void:
	var grid: Array = []
	for y in MAP_H:
		var row := PackedInt32Array()
		row.resize(MAP_W)
		row.fill(-1)
		grid.append(row)

	for c in corridors:
		_fill(grid, c, SRC_FLOOR)
	for room_name in rooms:
		var value: int = int(room_floor.get(room_name, SRC_FLOOR))
		_fill(grid, rooms[room_name], value)
	for d in doorways:
		_fill(grid, d, SRC_FLOOR)

	# Walls are only drawn as a border hugging the walkable space. Filling every
	# other cell turned the mall into one giant black block; leaving the outside
	# open makes the floor plan read at a glance.
	for y in MAP_H:
		for x in MAP_W:
			var value: int = grid[y][x]
			if value >= 0:
				floor_layer.set_cell(Vector2i(x, y), value, Vector2i.ZERO)
			elif _near_floor(grid, x, y, WALL_BORDER):
				walls_layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)

	map_grid = grid
	_build_astar(grid)


## Grid used by enemy pathfinding, built from the same walkable data as the map.
func _build_astar(grid: Array) -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, MAP_W, MAP_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in MAP_H:
		for x in MAP_W:
			if grid[y][x] < 0:
				astar.set_point_solid(Vector2i(x, y), true)


func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(point.x / TILE), 0, MAP_W - 1),
		clampi(int(point.y / TILE), 0, MAP_H - 1)
	)


## World-space route between two points, walking around walls. Empty when there
## is no way through.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	if astar == null:
		return points
	var cells := astar.get_id_path(cell_of(from), cell_of(to))
	for cell in cells:
		points.append(cell_center(cell))
	return points


## True when the straight line between two points is clear of walls.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	if map_grid.is_empty():
		return false
	var steps := int(from.distance_to(to) / 12.0) + 1
	for i in range(steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		var cell := cell_of(p)
		if map_grid[cell.y][cell.x] < 0:
			return false
	return true


func _near_floor(grid: Array, x: int, y: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H:
				continue
			if grid[ny][nx] >= 0:
				return true
	return false


func _fill(grid: Array, rect: Rect2i, value: int) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if y >= 0 and y < MAP_H and x >= 0 and x < MAP_W:
				grid[y][x] = value


func _place_props() -> void:
	_add_solid(Vector2(1040, 752), "res://assets/generated/fountain.png", Vector2(74, 74))
	# The two escalator banks flanking the fountain. They are solid - a stopped
	# escalator is not somewhere the guard walks at night - but they have to READ
	# as escalators: step treads, balustrades, handrails. The previous grey
	# shutter panels were just rectangles blocking the atrium floor.
	_add_solid(Vector2(912, 664), "res://assets/generated/prop_escalator.png", Vector2(92, 54))
	_add_solid(Vector2(1168, 664), "res://assets/generated/prop_escalator.png", Vector2(92, 54))


## Furniture is placed by hand as cell coordinates across several passes, and two
## entries landing on the same tile is easy to do and ugly to look at: two sprites
## stack pixel-for-pixel. Anything that would substantially sit inside a prop
## already standing there is dropped instead of drawn.
## Every prop footprint placed so far this build. Tracked here rather than read
## back out of the scene tree: props are added while the mall is still assembling,
## so tree membership is not reliable yet.
var _placed_props: Array[Rect2] = []




## Texture names whose art on disk turned out wrong. prop_bin.png is not a bin -
## it renders as a grey disc with a cross and radial ribs, like a valve wheel -
## and seventeen of them are dotted around the mall, which is a large part of why
## the interiors read as full of random objects. Mapping the name here fixes every
## placement at once instead of editing seventeen call sites.
const TEX_ALIAS := {"prop_bin": "prop_wastebin"}


func _put(tex: String, cell: Vector2i, box: Vector2) -> void:
	var centre := cell_center(cell)
	if _prop_space_taken(Rect2(centre - box * 0.5, box)):
		return
	_add_solid(centre, "res://assets/generated/%s.png" % TEX_ALIAS.get(tex, tex), box)


## True when a prop would genuinely sit inside this one. Props should occupy whole
## tiles, so anything overlapping by more than a quarter tile in BOTH directions
## is a conflict. A few pixels of brush past a neighbour is normal dressing.
func _prop_space_taken(rect: Rect2) -> bool:
	const TOLERANCE := 8.0
	for other in _placed_props:
		if not rect.intersects(other):
			continue
		var shared := rect.intersection(other)
		if shared.size.x > TOLERANCE and shared.size.y > TOLERANCE:
			return true
	return false


func _place_furniture() -> void:
	# --- Techworld -------------------------------------------------------
	_put("prop_tvwall", Vector2i(5, 4), Vector2(90, 26))
	_put("prop_tvwall", Vector2i(5, 8), Vector2(90, 26))
	_put("prop_counter", Vector2i(15, 4), Vector2(60, 26))
	_put("shelf", Vector2i(5, 11), Vector2(44, 28))
	_put("shelf", Vector2i(9, 11), Vector2(44, 28))
	_put("shelf", Vector2i(13, 11), Vector2(44, 28))
	_put("prop_plant", Vector2i(17, 2), Vector2(26, 26))

	# --- Game Zone -------------------------------------------------------
	for x in [28, 30, 32, 34, 36]:
		_put("arcade_machine", Vector2i(x, 4), Vector2(28, 40))
	for x in [28, 30, 32]:
		_put("arcade_machine", Vector2i(x, 8), Vector2(28, 40))
	_put("prop_counter", Vector2i(36, 11), Vector2(60, 26))

	# --- Fashion Hub -----------------------------------------------------
	for x in [48, 52, 56]:
		_put("prop_rack", Vector2i(x, 4), Vector2(60, 26))
	for x in [48, 52]:
		_put("prop_rack", Vector2i(x, 8), Vector2(60, 26))
	_put("prop_counter", Vector2i(58, 11), Vector2(60, 26))
	_put("prop_plant", Vector2i(60, 2), Vector2(26, 26))

	# --- Books & More ----------------------------------------------------
	for x in [5, 9, 13]:
		_put("prop_bookcase", Vector2i(x, 21), Vector2(60, 26))
	for x in [5, 9]:
		_put("prop_bookcase", Vector2i(x, 24), Vector2(60, 26))
	_put("prop_counter", Vector2i(14, 27), Vector2(60, 26))

	# --- Main Atrium -----------------------------------------------------
	_put("prop_plant", Vector2i(27, 27), Vector2(26, 26))
	_put("prop_plant", Vector2i(37, 27), Vector2(26, 26))
	_put("prop_bench", Vector2i(30, 27), Vector2(60, 20))

	# --- Beauty Co. ------------------------------------------------------
	_put("prop_counter", Vector2i(48, 22), Vector2(60, 26))
	_put("prop_counter", Vector2i(48, 25), Vector2(60, 26))
	for x in [53, 56, 59]:
		_put("shelf", Vector2i(x, 22), Vector2(44, 28))
	for x in [53, 56]:
		_put("shelf", Vector2i(x, 25), Vector2(44, 28))
	_put("prop_plant", Vector2i(60, 27), Vector2(26, 26))

	# --- Coffee Shop -----------------------------------------------------
	_put("prop_counter", Vector2i(6, 36), Vector2(60, 26))
	for x in [5, 9, 13]:
		_put("prop_foodtable", Vector2i(x, 40), Vector2(58, 58))
	_put("prop_plant", Vector2i(17, 34), Vector2(26, 26))

	# --- Food Court ------------------------------------------------------
	_put("prop_counter", Vector2i(28, 36), Vector2(60, 26))
	_put("prop_counter", Vector2i(37, 36), Vector2(60, 26))
	for x in [27, 37]:
		for y in [38, 42]:
			_put("prop_foodtable", Vector2i(x, y), Vector2(58, 58))
	_put("prop_plant", Vector2i(38, 34), Vector2(26, 26))

	# --- Sports Zone -----------------------------------------------------
	for x in [48, 51, 54]:
		_put("prop_sportsrack", Vector2i(x, 37), Vector2(44, 26))
	for x in [48, 51]:
		_put("prop_sportsrack", Vector2i(x, 40), Vector2(44, 26))
	_put("prop_bench", Vector2i(58, 37), Vector2(60, 20))
	_put("prop_counter", Vector2i(58, 41), Vector2(60, 26))

	# --- Storage Room ----------------------------------------------------
	for x in [4, 7, 10]:
		_put("shelf", Vector2i(x, 51), Vector2(44, 28))
	for x in [4, 7]:
		_put("shelf", Vector2i(x, 54), Vector2(44, 28))
	_put("prop_vending", Vector2i(16, 51), Vector2(28, 40))

	# --- Security Office -------------------------------------------------
	_put("prop_counter", Vector2i(28, 51), Vector2(60, 26))
	_put("prop_counter", Vector2i(28, 54), Vector2(60, 26))
	_put("prop_plant", Vector2i(27, 56), Vector2(26, 26))

	# --- Restrooms -------------------------------------------------------
	_put("prop_counter", Vector2i(48, 51), Vector2(60, 26))
	_put("prop_counter", Vector2i(48, 54), Vector2(60, 26))
	_put("prop_bench", Vector2i(56, 54), Vector2(60, 20))
	_put("prop_plant", Vector2i(60, 51), Vector2(26, 26))

	# --- Corridors -------------------------------------------------------
	_put("prop_plant", Vector2i(14, 15), Vector2(26, 26))
	_put("prop_plant", Vector2i(44, 15), Vector2(26, 26))
	_put("prop_bench", Vector2i(50, 15), Vector2(60, 20))
	_put("prop_vending", Vector2i(24, 15), Vector2(28, 40))
	_put("prop_plant", Vector2i(14, 30), Vector2(26, 26))
	_put("prop_vending", Vector2i(44, 30), Vector2(28, 40))
	_put("prop_plant", Vector2i(14, 45), Vector2(26, 26))
	_put("prop_vending", Vector2i(44, 45), Vector2(28, 40))
	_put("prop_bench", Vector2i(20, 45), Vector2(60, 20))
	_put("prop_plant", Vector2i(21, 10), Vector2(26, 26))
	_put("prop_plant", Vector2i(23, 40), Vector2(26, 26))
	_put("prop_plant", Vector2i(43, 55), Vector2(26, 26))


## A soft radial shadow built as an engine gradient rather than a bitmap: it is a
## technical alpha ramp, not artwork, and one texture stretches to any footprint.
func _make_shadow() -> GradientTexture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0.62))
	ramp.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = ramp
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


## How much walkable floor must show between a prop's sprite and the wall cell
## beside it. A prop placed flush against a wall reads as embedded in it: with no
## floor between the sprite and the wall graphic, half the object looks buried.
const WALL_MARGIN := 12.0


## Is this world point on walkable floor?
func _walkable(point: Vector2) -> bool:
	if map_grid.is_empty():
		return true
	var c := cell_of(point)
	return map_grid[c.y][c.x] >= 0


## Slides a prop inward until every edge of its sprite shows a margin of walkable
## floor. Applied to EVERY prop in _add_solid, so a single bad cell coordinate can
## no longer leave something visually stuck through a wall - and neither can a new
## placement added later.
func _inset_from_walls(center: Vector2, size: Vector2) -> Vector2:
	var half := size * 0.5
	var pos := center
	const STEP := 6.0
	for side in [-1.0, 1.0]:
		var tries := 0
		while tries < 12 and not _walkable(Vector2(pos.x + side * (half.x + WALL_MARGIN + 2.0), pos.y)):
			pos.x -= side * STEP
			tries += 1
	for side in [-1.0, 1.0]:
		var tries := 0
		while tries < 12 and not _walkable(Vector2(pos.x, pos.y + side * (half.y + WALL_MARGIN + 2.0))):
			pos.y -= side * STEP
			tries += 1
	return pos


func _add_solid(center: Vector2, texture_path: String, shape_size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var spr := Sprite2D.new()
	spr.texture = load(texture_path)
	var tex_size: Vector2 = spr.texture.get_size()
	# The sprite is drawn at its native texture size, so that is what has to clear
	# the wall - not the collision box, which is often a different shape.
	var pos := _inset_from_walls(center, tex_size)
	body.position = pos
	# A soft shadow under every prop, added first so it draws beneath the sprite.
	# Flat sprites on a flat floor are what made the interiors read as pictures
	# pasted onto the screen; a shadow is what makes them look placed on it.
	var shadow := Sprite2D.new()
	shadow.texture = _make_shadow()
	shadow.position = Vector2(2.0, shape_size.y * 0.16)
	shadow.scale = Vector2(shape_size.x / 64.0 * 0.95, shape_size.y / 64.0 * 0.55)
	body.add_child(shadow)
	# Mirror every other prop, so a long row of identical fittings stops reading
	# as one stamped copy.
	spr.flip_h = (int(pos.x) + int(pos.y)) % 2 == 0
	body.add_child(spr)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = shape_size
	cs.shape = shape
	body.add_child(cs)
	_placed_props.append(Rect2(pos - shape_size * 0.5, shape_size))
	objects.add_child(body)


func _place_lights() -> void:
	var corridor_spots := [
		Vector2(352, 528), Vector2(1024, 528), Vector2(1664, 528),
		Vector2(720, 992), Vector2(1024, 992), Vector2(1360, 992),
		Vector2(352, 1472), Vector2(1024, 1472), Vector2(1664, 1472),
		Vector2(720, 240), Vector2(1360, 240),
	]
	for pos in corridor_spots:
		_make_light(pos, 1.95, 0.42, 0.012, Color(0.85, 0.9, 1.0))

	for room_name in rooms:
		if room_name == "Main Atrium":
			continue
		var r: Rect2i = rooms[room_name]
		var c := Vector2i(r.position.x + int(r.size.x * 0.5), r.position.y + int(r.size.y * 0.5))
		_make_light(cell_center(c), 2.5, 0.34, 0.008, Color(0.9, 0.88, 0.82))

	_make_light(cell_center(Vector2i(28, 24)), 2.2, 0.34, 0.008, Color(0.9, 0.88, 0.82))
	_make_light(cell_center(Vector2i(36, 24)), 2.2, 0.34, 0.008, Color(0.9, 0.88, 0.82))


func _make_light(pos: Vector2, light_scale: float, energy: float, blackout: float, tint: Color) -> void:
	var light := FlickerLight.new()
	light.texture = load("res://assets/generated/light_glow.png")
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	light.texture_scale = light_scale
	light.color = tint
	light.base_energy = energy
	light.blackout_chance = blackout
	light.position = pos
	objects.add_child(light)


func _place_doors() -> void:
	var door_positions := [
		Vector2(288, 592), Vector2(288, 1072), Vector2(288, 1552), Vector2(1728, 1072),
	]
	for pos in door_positions:
		var door := DOOR_SCENE.instantiate()
		door.position = pos
		objects.add_child(door)


func _place_sliding_doors() -> void:
	var spots := [
		Vector2(288, 464), Vector2(1056, 464), Vector2(1728, 464),
		Vector2(1056, 592), Vector2(1728, 592),
		Vector2(1056, 1072),
		Vector2(1056, 1552), Vector2(1728, 1552),
		Vector2(1056, 944),
	]
	for pos in spots:
		var d := SLIDING_DOOR_SCENE.instantiate()
		d.position = pos
		objects.add_child(d)


func _place_furniture_extra() -> void:
	# --- Techworld -------------------------------------------------------
	_put("shelf", Vector2i(10, 4), Vector2(44, 28))
	_put("shelf", Vector2i(13, 4), Vector2(44, 28))
	_put("prop_kiosk", Vector2i(4, 10), Vector2(44, 26))
	_put("prop_bin", Vector2i(2, 6), Vector2(20, 20))
	_put("shelf", Vector2i(15, 8), Vector2(44, 28))

	# --- Game Zone -------------------------------------------------------
	_put("shelf", Vector2i(36, 7), Vector2(44, 28))
	_put("prop_bin", Vector2i(27, 12), Vector2(20, 20))
	_put("prop_plant", Vector2i(37, 2), Vector2(26, 26))

	# --- Fashion Hub -----------------------------------------------------
	_put("mannequin", Vector2i(60, 8), Vector2(22, 30))
	_put("mannequin", Vector2i(60, 10), Vector2(22, 30))
	_put("prop_bin", Vector2i(46, 12), Vector2(20, 20))
	_put("prop_rack", Vector2i(59, 4), Vector2(60, 26))

	# --- Books & More ----------------------------------------------------
	_put("prop_bookcase", Vector2i(6, 27), Vector2(60, 26))
	_put("prop_bin", Vector2i(17, 20), Vector2(20, 20))
	_put("prop_bookcase", Vector2i(13, 24), Vector2(60, 26))

	# --- Main Atrium -----------------------------------------------------
	_put("prop_kiosk", Vector2i(29, 24), Vector2(44, 26))
	_put("prop_sofa", Vector2i(35, 26), Vector2(58, 26))
	_put("prop_plant", Vector2i(27, 22), Vector2(26, 26))
	_put("prop_plant", Vector2i(37, 22), Vector2(26, 26))
	_put("prop_bin", Vector2i(26, 27), Vector2(20, 20))

	# --- Beauty Co. ------------------------------------------------------
	_put("shelf", Vector2i(52, 27), Vector2(44, 28))
	_put("prop_bin", Vector2i(46, 20), Vector2(20, 20))
	_put("shelf", Vector2i(59, 25), Vector2(44, 28))

	# --- Coffee Shop -----------------------------------------------------
	_put("prop_sofa", Vector2i(15, 36), Vector2(58, 26))
	_put("prop_bin", Vector2i(2, 43), Vector2(20, 20))
	_put("prop_foodtable", Vector2i(16, 40), Vector2(58, 58))

	# --- Food Court ------------------------------------------------------
	_put("prop_kiosk", Vector2i(29, 34), Vector2(44, 26))
	_put("prop_bin", Vector2i(26, 43), Vector2(20, 20))
	_put("prop_plant", Vector2i(36, 34), Vector2(26, 26))

	# --- Sports Zone -----------------------------------------------------
	_put("prop_sportsrack", Vector2i(57, 40), Vector2(44, 26))
	_put("prop_bin", Vector2i(46, 43), Vector2(20, 20))
	_put("prop_plant", Vector2i(60, 43), Vector2(26, 26))

	# --- Storage Room ----------------------------------------------------
	_put("prop_crate", Vector2i(12, 51), Vector2(28, 26))
	_put("prop_crate", Vector2i(12, 54), Vector2(28, 26))
	_put("prop_crate", Vector2i(15, 54), Vector2(28, 26))
	_put("prop_bin", Vector2i(17, 54), Vector2(20, 20))

	# --- Security Office -------------------------------------------------
	_put("prop_locker", Vector2i(37, 55), Vector2(44, 26))
	_put("prop_sofa", Vector2i(29, 56), Vector2(58, 26))
	_put("prop_bin", Vector2i(37, 49), Vector2(20, 20))
	_put("prop_locker", Vector2i(36, 49), Vector2(44, 26))

	# --- Restrooms -------------------------------------------------------
	_put("prop_sink", Vector2i(48, 51), Vector2(58, 22))
	_put("prop_sink", Vector2i(48, 54), Vector2(58, 22))
	_put("prop_bin", Vector2i(59, 56), Vector2(20, 20))

	# --- Corridors -------------------------------------------------------
	# Was at cell (9, 17), which is directly in the mouth of the doorway at (8, 18):
# walking into Books & More you hit it. Moved clear of the threshold.
	_put("prop_bin", Vector2i(12, 16), Vector2(20, 20))
	_put("prop_bin", Vector2i(56, 17), Vector2(20, 20))
	_put("prop_sofa", Vector2i(31, 16), Vector2(58, 26))
	_put("prop_bin", Vector2i(30, 32), Vector2(20, 20))
	_put("prop_sofa", Vector2i(31, 46), Vector2(58, 26))
	_put("prop_bin", Vector2i(12, 32), Vector2(20, 20))


## A second furnishing pass so no shop reads as an empty box.
func _place_furniture_dense() -> void:
	# --- Techworld -------------------------------------------------------
	_put("shelf", Vector2i(6, 6), Vector2(44, 28))
	_put("shelf", Vector2i(7, 11), Vector2(44, 28))
	_put("prop_kiosk", Vector2i(16, 11), Vector2(44, 26))
	_put("prop_bin", Vector2i(18, 11), Vector2(20, 20))

	# --- Game Zone -------------------------------------------------------
	_put("shelf", Vector2i(28, 4), Vector2(44, 28))
	_put("shelf", Vector2i(32, 4), Vector2(44, 28))
	_put("shelf", Vector2i(35, 10), Vector2(44, 28))
	_put("prop_kiosk", Vector2i(27, 9), Vector2(44, 26))

	# --- Fashion Hub -----------------------------------------------------
	_put("prop_rack", Vector2i(48, 8), Vector2(60, 26))
	_put("prop_rack", Vector2i(50, 11), Vector2(60, 26))
	_put("prop_rack", Vector2i(57, 7), Vector2(60, 26))
	_put("mannequin", Vector2i(58, 12), Vector2(22, 30))

	# --- Books & More ----------------------------------------------------
	_put("prop_bookcase", Vector2i(4, 21), Vector2(60, 26))
	_put("prop_bookcase", Vector2i(5, 25), Vector2(60, 26))
	_put("prop_bookcase", Vector2i(16, 21), Vector2(60, 26))
	_put("prop_bookcase", Vector2i(15, 26), Vector2(60, 26))
	_put("prop_sofa", Vector2i(10, 27), Vector2(58, 26))

	# --- Main Atrium -----------------------------------------------------
	_put("prop_plant", Vector2i(29, 27), Vector2(26, 26))
	_put("prop_bench", Vector2i(28, 21), Vector2(58, 26))
	_put("prop_kiosk", Vector2i(38, 24), Vector2(44, 26))

	# --- Beauty Co. ------------------------------------------------------
	_put("shelf", Vector2i(48, 22), Vector2(44, 28))
	_put("shelf", Vector2i(53, 25), Vector2(44, 28))
	_put("prop_kiosk", Vector2i(58, 21), Vector2(44, 26))
	_put("prop_plant", Vector2i(60, 28), Vector2(26, 26))

	# --- Coffee Shop -----------------------------------------------------
	_put("prop_foodtable", Vector2i(6, 37), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(12, 37), Vector2(58, 58))
	_put("prop_kiosk", Vector2i(17, 36), Vector2(44, 26))
	_put("prop_plant", Vector2i(2, 35), Vector2(26, 26))

	# --- Food Court ------------------------------------------------------
	_put("prop_foodtable", Vector2i(29, 37), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(35, 40), Vector2(58, 58))
	_put("prop_kiosk", Vector2i(27, 41), Vector2(44, 26))
	_put("prop_bin", Vector2i(38, 34), Vector2(20, 20))

	# --- Sports Zone -----------------------------------------------------
	_put("prop_sportsrack", Vector2i(49, 38), Vector2(44, 26))
	_put("prop_sportsrack", Vector2i(53, 42), Vector2(44, 26))
	_put("shelf", Vector2i(58, 36), Vector2(44, 28))
	_put("prop_kiosk", Vector2i(46, 35), Vector2(44, 26))

	# --- Storage Room ----------------------------------------------------
	_put("prop_crate", Vector2i(4, 51), Vector2(28, 26))
	_put("prop_crate", Vector2i(7, 53), Vector2(28, 26))
	_put("prop_crate", Vector2i(10, 55), Vector2(28, 26))
	_put("shelf", Vector2i(15, 50), Vector2(44, 28))
	_put("prop_locker", Vector2i(5, 55), Vector2(44, 26))

	# --- Security Office -------------------------------------------------
	_put("prop_locker", Vector2i(27, 50), Vector2(44, 26))
	_put("prop_locker", Vector2i(28, 50), Vector2(44, 26))
	_put("prop_plant", Vector2i(38, 55), Vector2(26, 26))
	_put("prop_bin", Vector2i(26, 55), Vector2(20, 20))

	# --- Restrooms -------------------------------------------------------
	_put("prop_sink", Vector2i(49, 53), Vector2(58, 22))
	_put("prop_sink", Vector2i(56, 54), Vector2(58, 22))
	_put("prop_plant", Vector2i(46, 56), Vector2(26, 26))

	# --- TOYBOX ----------------------------------------------------------
	# The doorway is the aisle at x 74-77, so everything sits clear of it.
	_put("prop_toystack", Vector2i(72, 4), Vector2(48, 32))
	_put("prop_toystack", Vector2i(78, 4), Vector2(48, 32))
	_put("prop_toystack", Vector2i(82, 4), Vector2(48, 32))
	_put("prop_rockinghorse", Vector2i(70, 7), Vector2(40, 32))
	_put("prop_dollhouse", Vector2i(84, 7), Vector2(40, 32))
	_put("prop_toystack", Vector2i(81, 10), Vector2(48, 32))
	_put("prop_plushbin", Vector2i(71, 10), Vector2(32, 28))
	_put("prop_plushbin", Vector2i(78, 11), Vector2(32, 28))
	_put("prop_counter", Vector2i(84, 12), Vector2(60, 26))
	_put("shelf", Vector2i(70, 2), Vector2(44, 28))
	_put("prop_plant", Vector2i(85, 2), Vector2(26, 26))

	# --- CINEMA ----------------------------------------------------------
	for x in [71, 77, 83]:
		_put("prop_bench", Vector2i(x, 23), Vector2(60, 20))
		_put("prop_bench", Vector2i(x, 26), Vector2(60, 20))
	_put("prop_counter", Vector2i(69, 20), Vector2(60, 26))
	_put("prop_plant", Vector2i(85, 20), Vector2(26, 26))
	_put("prop_bin", Vector2i(85, 28), Vector2(20, 20))


func _place_inspectables() -> void:
	_put_inspectable(Vector2i(33, 54), "Read the duty log",
		"Night log, 9:58 PM — 'Mannequins in Fashion Hub were moved again. Maintenance says it wasn't them.'")
	_put_inspectable(Vector2i(10, 6), "Check the display",
		"Every television shows the same empty hallway. It is not a hallway in this building.")
	_put_inspectable(Vector2i(30, 6), "Try the cabinet",
		"The cabinet is warm. The high score is still being typed, one digit at a time.")
	_put_inspectable(Vector2i(48, 6), "Look through the racks",
		"Forty identical coats. The last one is still warm.")
	_put_inspectable(Vector2i(50, 4), "Check the display figure",
		"Its hands are warm. Maintenance has reset this display twice this week.")
	_put_inspectable(Vector2i(5, 23), "Read a book",
		"Every bookmark in this shop is on the same page.")
	_put_inspectable(Vector2i(28, 37), "Open the register",
		"The till is full of folded paper. They are all notes to the morning shift.")
	_put_inspectable(Vector2i(16, 53), "Search the machine",
		"The vending machine is empty and unplugged. Something inside takes a coin anyway.")
	_put_inspectable(Vector2i(35, 25), "Look into the fountain",
		"Coins at the bottom. And one shape down there that is not a coin.")


func _put_inspectable(cell: Vector2i, prompt: String, message: String) -> void:
	var node := Inspectable.new()
	node.position = cell_center(cell)
	node.prompt_string = prompt
	node.message = message
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(44, 40)
	cs.shape = shape
	node.add_child(cs)
	objects.add_child(node)


func _place_terminal() -> void:
	var terminal := TERMINAL_SCENE.instantiate()
	terminal.position = Vector2(1168, 1648)
	objects.add_child(terminal)
	terminal.activated.connect(_on_terminal_used)
	add_to_group("terminal_host")


func _on_terminal_used() -> void:
	Game.set_flag("used_cameras")
	var cam := get_tree().get_first_node_in_group("camera_interface")
	if cam != null:
		cam.open()


func _place_room_triggers() -> void:
	for room_name in rooms:
		var rect := room_rect_world(room_name)
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = rect.position + rect.size * 0.5
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(_on_room_entered.bind(room_name))
		objects.add_child(area)


func _on_room_entered(_body: Node, room_name: String) -> void:
	hud.show_location(room_name)


## Cabinets, drawers and lockers. Only a handful hold a cell, and you have to
## stand still and go through them to find out which.
func _place_searchables() -> void:
	var spots := [
		# The office supply cabinet is the one guaranteed source, so a player who
		# burns every other cell can still recover.
		{"cell": Vector2i(35, 56), "tex": "prop_locker", "size": Vector2(44, 30),
			"loot": "battery", "what": "supply cabinet", "respawn": true},
		{"cell": Vector2i(17, 53), "tex": "prop_toolchest", "size": Vector2(34, 26),
			"loot": "battery", "what": "tool chest"},
		{"cell": Vector2i(34, 43), "tex": "prop_crate", "size": Vector2(32, 26),
			"loot": "battery", "what": "delivery crate"},
		{"cell": Vector2i(70, 12), "tex": "prop_crate", "size": Vector2(32, 26),
			"loot": "battery", "what": "toy crate"},
		{"cell": Vector2i(18, 4), "tex": "prop_locker", "size": Vector2(44, 30),
			"loot": "note:The breaker for the east wing keeps tripping. The label fell off years ago.",
			"what": "wall locker"},
		{"cell": Vector2i(3, 20), "tex": "prop_toolchest", "size": Vector2(34, 26),
			"loot": "note:'THEY COME TWICE. THE SECOND TIME THEY DO NOT STOP.'",
			"what": "returns drawer"},
		{"cell": Vector2i(46, 4), "tex": "prop_locker", "size": Vector2(44, 30),
			"loot": "note:Every mannequin in this store has been re-dressed. I did not do it.",
			"what": "staff locker"},
		{"cell": Vector2i(46, 25), "tex": "prop_toolchest", "size": Vector2(34, 26),
			"loot": "empty", "what": "cosmetics drawer"},
		{"cell": Vector2i(4, 42), "tex": "prop_crate", "size": Vector2(32, 26),
			"loot": "empty", "what": "dry store crate"},
		{"cell": Vector2i(59, 50), "tex": "prop_locker", "size": Vector2(44, 30),
			"loot": "empty", "what": "cleaning locker"},
		{"cell": Vector2i(74, 28), "tex": "prop_toolchest", "size": Vector2(34, 26),
			"loot": "empty", "what": "projection drawer"},
	]
	for entry in spots:
		var node := SEARCHABLE_SCENE.instantiate()
		node.position = cell_center(entry["cell"])
		node.setup("res://assets/generated/%s.png" % entry["tex"], entry["loot"],
			entry["what"], entry.get("respawn", false))
		var spr: Sprite2D = node.get_node("Sprite")
		if spr != null:
			var size: Vector2 = entry["size"]
			var tex := load("res://assets/generated/%s.png" % entry["tex"]) as Texture2D
			if tex != null:
				spr.scale = Vector2(size.x / tex.get_size().x, size.y / tex.get_size().y)
		objects.add_child(node)


func _place_breaker() -> void:
	var breaker := BREAKER_SCENE.instantiate()
	breaker.position = Vector2(3 * TILE + 16, 53 * TILE + 16)
	objects.add_child(breaker)


func _place_service_door() -> void:
	var door := SERVICE_DOOR_SCENE.instantiate()
	# Set into the corridor wall a few steps north of the security office, so the
	# first task of the shift is right on the guard's doorstep.
	door.position = Vector2(32 * TILE + 16, 45 * TILE + 8)
	objects.add_child(door)


## Readable shop signage so the player can name a place and remember a route.
func _place_signs() -> void:
	var signs := [
		{"cell": Vector2i(32, 22), "text": "RIVERVIEW MALL", "size": 17},
		{"cell": Vector2i(9, 12), "text": "TECHWORLD", "size": 13},
		{"cell": Vector2i(33, 12), "text": "GAME ZONE", "size": 13},
		{"cell": Vector2i(54, 12), "text": "FASHION HUB", "size": 13},
		{"cell": Vector2i(10, 20), "text": "BOOKS & MORE", "size": 13},
		{"cell": Vector2i(54, 20), "text": "BEAUTY CO.", "size": 13},
		{"cell": Vector2i(10, 35), "text": "COFFEE SHOP", "size": 13},
		{"cell": Vector2i(34, 35), "text": "FOOD COURT", "size": 13},
		{"cell": Vector2i(56, 35), "text": "SPORTS ZONE", "size": 13},
		{"cell": Vector2i(11, 50), "text": "STORAGE", "size": 13},
		{"cell": Vector2i(34, 50), "text": "SECURITY OFFICE", "size": 13},
		{"cell": Vector2i(55, 50), "text": "RESTROOMS", "size": 13},
		{"cell": Vector2i(32, 58), "text": "MAIN ENTRANCE", "size": 14, "color": Color(0.7, 0.85, 0.95)},
		{"cell": Vector2i(6, 46), "text": "SERVICE CORRIDOR", "size": 12, "color": Color(0.6, 0.75, 0.78)},
		{"cell": Vector2i(32, 31), "text": "MAIN HALLWAY", "size": 12, "color": Color(0.6, 0.75, 0.78)},
		{"cell": Vector2i(74, 12), "text": "TOYBOX", "size": 15},
		{"cell": Vector2i(74, 20), "text": "CINEMA", "size": 14, "color": Color(0.62, 0.72, 0.85)},
	]
	for entry in signs:
		_put_sign(entry["cell"], entry["text"], entry.get("size", 13), entry.get("color", Color(0.92, 0.86, 0.62)))


## The board behind a room name: a dark plate with a worn brass edge.
func _sign_plate() -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.07, 0.08, 0.11, 0.88)
	plate.border_color = Color(0.38, 0.34, 0.25, 0.95)
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 12.0
	plate.content_margin_right = 12.0
	plate.content_margin_top = 4.0
	plate.content_margin_bottom = 4.0
	return plate


func _put_sign(cell: Vector2i, text: String, font_size: int, tint: Color) -> void:
	var holder := Node2D.new()
	holder.position = cell_center(cell)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.05, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	# Room names were bare text dropped in the middle of the floor. With nothing
	# holding them they read as leftover debug labels draped over the rooms, and
	# they collided with the HUD's own waypoint text. A backing plate makes them
	# read as mall signage instead.
	label.add_theme_stylebox_override("normal", _sign_plate())
	holder.add_child(label)
	# Hug the words rather than spanning a fixed 220px box, then centre the plate
	# on the sign's position.
	label.reset_size()
	label.position = -label.size * 0.5
	objects.add_child(holder)


## True when a point sits on real floor, so restoring a save can never drop the
## player inside a wall.
func is_walkable(point: Vector2) -> bool:
	for room_name in rooms:
		if room_rect_world(room_name).has_point(point):
			return true
	for c in corridors:
		var rect := Rect2(Vector2(c.position.x * TILE, c.position.y * TILE), Vector2(c.size.x * TILE, c.size.y * TILE))
		if rect.has_point(point):
			return true
	return false


func _setup_player() -> void:
	if Game.has_pending_position and is_walkable(Game.pending_player_position):
		player.global_position = Game.pending_player_position
	else:
		player.global_position = cell_center(PLAYER_SPAWN)
	Game.has_pending_position = false
	var cam: Camera2D = player.get_node("Camera")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = MAP_W * TILE
	cam.limit_bottom = MAP_H * TILE
	cam.make_current()