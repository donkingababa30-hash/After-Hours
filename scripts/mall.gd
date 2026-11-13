class_name Mall
extends Node2D
## Builds RIVERVIEW MALL at runtime: floor, walls, props, lights,
## room name triggers and the player. Also wires up the encounter manager.

const TILE := 32
const MAP_W := 88
## 65, not 62: the mall's front doors need a vestibule beyond them, or the main
## entrance is a sign on a dead-end corridor.
const MAP_H := 65

const SRC_FLOOR := 0
const SRC_CARPET := 1
## How many tiles of wall to draw around the walkable space.
const WALL_BORDER := 2

const PLAYER_SPAWN := Vector2i(32, 52)

const TERMINAL_SCENE := preload("res://scenes/objects/security_terminal.tscn")
const SLIDING_DOOR_SCENE := preload("res://scenes/objects/sliding_door.tscn")
const SERVICE_PANEL_SCENE := preload("res://scenes/objects/service_panel.tscn")
## Where the service door's control panel is mounted: on the same wall as the
## door, two tiles east of it. Close enough to read as its control, far enough
## that the two can never be mistaken for each other.
const SERVICE_PANEL_CELL := Vector2i(7, 48)
const SEARCHABLE_SCENE := preload("res://scenes/objects/searchable.tscn")
const BREAKER_SCENE := preload("res://scenes/objects/breaker.tscn")

## Walkable map data and the pathfinding grid built from it.
var map_grid: Array = []
var astar: AStarGrid2D = null

## What each cell IS: 0 wall, 1 corridor or doorway, 2 a public room, 3 back of
## house.
##
## map_grid only knows walkable from solid, which cannot answer the question the
## shopfronts need: "is this wall standing between a SHOP and a corridor?" A wall
## with a room on one side and another room on the other is a party wall and gets
## no glazing. A wall with a shop on one side and a corridor on the other is a
## storefront, and that is where the glass goes. Back-of-house space is a third
## kind because it faces corridors too, but a stockroom, a security office and the
## restrooms have solid walls rather than shop windows - glazing those as well made
## the whole building read as one uniform glass box instead of a mall with shops in
## it and services behind them.
const KIND_PUBLIC := 2
const KIND_BACK := 3
const NO_GLAZING := ["Storage Room", "Security Office", "Restrooms"]
var kind_grid: Array = []

## Every cell that belongs to an opening, keyed by cell. The glazing reads this to
## put a pier either side of every doorway.
var _opening_cells: Dictionary = {}

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
	## The mall's front doors, at the south end of the spine. Without it the sign
	## reading MAIN ENTRANCE pointed at a dead end with no entrance in it.
	"Entrance": Rect2i(24, 61, 16, 2),
}

## Which TileSet source each room floor uses.
## Which TileSet source each room floor uses. The whole set is deliberately in one
## cool blue-grey palette: the old set mixed a saturated brick-red carpet and a warm
## red argyle into a mall that is lit entirely blue, which is exactly what made the
## interiors read as mismatched assets. Source 0 is now proper polished tile, 1 and
## 2 are cool carpets, 3 is bare concrete for the back-of-house areas.
var room_floor := {
	"Techworld": 2, "Game Zone": 2, "Sports Zone": 2,
	"Fashion Hub": 1, "Books & More": 1, "Beauty Co.": 1, "Coffee Shop": 1,
	"Storage Room": 3,
	"Security Office": 0, "Food Court": 0, "Restrooms": 0,
	## The atrium and the entrance get their own floor. Every other room keeps its
	## own material too, but these two are the ones the player crosses from a
	## corridor, and a change of floor is what tells them they have arrived
	## somewhere rather than walked into another stretch of hallway.
	"Main Atrium": 2, "Entrance": 2,
	"TOYBOX": 1, "CINEMA": 1,
}

var corridors := [
	## Corridors 1 and 2 run on east past the vertical link to reach the doors of
	## the east wing. Anything shorter leaves the TOYBOX sealed off.
	Rect2i(2, 15, 77, 3),
	Rect2i(2, 30, 77, 3),
	Rect2i(2, 45, 63, 3),
	## The three north-south spines are five tiles wide.
	##
	## That width is not decoration: it is what leaves a ONE-TILE wall on either
	## side of them (x19/x25, x39/x45, x62/x68). At three tiles wide the gap out to
	## the rooms was two tiles, so every north-south wall in the building was
	## twice as thick as every east-west one and the mall read as assembled from
	## two different kits. Wall thickness is now uniform everywhere.
	##
	## The extra width also gives a corridor wall enough depth to stand a vending
	## machine against with 112 px of walkway still clear - which is why the
	## machines no longer need holes cut in the wall behind them.
	Rect2i(20, 2, 5, 58),
	Rect2i(40, 2, 5, 58),
	Rect2i(63, 2, 5, 58),
	Rect2i(21, 58, 23, 2),
]

## What kind of entrance belongs in an opening.
##
## The kind is chosen by the PURPOSE of the room behind the opening. It used to
## be decided by how wide the hole happened to be - a 2-tile hole got a roller
## shutter and a 4-tile hole got glass - which is why the bookshop had a garage
## door, the loading bay had a shopfront, and nine openings had nothing in them
## at all.
##
##   STOREFRONT  a public shop: glass panels that part as you walk up
##   OPEN        concourse and restrooms: a finished opening with no door leaf
##   STAFF       back of house: a solid closed door
##   SERVICE     the shift's service door, with its wire panel
const ENTRY_STOREFRONT := "storefront"
const ENTRY_OPEN := "open"
const ENTRY_STAFF := "staff"
const ENTRY_SERVICE := "service"


## Every opening in the mall's walls. An opening is cut for an architectural
## reason, and `entrance_kinds` installs exactly one entrance in each of them.
##
## The east-west walls carry wide openings, because a shopfront is four tiles.
## The north-south walls are one tile thick and their doorways run two tiles
## along the wall, so a side door is a normal door-width hole through a normal
## wall rather than a square pit two tiles deep.
var doorways := [
	# --- public shopfronts, off the corridors ----------------------------
	Rect2i(7, 14, 4, 1),     # Techworld
	Rect2i(31, 14, 4, 1),    # Game Zone
	Rect2i(52, 14, 4, 1),    # Fashion Hub
	Rect2i(7, 18, 4, 1),     # Books & More
	Rect2i(52, 18, 4, 1),    # Beauty Co.
	Rect2i(7, 33, 4, 1),     # Coffee Shop
	Rect2i(31, 33, 4, 1),    # Food Court
	Rect2i(52, 33, 4, 1),    # Sports Zone
	Rect2i(31, 44, 4, 1),    # Food Court, south
	Rect2i(74, 14, 4, 1),    # TOYBOX
	Rect2i(74, 18, 4, 1),    # CINEMA, north
	Rect2i(74, 29, 4, 1),    # CINEMA, south
	# --- open concourse and restroom doorways ----------------------------
	Rect2i(31, 18, 4, 1),    # Main Atrium, north
	Rect2i(31, 29, 4, 1),    # Main Atrium, south
	Rect2i(52, 48, 4, 1),    # Restrooms
	# --- staff and back-of-house doors -----------------------------------
	Rect2i(32, 48, 2, 1),    # Security Office
	Rect2i(19, 25, 1, 2),    # Books & More, east
	Rect2i(45, 25, 1, 2),    # Beauty Co., west
	Rect2i(25, 20, 1, 2),    # Main Atrium, west
	Rect2i(39, 20, 1, 2),    # Main Atrium, east
	Rect2i(25, 38, 1, 2),    # Coffee Shop, east
	Rect2i(39, 38, 1, 2),    # Food Court, west
	# --- the service door the shift opens on -----------------------------
	# At the WEST END of the service corridor, which is what the objective names.
	Rect2i(4, 48, 2, 1),     # Storage Room, service corridor west end
	## The Storage Room's way in that is NOT the door the shift seals.
	##
	## Until this existed the room's only opening was the service door, and the
	## first duty of every night is to SEAL that door - one way, by design. So the
	## act of completing duty one walled off the room that duty two happens in
	## (the west wing breaker is at cell (3,53), inside it), and the whole room
	## became unreachable for the rest of the run.
	Rect2i(13, 48, 2, 1),    # Storage Room, staff door off the corridor
	# --- the mall's front doors ------------------------------------------
	# Six tiles of glass, straight off the end of the main spine.
	Rect2i(29, 60, 6, 1),    # Main Entrance, to the vestibule
]


## The kind of entrance each opening carries, keyed by the opening's cell.
##
## Every entry in `doorways` must appear here. _place_entrances() reports any
## opening it finds without a kind instead of leaving it bare, which is how nine
## of these came to be plain holes in the wall.
var entrance_kinds := {
	Vector2i(7, 14): ENTRY_STOREFRONT,
	Vector2i(31, 14): ENTRY_STOREFRONT,
	Vector2i(52, 14): ENTRY_STOREFRONT,
	Vector2i(7, 18): ENTRY_STOREFRONT,
	Vector2i(52, 18): ENTRY_STOREFRONT,
	Vector2i(7, 33): ENTRY_STOREFRONT,
	Vector2i(31, 33): ENTRY_STOREFRONT,
	Vector2i(52, 33): ENTRY_STOREFRONT,
	Vector2i(31, 44): ENTRY_STOREFRONT,
	Vector2i(74, 14): ENTRY_STOREFRONT,
	Vector2i(74, 18): ENTRY_STOREFRONT,
	Vector2i(74, 29): ENTRY_STOREFRONT,
	Vector2i(31, 18): ENTRY_OPEN,
	Vector2i(31, 29): ENTRY_OPEN,
	Vector2i(52, 48): ENTRY_OPEN,
	Vector2i(32, 48): ENTRY_STAFF,
	Vector2i(19, 25): ENTRY_STAFF,
	Vector2i(45, 25): ENTRY_STAFF,
	Vector2i(25, 20): ENTRY_STAFF,
	Vector2i(39, 20): ENTRY_STAFF,
	Vector2i(25, 38): ENTRY_STAFF,
	Vector2i(39, 38): ENTRY_STAFF,
	Vector2i(4, 48): ENTRY_SERVICE,
	Vector2i(13, 48): ENTRY_STAFF,
	Vector2i(29, 60): ENTRY_STOREFRONT,
}

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
	_place_shopfronts()
	_place_wall_ads()
	_place_props()
	_place_furniture()
	_place_furniture_extra()
	_place_furniture_dense()
	_place_lights()
	_place_entrances()
	_place_service_panel()
	_place_inspectables()
	_place_terminal()
	_place_signs()
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


## The glazing between every shop and the corridor it opens onto.
##
## This is the single thing that makes the floor plan read as a mall rather than a
## set of boxes: a concourse lined with glass, with the shop signs and the lit
## interiors visible through it. It uses the SAME panel the automatic doors use,
## so a shopfront and the door set into it are one continuous run of glass, which
## is exactly how a real building is put together.
##
## Nothing is cut and nothing is moved. The glass is drawn on wall cells that are
## already there and the wall keeps its collision underneath, so this is a purely
## visual layer and cannot break a route. Doors are skipped automatically: a
## doorway is a hole in the plan, so its cell is floor, and floor is never a
## candidate for glazing.
func _place_shopfronts() -> void:
	var tex := load("res://assets/generated/door_glass.png") as Texture2D
	if tex == null or kind_grid.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "Shopfronts"
	objects.add_child(holder)
	for y in MAP_H:
		_glass_line(holder, tex, y, true)
	for x in MAP_W:
		_glass_line(holder, tex, x, false)


## Lays glass along every run of shopfront wall on one row (or one column).
##
## ONE panel per glazing cell, scaled to fill that cell exactly.
##
## The panel art is 64x24 with transparent margins, so laying one every other cell
## left strips of bare wall showing between them, and because the visible glass is
## narrower than the texture the panels read as rectangles of DIFFERENT widths
## depending on what happened to be next to them. That is the inconsistency this
## replaces. A panel is now exactly one tile and tiles seamlessly, so a shopfront
## is a continuous ribbon of glass with a mullion every tile.
##
## The piers that break the ribbon are placed either side of every DOORWAY, so they
## land where the architecture says they should. The previous rule was "a pier
## every third bay", which ignored where the doors were and put the breaks at
## arbitrary points along the wall.
func _glass_line(holder: Node2D, tex: Texture2D, line: int, horizontal: bool) -> void:
	var limit := MAP_W if horizontal else MAP_H
	var axis := 1 if horizontal else 2
	for i in limit:
		if _axis_at(line, i, horizontal) != axis:
			continue
		if _is_pier_cell(line, i, horizontal):
			continue
		var cell := Vector2i(i, line) if horizontal else Vector2i(line, i)
		var spr := Sprite2D.new()
		spr.texture = tex
		# Fill the cell on BOTH axes, so the ribbon has no gaps in it.
		spr.scale = Vector2(float(TILE) / tex.get_size().x, float(TILE) / tex.get_size().y)
		# A panel in a north-south wall has to lie along the wall.
		if not horizontal:
			spr.rotation = deg_to_rad(90.0)
		spr.position = cell_center(cell)
		holder.add_child(spr)


## True when a glazing cell must be left as solid wall instead: the cells
## immediately either side of a doorway. That is what frames each entrance and
## gives the frontages a rhythm tied to the building rather than to a count.
func _is_pier_cell(line: int, i: int, horizontal: bool) -> bool:
	for d in [-1, 1]:
		var j: int = i + d
		var cell := Vector2i(j, line) if horizontal else Vector2i(line, j)
		if _opening_cells.has(cell):
			return true
	return false


func _axis_at(line: int, i: int, horizontal: bool) -> int:
	return _shopfront_axis(i, line) if horizontal else _shopfront_axis(line, i)


## Which way the glazing runs on a wall cell, or 0 when the cell is not a
## storefront at all. 1 means the glass lies east-west, 2 means north-south.
func _shopfront_axis(x: int, y: int) -> int:
	if kind_grid.is_empty() or kind_grid[y][x] != 0:
		return 0
	var up: int = kind_grid[y - 1][x] if y > 0 else 0
	var down: int = kind_grid[y + 1][x] if y < MAP_H - 1 else 0
	var left: int = kind_grid[y][x - 1] if x > 0 else 0
	var right: int = kind_grid[y][x + 1] if x < MAP_W - 1 else 0
	if (up == KIND_PUBLIC and down == 1) or (up == 1 and down == KIND_PUBLIC):
		return 1
	if (left == KIND_PUBLIC and right == 1) or (left == 1 and right == KIND_PUBLIC):
		return 2
	return 0


## The direction a corridor lies in from a wall cell, or ZERO if none does.
func _corridor_side(x: int, y: int) -> Vector2i:
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H:
			continue
		if kind_grid[ny][nx] == 1:
			return d
	return Vector2i.ZERO


## Advertising and notice boards on the corridor walls.
##
## Placed only on wall cells that face a corridor and are NOT already glazed, so a
## board never lands on top of a shop window. Deliberately sparse - a wall covered
## end to end in boards stops reading as a wall, which is the "scattered props"
## problem in a different costume.
func _place_wall_ads() -> void:
	var tex := load("res://assets/generated/duty_board.png") as Texture2D
	if tex == null or kind_grid.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "WallAds"
	objects.add_child(holder)
	var n := 0
	for y in range(1, MAP_H - 1):
		for x in range(1, MAP_W - 1):
			if kind_grid[y][x] != 0 or _shopfront_axis(x, y) != 0:
				continue
			var side := _corridor_side(x, y)
			if side == Vector2i.ZERO:
				continue
			n += 1
			if n % 6 != 0:
				continue
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.modulate = Color(0.82, 0.84, 0.9)
			spr.position = cell_center(Vector2i(x, y))
			# A board lies ALONG the wall it hangs on, so one on a north-south wall
			# is turned a quarter turn rather than left sticking out of it.
			if side.x != 0:
				spr.rotation = deg_to_rad(90.0)
			holder.add_child(spr)


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

	# The same pass again, recording what each walkable cell belongs to. Doorways
	# count as corridor: a doorway is a passage, and a wall is never built beside
	# one that needs glazing.
	var kinds: Array = []
	for y in MAP_H:
		var krow := PackedInt32Array()
		krow.resize(MAP_W)
		krow.fill(0)
		kinds.append(krow)
	for c in corridors:
		_fill_kind(kinds, c, 1)
	for d in doorways:
		_fill_kind(kinds, d, 1)
	for room_name in rooms:
		var kind: int = KIND_BACK if NO_GLAZING.has(room_name) else KIND_PUBLIC
		_fill_kind(kinds, rooms[room_name], kind)
	kind_grid = kinds

	_opening_cells.clear()
	for d in doorways:
		for y in range(d.position.y, d.position.y + d.size.y):
			for x in range(d.position.x, d.position.x + d.size.x):
				_opening_cells[Vector2i(x, y)] = true

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
	_verify_reachability()


## Reports any room the guard cannot reach once the service door is sealed.
##
## This exists because it happened. The Storage Room's only opening WAS the service
## door, the first duty of every night seals that door one-way on purpose, and the
## room then held the second duty's breaker - with nothing able to reach it. A
## walk-in staff door is the fix; this is the tripwire that says so out loud, at
## build time, if another room ever ends up in that position.
##
## The service door is treated as shut for the whole walk, because that is what it
## will be for almost the entire shift.
func _verify_reachability() -> void:
	if map_grid.is_empty():
		return
	var sealed := {}
	for d in doorways:
		if entrance_kinds.get(d.position, "") != ENTRY_SERVICE:
			continue
		for y in range(d.position.y, d.position.y + d.size.y):
			for x in range(d.position.x, d.position.x + d.size.x):
				sealed[Vector2i(x, y)] = true
	var seen := {PLAYER_SPAWN: true}
	var frontier: Array[Vector2i] = [PLAYER_SPAWN]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= MAP_W or next.y >= MAP_H:
				continue
			if seen.has(next) or sealed.has(next) or map_grid[next.y][next.x] < 0:
				continue
			seen[next] = true
			frontier.push_back(next)
	for room_name in rooms:
		var r: Rect2i = rooms[room_name]
		var reached := false
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				if seen.has(Vector2i(x, y)):
					reached = true
					break
			if reached:
				break
		if not reached:
			push_error("_verify_reachability: %s has no way in once the service door is sealed" % room_name)


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


func _fill_kind(grid: Array, rect: Rect2i, value: int) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if y >= 0 and y < MAP_H and x >= 0 and x < MAP_W:
				grid[y][x] = value


func _place_props() -> void:
	_fountain_body = _add_solid(Vector2(1040, 752), "res://assets/generated/fountain.png", Vector2(74, 74))


## Furniture is placed by hand as cell coordinates across several passes, and two
## entries landing on the same tile is easy to do and ugly to look at: two sprites
## stack pixel-for-pixel. Anything that would substantially sit inside a prop
## already standing there is dropped instead of drawn.
## Every prop footprint placed so far this build. Tracked here rather than read
## back out of the scene tree: props are added while the mall is still assembling,
## so tree membership is not reliable yet.
var _placed_props: Array[Rect2] = []

## Every floor prop, keyed by the cell it was placed on. An examine prompt is
## attached to the body found here, so a prompt can only ever be attached to an
## object that is really standing in the room.
var _prop_by_cell: Dictionary = {}

## The fountain, kept so its prompt can hang off the real body.
var _fountain_body: StaticBody2D = null

## The service door, kept so its control panel can be wired to it.
var _service_door: MallDoor = null




## Texture names whose art on disk turned out wrong.
##
## prop_bin.png renders as a grey disc with a cross and radial ribs - a valve
## wheel, not a bin. The first attempt at fixing that pointed the alias at
## prop_wastebin.png, which is the SAME broken drawing under a second name, so
## every bin in the mall still read as machinery. Both names now resolve to a real
## top-down bin with a lid and a visible opening. Mapping here fixes every call
## site at once.
const TEX_ALIAS := {"prop_bin": "prop_trashcan", "prop_wastebin": "prop_trashcan"}

## The plant sprite was an indistinct dark splat with no pot, so a planter in the
## middle of a corridor did not read as a planter at all. Same aliasing trick.
const PLANT_TEX := "prop_planter"


## Art-palette correction. The prop set arrived in two clashing material families:
## a warm brown-wood half (shelf, bookcase, rack, bench, food table, sports rack,
## crate, tool chest, the toy-box fittings) and a cool steel/glass half (counter,
## locker, vending machine, arcade cabinet, TV wall). Mixed at random in a mall lit
## entirely blue, the two read as unrelated art dropped together - the single
## biggest reason the interiors looked assembled rather than designed. Multiplying
## just the warm half toward the cool palette unifies every room while leaving the
## silhouettes, the layout, and the two hero enemies' art completely untouched.
const WARM_TINT := Color(0.55, 0.72, 0.92)
const TEX_WARM := {
	"shelf": true, "prop_bookcase": true, "prop_rack": true,
	"prop_foodtable": true, "prop_foodtable_2": true, "prop_sportsrack": true,
	"prop_bench": true, "prop_kiosk": true, "prop_toolchest": true,
	"prop_toystack": true, "prop_rockinghorse": true, "prop_dollhouse": true,
	"prop_plushbin": true, "prop_crate": true, "prop_cabinet": true,
}


## Places a fixture. `rot` is degrees clockwise: a wall fitting has to be turned
## to face into the room it is mounted on rather than always facing the camera.
## `margin` is the walkable gap left between the sprite and the nearest wall -
## floor-standing props keep the default, wall-mounted fittings pass 0 and are
## placed one cell into their wall so _inset_from_walls snaps them flush.
func _put(tex: String, cell: Vector2i, box: Vector2, rot: float = 0.0, margin: float = WALL_MARGIN) -> StaticBody2D:
	var centre := cell_center(cell)
	if _prop_space_taken(_footprint(centre, box, rot)):
		return null
	var body := _add_solid(centre, "res://assets/generated/%s.png" % TEX_ALIAS.get(tex, tex), box, rot, margin)
	_prop_by_cell[cell] = body
	return body


## True when a rotation is a quarter turn, which swaps an object's width and
## height - it matters for collision spacing and how close it may sit to a wall.
func _is_quarter_turn(rot: float) -> bool:
	var a := fposmod(rot, 180.0)
	return a > 45.0 and a < 135.0


## The axis-aligned rectangle a box occupies once turned by `rot` degrees.
func _footprint(centre: Vector2, box: Vector2, rot: float) -> Rect2:
	var size := Vector2(box.y, box.x) if _is_quarter_turn(rot) else box
	return Rect2(centre - size * 0.5, size)


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
	# --- Techworld: an electronics shop ----------------------------------
	# Screen display walls on the back wall, boxed stock shelving on the side
	# walls, glass display counters on the floor, a demo table and the till by
	# the door. The door is at x7-10, so that lane is kept clear.
	_put("tech_screen_wall", Vector2i(6, 2), Vector2(92, 36), 0.0, 0.0)
	_put("tech_screen_wall", Vector2i(14, 2), Vector2(92, 36), 0.0, 0.0)
	_put("tech_shelf_v", Vector2i(2, 7), Vector2(36, 92), 0.0, 0.0)
	_put("tech_shelf_v", Vector2i(18, 7), Vector2(36, 92), 0.0, 0.0)
	_put("tech_counter", Vector2i(5, 6), Vector2(84, 36))
	_put("tech_counter", Vector2i(5, 10), Vector2(84, 36))
	_put("tech_table", Vector2i(12, 9), Vector2(68, 52))
	_put("shop_checkout", Vector2i(14, 12), Vector2(76, 36))
	_put("prop_plant", Vector2i(2, 12), Vector2(26, 26))

	# --- Game Zone: an arcade --------------------------------------------
	# Cabinets line the back wall and stand in a mid-floor row facing the
	# aisles, the change machine is mounted on the west wall and the prize
	# counter and claw machine sit by the door. The door is at x31-34, so that
	# lane is kept clear.
	for x in [27, 29, 31, 33, 35, 37]:
		_put("arcade_machine", Vector2i(x, 2), Vector2(30, 40), 0.0, 0.0)
	for x in [27, 29, 37]:
		_put("arcade_machine", Vector2i(x, 8), Vector2(30, 40))
	_put("arcade_change", Vector2i(26, 6), Vector2(32, 38), 270.0, 0.0)
	_put("arcade_claw", Vector2i(37, 11), Vector2(42, 42))
	_put("arcade_prize", Vector2i(29, 11), Vector2(84, 36))
	_put("prop_wastebin", Vector2i(26, 12), Vector2(24, 24))

	# --- Fashion Hub: a clothing shop ------------------------------------
	# Fitting rooms along the back wall, clothing racks either side of a clear
	# central aisle, mannequins by the door and the till beside the entrance.
	_put("fashion_fitting", Vector2i(49, 2), Vector2(58, 54), 0.0, 0.0)
	_put("fashion_fitting", Vector2i(53, 2), Vector2(58, 54), 0.0, 0.0)
	_put("fashion_fitting", Vector2i(57, 2), Vector2(58, 54), 0.0, 0.0)
	_put("fashion_table", Vector2i(47, 7), Vector2(62, 46))
	_put("prop_rack", Vector2i(49, 9), Vector2(62, 28))
	_put("prop_rack", Vector2i(59, 9), Vector2(62, 28))
	_put("prop_rack", Vector2i(49, 12), Vector2(62, 28))
	_put("prop_rack", Vector2i(59, 12), Vector2(62, 28))
	_put("mannequin", Vector2i(51, 12), Vector2(22, 30))
	_put("mannequin", Vector2i(56, 12), Vector2(22, 30))
	_put("shop_checkout", Vector2i(58, 6), Vector2(76, 36))
	_put("prop_plant", Vector2i(46, 2), Vector2(26, 26))

	# --- Books & More: a bookstore ---------------------------------------
	# Laid out as a shop, not a row of boxes. Shelving runs north-south with
	# walkways between the runs, display tables and a reading nook at the
	# front, and the checkout desk beside the door. The entrance is at x8-9,
	# so that lane is deliberately left clear.
	_put("book_shelf_h", Vector2i(5, 19), Vector2(92, 36), 0.0, 0.0)
	_put("book_checkout", Vector2i(14, 20), Vector2(76, 36))
	for x in [5, 9, 13]:
		_put("book_shelf_v", Vector2i(x, 24), Vector2(36, 92))
	_put("book_table", Vector2i(8, 27), Vector2(68, 52))
	_put("book_table", Vector2i(13, 27), Vector2(68, 52))
	_put("book_chair", Vector2i(3, 27), Vector2(36, 36))
	_put("prop_bin", Vector2i(17, 27), Vector2(20, 20))

	# --- Main Atrium: the concourse --------------------------------------
	# The one genuinely open room in the mall, so it is laid out as a PLAZA rather
	# than filled: a landmark at the centre with a clear ring of floor around it,
	# and everything else against a wall. Nothing is dropped into a walking line,
	# and no two sides of it are the same, so the player can tell where they are
	# standing from what is beside them.
	#
	#   north wall   the escalator bank, flanking the doorway to the corridor
	#   centre       the fountain (placed in _place_props)
	#   west wall    the mall directory, then a planter
	#   east wall    the information kiosk, then a vending machine
	#   south wall   two seating clusters, either side of the south doorway
	#
	# The escalators sit either side of the north doorway at x31-34 and stop short
	# of x26 and x38, so the two side doorways still open onto clear floor.
	_put("prop_escalator", Vector2i(29, 19), Vector2(92, 54), 0.0, 0.0)
	_put("prop_escalator", Vector2i(36, 19), Vector2(92, 54), 0.0, 0.0)
	_put("mall_directory", Vector2i(26, 23), Vector2(50, 34), 270.0, 0.0)
	_put("prop_plant", Vector2i(26, 26), Vector2(26, 26))
	_put("prop_kiosk", Vector2i(38, 23), Vector2(44, 26), 90.0, 0.0)
	_put("prop_vending", Vector2i(38, 26), Vector2(28, 40), 90.0, 0.0)
	_put("prop_bench", Vector2i(28, 28), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(36, 28), Vector2(60, 20), 0.0, 0.0)
	_put("prop_plant", Vector2i(26, 28), Vector2(26, 26))
	_put("prop_plant", Vector2i(38, 28), Vector2(26, 26))
	_put("prop_wastebin", Vector2i(37, 22), Vector2(24, 24))

	# --- Beauty Co.: a cosmetics shop ------------------------------------
	# Glass display counters on the shop floor, skincare shelving on the walls,
	# a consultation vanity and a display table, with the till by the door. The
	# main door is at x52-55 and a side door at y25-26 on the west wall; both
	# approach lanes are kept clear.
	_put("beauty_counter", Vector2i(49, 20), Vector2(84, 36))
	_put("beauty_checkout", Vector2i(58, 20), Vector2(76, 36))
	_put("beauty_shelf_v", Vector2i(60, 22), Vector2(36, 92))
	_put("beauty_shelf_v", Vector2i(60, 26), Vector2(36, 92))
	_put("beauty_shelf_v", Vector2i(47, 22), Vector2(36, 92))
	_put("beauty_counter", Vector2i(51, 23), Vector2(84, 36))
	_put("beauty_counter", Vector2i(56, 23), Vector2(84, 36))
	_put("beauty_stand", Vector2i(51, 26), Vector2(32, 32))
	_put("beauty_stand", Vector2i(56, 26), Vector2(32, 32))
	_put("beauty_table", Vector2i(53, 27), Vector2(68, 52))
	# Mounted on the east wall and turned to face into the shop, rather than
	# standing in the middle of the floor facing the camera. It sits in the gap
	# above the wall shelving: at y26 it was pushed by _inset_from_walls straight
	# into the shelf run and the two sprites drew on top of each other.
	_put("beauty_mirror", Vector2i(62, 19), Vector2(44, 44), 90.0, 0.0)
	_put("prop_plant", Vector2i(46, 20), Vector2(26, 26))

	# --- Coffee Shop: a cafe ---------------------------------------------
	# Service counter with the espresso machine, a pastry case beside it, and
	# tables and chairs on the floor. The door is at x8-9, so that lane stays
	# clear all the way in.
	_put("cafe_counter", Vector2i(14, 36), Vector2(94, 36))
	_put("cafe_pastry", Vector2i(14, 39), Vector2(54, 34))
	_put("prop_foodtable", Vector2i(4, 39), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(12, 41), Vector2(58, 58))
	# A pair of chairs at the counter, turned to FACE it (rot 180: the chair art
	# has its backrest at the top, so it looks south by default).
	#
	# The food tables carry their own four chairs in the artwork. The loose
	# cafe_chairs that used to sit beside them were duplicates standing on top of
	# the ones already drawn, which is what made the seating look wrong.
	_put("cafe_chair", Vector2i(13, 38), Vector2(26, 26), 180.0, 0.0)
	_put("cafe_chair", Vector2i(15, 38), Vector2(26, 26), 180.0, 0.0)
	# The sofa backs onto the south wall and faces into the cafe.
	_put("prop_sofa", Vector2i(6, 42), Vector2(58, 26), 180.0)
	_put("prop_plant", Vector2i(2, 35), Vector2(26, 26))
	_put("prop_wastebin", Vector2i(17, 43), Vector2(24, 24))

	# --- Food Court: a dining court --------------------------------------
	# Serving counters run along the back wall, tables fill the floor either
	# side of the middle aisle, and the tray return and condiment stand sit by
	# the seating. Doors at x31-34 (south) and x24-25 (west) stay clear.
	_put("court_counter", Vector2i(29, 34), Vector2(94, 36), 0.0, 0.0)
	_put("court_counter", Vector2i(36, 34), Vector2(94, 36), 0.0, 0.0)
	_put("prop_foodtable", Vector2i(28, 38), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(28, 41), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(36, 38), Vector2(58, 58))
	_put("prop_foodtable", Vector2i(36, 41), Vector2(58, 58))
	_put("court_condiment", Vector2i(38, 38), Vector2(34, 34))
	_put("court_tray", Vector2i(38, 43), Vector2(42, 34))
	_put("prop_wastebin", Vector2i(26, 43), Vector2(24, 24))
	_put("prop_plant", Vector2i(26, 34), Vector2(26, 26))

	# --- Sports Zone: a sports shop --------------------------------------
	# Shoe display wall across the back either side of the door, clothing racks
	# on the floor, ball bins and a fitting bench, and the till by the door.
	# The door is at x53-54, so that lane is kept clear.
	_put("sport_shoe_wall", Vector2i(49, 34), Vector2(92, 36), 0.0, 0.0)
	_put("sport_shoe_wall", Vector2i(58, 34), Vector2(92, 36), 0.0, 0.0)
	_put("prop_sportsrack", Vector2i(48, 38), Vector2(60, 26))
	_put("prop_sportsrack", Vector2i(48, 41), Vector2(60, 26))
	_put("prop_sportsrack", Vector2i(58, 38), Vector2(60, 26))
	_put("sport_ballbin", Vector2i(50, 41), Vector2(38, 38))
	_put("sport_ballbin", Vector2i(57, 39), Vector2(38, 38))
	_put("prop_bench", Vector2i(51, 43), Vector2(60, 20))
	_put("shop_checkout", Vector2i(58, 42), Vector2(76, 36))
	_put("prop_plant", Vector2i(46, 34), Vector2(26, 26))

	# --- Storage Room: back of house -------------------------------------
	# Steel pallet racking along the side walls, a rack against the back wall,
	# stacked crates on the floor, a vending machine and a staff locker. The
	# walk-in staff door is at x13-14 and the service door and its control panel
	# sit at x4-7, so both lanes stay clear.
	_put("stock_shelf_v", Vector2i(2, 51), Vector2(36, 92), 0.0, 0.0)
	_put("stock_shelf_v", Vector2i(18, 51), Vector2(36, 92), 0.0, 0.0)
	_put("stock_shelf_h", Vector2i(6, 49), Vector2(92, 36), 0.0, 0.0)
	_put("prop_crate", Vector2i(6, 53), Vector2(28, 26))
	_put("prop_crate", Vector2i(10, 53), Vector2(28, 26))
	_put("prop_crate", Vector2i(12, 51), Vector2(28, 26))
	_put("prop_crate", Vector2i(15, 53), Vector2(28, 26))
	_put("prop_vending", Vector2i(12, 55), Vector2(28, 40))
	_put("prop_locker", Vector2i(15, 55), Vector2(44, 26))

	# --- Security Office: the control room -------------------------------
	# The monitor desk is against the west wall facing into the room, staff
	# lockers line the east wall, and there is a couch and a coffee machine.
	# The door is at x31-34, so that lane and the camera terminal stay clear.
	_put("office_desk", Vector2i(26, 51), Vector2(84, 44), 270.0, 0.0)
	_put("prop_locker", Vector2i(38, 51), Vector2(44, 26), 90.0, 0.0)
	_put("prop_locker", Vector2i(38, 54), Vector2(44, 26), 90.0, 0.0)
	# The couch backs onto the south wall and faces into the room (rot 180), and
	# the bin sits beside the coffee machine the way it would in a real office.
	_put("prop_sofa", Vector2i(29, 56), Vector2(58, 26), 180.0)
	_put("prop_vending", Vector2i(36, 56), Vector2(28, 40))
	_put("prop_plant", Vector2i(26, 56), Vector2(26, 26))
	_put("prop_wastebin", Vector2i(37, 56), Vector2(24, 24))
	# The duty board the shift log keeps telling the guard to check. It used to
	# exist only as an invisible prompt zone, so there was nothing on the wall.
	_put("duty_board", Vector2i(28, 49), Vector2(64, 18), 0.0, 0.0)

	# --- Restrooms: a public washroom ------------------------------------
	# Every fitting is attached to the wall it belongs to and turned to face into
	# the room: basins with their mirror strips run along the north wall, the
	# urinals back onto the west wall, the stall bank backs onto the south wall
	# and the dryers are mounted on the east wall. Each is placed one cell into
	# its wall with no margin, so _inset_from_walls snaps it flush to the tiles.
	_put("wc_sink_row", Vector2i(49, 49), Vector2(100, 36), 0.0, 0.0)
	_put("wc_sink_row", Vector2i(58, 49), Vector2(100, 36), 0.0, 0.0)
	_put("wc_urinal", Vector2i(46, 52), Vector2(30, 38), 270.0, 0.0)
	_put("wc_urinal", Vector2i(46, 53), Vector2(30, 38), 270.0, 0.0)
	for x in [49, 51, 53, 55, 57]:
		_put("wc_stall", Vector2i(x, 56), Vector2(62, 62), 180.0, 0.0)
	_put("wc_dryer", Vector2i(62, 52), Vector2(24, 24), 90.0, 0.0)
	_put("wc_dryer", Vector2i(62, 53), Vector2(24, 24), 90.0, 0.0)
	_put("wc_cleaning", Vector2i(60, 51), Vector2(38, 34))
	_put("prop_wastebin", Vector2i(46, 56), Vector2(24, 24))

	# --- Corridors -------------------------------------------------------
	# Corridor walls carry only what genuinely belongs against a wall, and each
	# piece is turned so its usable face looks into the corridor rather than at
	# the camera. The five-tile spines have the depth for a vending machine
	# (48 px deep against a 160 px walkway, so 112 px stays clear); the three-tile
	# cross corridors only have room for a bench or a bin, and that is all they
	# carry. Nothing here needs a hole cut in the wall behind it.
	for y in [8, 22, 36]:
		_put("prop_vending", Vector2i(20, y), Vector2(28, 40), 270.0, 0.0)
	for y in [11, 27, 42]:
		_put("prop_wastebin", Vector2i(24, y), Vector2(28, 28), 0.0, 0.0)


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
func _inset_from_walls(center: Vector2, size: Vector2, margin: float = WALL_MARGIN) -> Vector2:
	var half := size * 0.5
	var pos := center
	const STEP := 6.0
	for side in [-1.0, 1.0]:
		var tries := 0
		while tries < 12 and not _walkable(Vector2(pos.x + side * (half.x + margin + 2.0), pos.y)):
			pos.x -= side * STEP
			tries += 1
	for side in [-1.0, 1.0]:
		var tries := 0
		while tries < 12 and not _walkable(Vector2(pos.x, pos.y + side * (half.y + margin + 2.0))):
			pos.y -= side * STEP
			tries += 1
	return pos


func _add_solid(center: Vector2, texture_path: String, shape_size: Vector2, rot: float = 0.0, margin: float = WALL_MARGIN) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var spr := Sprite2D.new()
	spr.texture = load(texture_path)
	# Cool the warm-wood half of the prop set into the mall's palette; see TEX_WARM.
	if TEX_WARM.has(texture_path.get_file().get_basename()):
		spr.modulate = WARM_TINT
	var tex_size: Vector2 = spr.texture.get_size()
	# The sprite is drawn at its native texture size, so it is the FOOTPRINT after
	# rotation that has to clear the wall - not the collision box, which is often a
	# different shape, and not the unrotated texture, which a quarter turn swaps.
	var footprint := Vector2(tex_size.y, tex_size.x) if _is_quarter_turn(rot) else tex_size
	var pos := _inset_from_walls(center, footprint, margin)
	body.position = pos
	# A soft shadow under every prop, added first so it draws beneath the sprite.
	# Flat sprites on a flat floor are what made the interiors read as pictures
	# pasted onto the screen; a shadow is what makes them look placed on it.
	var shadow := Sprite2D.new()
	shadow.texture = _make_shadow()
	shadow.position = Vector2(2.0, footprint.y * 0.16)
	shadow.scale = Vector2(footprint.x / 64.0 * 0.95, footprint.y / 64.0 * 0.55)
	body.add_child(shadow)
	# Mirror every other prop, so a long row of identical fittings stops reading
	# as one stamped copy. Skipped on turned props, where a mirror would flip the
	# direction the fitting faces.
	if not _is_quarter_turn(rot):
		spr.flip_h = (int(pos.x) + int(pos.y)) % 2 == 0
	spr.rotation = deg_to_rad(rot)
	body.add_child(spr)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = shape_size
	cs.shape = shape
	# The collision box turns with the sprite, so a fixture's solid area matches
	# the way it is actually standing rather than its unrotated outline.
	cs.rotation = deg_to_rad(rot)
	body.add_child(cs)
	_placed_props.append(_footprint(pos, shape_size, rot))
	objects.add_child(body)
	return body


func _place_lights() -> void:
	var corridor_spots := [
		Vector2(352, 528), Vector2(1024, 528), Vector2(1664, 528),
		Vector2(720, 992), Vector2(1024, 992), Vector2(1360, 992),
		Vector2(352, 1472), Vector2(1024, 1472), Vector2(1664, 1472),
		## The three north-south spines run the whole length of the building, and
		## they used to carry two lamps between them, both at the top - so most of
		## the mall's longest walkways were pitch dark, and the third spine had no
		## light at all. They are lit evenly now, down the centre of each one.
		Vector2(720, 240), Vector2(720, 816), Vector2(720, 1392), Vector2(720, 1808),
		Vector2(1360, 240), Vector2(1360, 816), Vector2(1360, 1392), Vector2(1360, 1808),
		Vector2(2096, 240), Vector2(2096, 816), Vector2(2096, 1392), Vector2(2096, 1808),
	]
	for pos in corridor_spots:
		_make_light(pos, 2.1, 0.40, 0.012, Color(0.85, 0.9, 1.0))

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


## Installs exactly one entrance in every opening in the mall.
##
## The kind comes from `entrance_kinds` and follows the purpose of the room, so
## the whole building speaks one design language: shopfronts are glass and part
## automatically, the concourse and the restrooms are finished open doorways,
## back-of-house doors are solid and shut, and the loading entrance is the one
## service door. An opening without a kind is reported, never left bare.
func _place_entrances() -> void:
	for rect in doorways:
		var kind: String = entrance_kinds.get(rect.position, "")
		if kind == "":
			push_error("_place_entrances: opening %s has no entrance kind" % rect)
			continue
		var span := Vector2(rect.size.x * TILE, rect.size.y * TILE)
		var at := Vector2(rect.position.x * TILE, rect.position.y * TILE) + span * 0.5
		# An opening in a north-south wall is taller than it is wide, so its
		# entrance is turned to sit along the wall rather than across it.
		var rot := 90.0 if rect.size.y >= rect.size.x else 0.0
		match kind:
			ENTRY_STOREFRONT:
				var glass := SLIDING_DOOR_SCENE.instantiate()
				glass.door_width = span.y if rot != 0.0 else span.x
				glass.position = at
				objects.add_child(glass)
			ENTRY_OPEN:
				_lay_entrance(at, span, rot, "res://assets/generated/door_frame_open.png")
			ENTRY_STAFF:
				# A REAL door: solid while it is shut, and it swings open on E.
				#
				# It used to be a drawn leaf with no collision at all, because the
				# game had no way to open a door - which is precisely the reported
				# "objects that look like doors can be walked straight through".
				var staff := MallDoor.new()
				staff.door_kind = "staff"
				staff.door_width = span.y if rot != 0.0 else span.x
				staff.rotation = deg_to_rad(rot)
				staff.position = at
				objects.add_child(staff)
			ENTRY_SERVICE:
				# The service door starts WEDGED OPEN and will not move until its
				# control panel beside it has been rerouted. It is its own object,
				# and the panel is a separate one: the door used to BE the puzzle,
				# so there was no sequence for the player to understand.
				var door := MallDoor.new()
				door.door_kind = "service"
				door.door_width = span.y if rot != 0.0 else span.x
				door.is_open = true
				door.locked = true
				door.locked_prompt = "Locked - door control is dead"
				door.locked_reason = "The door control is dead. Reroute the panel beside it."
				door.rotation = deg_to_rad(rot)
				door.position = at
				objects.add_child(door)
				_service_door = door


## The service door's control panel: a SEPARATE object, on the wall beside the
## door, and the thing the objective actually sends the player to first.
##
## The door and its control used to be one node, so there was no sequence to
## understand - you walked at a door and the game played a wire puzzle at you, and
## the report was that the objective never said which object to use. Now:
##
##   1. the panel is the puzzle, and it is an electrical cabinet, not a door
##   2. the door says out loud that it is waiting on the panel
##   3. rerouting the panel unlocks the door
##   4. sealing the door is a separate act, and that is what completes the duty
func _place_service_panel() -> void:
	if _service_door == null:
		push_error("_place_service_panel: there is no service door to control")
		return
	var panel := SERVICE_PANEL_SCENE.instantiate()
	panel.position = cell_center(SERVICE_PANEL_CELL)
	objects.add_child(panel)
	panel.rerouted.connect(_on_service_panel_rerouted)


func _on_service_panel_rerouted() -> void:
	if _service_door != null and is_instance_valid(_service_door):
		_service_door.unlock()


## Lays a door-width sprite along an opening, repeating it rather than stretching
## it, so a four-tile opening is two door-widths and not one smeared one.
##
## Used for ENTRY_OPEN, which is a finished opening with NO door leaf: a concourse
## or a restroom doorway. Anything that is meant to be a door the player operates
## is a MallDoor instead, because an opening with a drawn leaf and no collision is
## the mismatch this whole pass exists to remove.
func _lay_entrance(at: Vector2, span: Vector2, rot: float, tex_path: String) -> void:
	var tex := load(tex_path) as Texture2D
	if tex == null:
		push_error("_lay_entrance: missing texture %s" % tex_path)
		return
	var width := span.y if rot != 0.0 else span.x
	var piece := tex.get_size().x
	var count := maxi(1, int(round(width / piece)))
	var step := width / float(count)

	var holder := Node2D.new()
	holder.position = at
	holder.rotation = deg_to_rad(rot)
	objects.add_child(holder)
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = Vector2(-width * 0.5 + step * (float(i) + 0.5), 0.0)
		holder.add_child(spr)


func _place_furniture_extra() -> void:
	# --- Techworld: the shop is laid out in _place_furniture() -----------

	# --- Game Zone: the arcade is laid out in _place_furniture() ---------

	# --- Fashion Hub: the shop is laid out in _place_furniture() ---------

	# --- Books & More: the shop is laid out in _place_furniture() --------

	# --- Main Atrium: laid out as a plaza in _place_furniture() ----------

	# --- Beauty Co.: the shop is laid out in _place_furniture() ----------

	# --- Coffee Shop: the cafe is laid out in _place_furniture() ---------

	# --- Food Court: the court is laid out in _place_furniture() ---------

	# --- Sports Zone: the shop is laid out in _place_furniture() ---------

	# --- Storage Room: laid out in _place_furniture() --------------------

	# --- Security Office: laid out in _place_furniture() -----------------

	# --- Restrooms: the washroom is laid out in _place_furniture() -------

	# --- Corridors -------------------------------------------------------
	# Benches only, and every one of them flush against the wall (margin = 0) in
	# a stretch of wall with no doorway in it. The sofas and loose bins that used
	# to stand in the middle of these corridors have gone back into the rooms.
	_put("prop_bench", Vector2i(14, 15), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(38, 15), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(60, 15), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(14, 32), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(37, 32), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(60, 32), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(14, 45), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(37, 45), Vector2(60, 20), 0.0, 0.0)
	_put("prop_bench", Vector2i(58, 45), Vector2(60, 20), 0.0, 0.0)


## A second furnishing pass so no shop reads as an empty box.
func _place_furniture_dense() -> void:
	# --- Techworld: the shop is laid out in _place_furniture() -----------

	# --- Game Zone: the arcade is laid out in _place_furniture() ---------

	# --- Fashion Hub: the shop is laid out in _place_furniture() ---------

	# --- Books & More: the shop is laid out in _place_furniture() --------

	# --- Main Atrium: laid out as a plaza in _place_furniture() ----------

	# --- Beauty Co.: the shop is laid out in _place_furniture() ----------

	# --- Coffee Shop: the cafe is laid out in _place_furniture() ---------

	# --- Food Court: the court is laid out in _place_furniture() ---------

	# --- Sports Zone: the shop is laid out in _place_furniture() ---------

	# --- Storage Room: laid out in _place_furniture() --------------------

	# --- Security Office: laid out in _place_furniture() -----------------

	# --- Restrooms: the washroom is laid out in _place_furniture() -------

	# --- TOYBOX: a toy shop ----------------------------------------------
	# Toy shelving runs down the side wall, boxed stock and play pieces stand
	# on the floor, plush bins sit low, and the till is by the door. The
	# doorway is the aisle at x74-77, so everything sits clear of it.
	_put("toy_shelf_v", Vector2i(69, 5), Vector2(36, 92), 0.0, 0.0)
	_put("prop_toystack", Vector2i(72, 4), Vector2(48, 32))
	_put("prop_toystack", Vector2i(78, 4), Vector2(48, 32))
	_put("prop_toystack", Vector2i(82, 4), Vector2(48, 32))
	_put("prop_rockinghorse", Vector2i(70, 7), Vector2(40, 32))
	_put("prop_dollhouse", Vector2i(84, 7), Vector2(40, 32))
	_put("prop_toystack", Vector2i(81, 10), Vector2(48, 32))
	_put("prop_plushbin", Vector2i(71, 10), Vector2(32, 28))
	_put("prop_plushbin", Vector2i(78, 11), Vector2(32, 28))
	_put("shop_checkout", Vector2i(84, 12), Vector2(76, 36))
	_put("prop_plant", Vector2i(85, 2), Vector2(26, 26))

	# --- CINEMA: an auditorium -------------------------------------------
	# Screen across the front wall, banks of seats facing it with a centre
	# aisle, and the concession counter at the back beside the door. Doors are
	# at x74-77 on the north and south walls, so both lanes stay clear.
	_put("cinema_screen", Vector2i(80, 19), Vector2(108, 30), 0.0, 0.0)
	for y in [22, 24, 26]:
		_put("cinema_seat", Vector2i(72, y), Vector2(70, 30))
		_put("cinema_seat", Vector2i(82, y), Vector2(70, 30))
	_put("cinema_concession", Vector2i(79, 28), Vector2(94, 36))
	_put("prop_wastebin", Vector2i(85, 27), Vector2(24, 24))
	_put("prop_plant", Vector2i(69, 20), Vector2(26, 26))


## Examine prompts.
##
## Every prompt below is ATTACHED to a prop that is really standing in the room,
## as a child of that prop's own body. The prompt zone is therefore the object the
## player can see, and the two can never drift apart.
##
## They used to be bare Area2Ds dropped at hand-picked cells with no sprite at
## all: an invisible 44x40 trigger floating over the floor. Those cells did not
## line up with the props they described - "Try the cabinet" sat 71 px from the
## nearest arcade cabinet, and "Read the duty log" pointed at empty floor in an
## office that had no duty board in it. So the prompt lit up on a bare patch of
## corridor and vanished the moment the guard actually walked up to the cabinet.
## Nothing about the detection radius was ever wrong; the zone was simply in the
## wrong place. _attach_inspect fails loudly if the prop it is aimed at is absent.
func _place_inspectables() -> void:
	_attach_inspect(Vector2i(28, 49), "Read the duty log",
		"Night log, 9:58 PM — 'Mannequins in Fashion Hub were moved again. Maintenance says it wasn't them.'")
	_attach_inspect(Vector2i(6, 2), "Check the display",
		"Every television shows the same empty hallway. It is not a hallway in this building.")
	_attach_inspect(Vector2i(29, 8), "Try the cabinet",
		"The cabinet is warm. The high score is still being typed, one digit at a time.")
	_attach_inspect(Vector2i(49, 9), "Look through the racks",
		"Forty identical coats. The last one is still warm.")
	_attach_inspect(Vector2i(51, 12), "Check the display figure",
		"Its hands are warm. Maintenance has reset this display twice this week.")
	_attach_inspect(Vector2i(5, 24), "Read a book",
		"Every bookmark in this shop is on the same page.")
	_attach_inspect(Vector2i(29, 34), "Open the register",
		"The till is full of folded paper. They are all notes to the morning shift.")
	_attach_inspect(Vector2i(12, 55), "Search the machine",
		"The vending machine is empty and unplugged. Something inside takes a coin anyway.")
	_attach_inspect_to(_fountain_body, "Look into the fountain",
		"Coins at the bottom. And one shape down there that is not a coin.")


## Attaches an examine prompt to the prop standing on `cell`.
func _attach_inspect(cell: Vector2i, prompt: String, message: String, reach := 10.0) -> void:
	var body: StaticBody2D = _prop_by_cell.get(cell, null)
	if body == null:
		push_error("_attach_inspect: no prop at %s, so the prompt '%s' has nothing to attach to" % [cell, prompt])
		return
	_attach_inspect_to(body, prompt, message, reach)


## Attaches an examine prompt to a specific prop body.
func _attach_inspect_to(body: StaticBody2D, prompt: String, message: String, reach := 10.0) -> void:
	if body == null:
		push_error("_attach_inspect_to: no body for the prompt '%s'" % prompt)
		return
	var node := Inspectable.new()
	node.prompt_string = prompt
	node.message = message
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# The prop's own blocked rectangle, plus a short reach so the prompt is not
	# lost when the guard stands right against the side of a wide fitting.
	shape.size = _body_shape_size(body) + Vector2(reach, reach) * 2.0
	cs.shape = shape
	node.add_child(cs)
	body.add_child(node)


## The rectangle a prop actually blocks, read back from its own collision shape.
func _body_shape_size(body: StaticBody2D) -> Vector2:
	for child in body.get_children():
		if child is CollisionShape2D:
			var sh: Shape2D = (child as CollisionShape2D).shape
			if sh is RectangleShape2D:
				return (sh as RectangleShape2D).size
	return Vector2(40, 40)


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
		{"cell": Vector2i(4, 55), "tex": "prop_toolchest", "size": Vector2(34, 26),
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
		{"cell": Vector2i(60, 56), "tex": "prop_locker", "size": Vector2(44, 30),
			"loot": "empty", "what": "cleaning locker"},
		{"cell": Vector2i(70, 27), "tex": "prop_toolchest", "size": Vector2(34, 26),
			"loot": "empty", "what": "projection drawer"},
	]
	for entry in spots:
		var node := SEARCHABLE_SCENE.instantiate()
		var cell: Vector2i = entry["cell"]
		var tex_name := str(entry["tex"])
		var path := "res://assets/generated/%s.png" % TEX_ALIAS.get(tex_name, tex_name)
		var tex := load(path) as Texture2D
		node.position = cell_center(cell)
		node.setup(path, entry["loot"], entry["what"], entry.get("respawn", false))
		# Drawn at native size and collided at native size.
		#
		# The sprite used to be squashed to an arbitrary `size` from this table
		# while BOTH collision shapes stayed a fixed 46x36 box from the scene - so
		# a 34x26 tool chest blocked like a locker, and the guard came to a stop a
		# hand's width short of the thing he was walking up to. Shape and art now
		# come from the same texture, so what you see is what stops you.
		var native: Vector2 = tex.get_size() if tex != null else Vector2(46, 36)
		var spr: Sprite2D = node.get_node("Sprite")
		if spr != null and TEX_WARM.has(tex_name):
			spr.modulate = WARM_TINT
		_set_square_shapes(node, native)
		objects.add_child(node)


## Forces every collision shape under `root` to a rectangle of `size`.
func _set_square_shapes(root: Node, size: Vector2) -> void:
	for child in root.get_children():
		if child is CollisionShape2D:
			var sh := RectangleShape2D.new()
			sh.size = size
			(child as CollisionShape2D).shape = sh
		else:
			_set_square_shapes(child, size)


func _place_breaker() -> void:
	var breaker := BREAKER_SCENE.instantiate()
	breaker.position = Vector2(3 * TILE + 16, 53 * TILE + 16)
	objects.add_child(breaker)


## Readable shop signage so the player can name a place and remember a route.
func _place_signs() -> void:
	var signs := [
		# The mall's own name belongs over its front doors. It used to sit on the
		# atrium floor, directly on top of the fountain, which is one of the
		# landmark/label overlaps this pass exists to remove.
		{"cell": Vector2i(32, 61), "text": "RIVERVIEW MALL", "size": 17},
		{"cell": Vector2i(32, 26), "text": "MAIN ATRIUM", "size": 14},
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
		# Read on the way in: the guard walks east to west along this corridor, so
		# the label is passed before the door it names.
		{"cell": Vector2i(8, 47), "text": "SERVICE DOOR", "size": 12, "color": Color(0.95, 0.78, 0.45)},
		{"cell": Vector2i(32, 31), "text": "MAIN HALLWAY", "size": 12, "color": Color(0.6, 0.75, 0.78)},
		{"cell": Vector2i(74, 12), "text": "TOYBOX", "size": 15},
		{"cell": Vector2i(74, 20), "text": "CINEMA", "size": 14, "color": Color(0.62, 0.72, 0.85)},
	]
	for entry in signs:
		_put_sign(entry["cell"], entry["text"], entry.get("size", 13), entry.get("color", Color(0.92, 0.86, 0.62)))
	
	## Directional signs at corridor junctions - arrows pointing the way
	## to key locations (Security Office, exits, etc.)
	var dir_signs := [
		{"cell": Vector2i(21, 16), "text": "SECURITY OFFICE", "size": 11, "color": Color(0.8, 0.9, 0.95)},
		{"cell": Vector2i(21, 31), "text": "MAIN HALLWAY", "size": 11, "color": Color(0.8, 0.9, 0.95)},
		{"cell": Vector2i(21, 46), "text": "STORAGE ROOM", "size": 11, "color": Color(0.8, 0.9, 0.95)},
		{"cell": Vector2i(21, 59), "text": "EAST WING", "size": 11, "color": Color(0.8, 0.9, 0.95)},
		{"cell": Vector2i(67, 16), "text": "TOYBOX", "size": 11, "color": Color(0.8, 0.95, 0.8)},
		{"cell": Vector2i(67, 31), "text": "CINEMA", "size": 11, "color": Color(0.8, 0.95, 0.8)},
	]
	for entry in dir_signs:
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


## True when a world point is solid, for line-of-sight tests.
##
## This reads the same grid the A* pathing walks, so it knows about corridors as
## well as room interiors. is_walkable() below only knows about room rectangles
## and would report every corridor in the mall as a wall.
func blocks_sight(point: Vector2) -> bool:
	return not _walkable(point)


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