class_name Level
extends RefCounted
## The whole slice as one global tile grid. Rooms are JSON files under res://data/rooms/ with ASCII tiles;
## every room sits at its map cell, so walking between rooms needs no door or loading screen.
##
## Tile legend:
##   .  empty            #  ground (top piece when open above)   B  brick        Z  hazard-stripe block
##   =  one-way platform ^  spikes (hurt)                        %  hollow wall (breaks on the 3rd bat hit)
##   X  crate bulkhead (breaks on any bat hit)                    T  mitt target (a charged Mitt Cannon shot)
##   C  conduit shutter (opens when the room's mitt target is hit)
##   decor (not solid): w back wall, - pipe, | pipe, g grate, L light, v vine, P pillar, b brick backdrop
## Entity `at` is [column, row] inside the room: the tile the entity's feet stand in.

const SOLID := "#BZ%XTC"
const GATES := "%XTC"
const DECOR := "w-|gLvPb"
const LEGEND := ".#B=^%XTCZw-|gLvPb"
const DECOR_TILES := {"w": "back_wall", "-": "pipe_h", "|": "pipe_v", "g": "grate", "L": "light_panel", "v": "vine", "P": "pillar", "b": "brick"}

var rooms := {}
var cell_room := {}
var order: Array[String] = []


static func load_all(dir: String = "res://data/rooms") -> Level:
	var level := Level.new()
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [dir, file_name])
		var parser := JSON.new()
		if parser.parse(text) != OK:
			push_error("Level: %s is not valid JSON (%s)" % [file_name, parser.get_error_message()])
			continue
		level.add_room(parser.data)
	return level


func add_room(data: Dictionary) -> void:
	var room := {
		"id": String(data["id"]), "area": String(data["area"]),
		"cell": Vector2i(int(data["cell"][0]), int(data["cell"][1])),
		"size": Vector2i(int(data["size"][0]), int(data["size"][1])) if data.has("size") else Vector2i.ONE,
		"tiles": data["tiles"], "entities": data.get("entities", []),
		"title": String(data.get("title", "")),
	}
	rooms[room["id"]] = room
	order.append(room["id"])
	for cell in MapCells.cells_of(room["cell"], room["size"]):
		cell_room[cell] = room["id"]


func room(id: String) -> Dictionary:
	return rooms.get(id, {})


func room_at_cell(cell: Vector2i) -> Dictionary:
	return rooms.get(cell_room.get(cell, ""), {})


func room_at_pixel(pixel: Vector2) -> Dictionary:
	return room_at_cell(MapCells.cell_of(pixel))


func room_rect(room_data: Dictionary) -> Rect2:
	return MapCells.cell_rect(room_data["cell"], room_data["size"])


func room_tile_origin(room_data: Dictionary) -> Vector2i:
	return room_data["cell"] * Consts.CELL_TILES


func room_size_tiles(room_data: Dictionary) -> Vector2i:
	return room_data["size"] * Consts.CELL_TILES


## The tile character at a global tile coordinate, or "" outside every room.
func tile_at(global_tile: Vector2i) -> String:
	var cell := Vector2i(floori(global_tile.x / float(Consts.CELL_TILES.x)), floori(global_tile.y / float(Consts.CELL_TILES.y)))
	var room_data := room_at_cell(cell)
	if room_data.is_empty():
		return ""
	var local: Vector2i = global_tile - room_tile_origin(room_data)
	var rows: Array = room_data["tiles"]
	if local.y < 0 or local.y >= rows.size():
		return ""
	var row: String = rows[local.y]
	if local.x < 0 or local.x >= row.length():
		return ""
	return row[local.x]


func is_solid(global_tile: Vector2i) -> bool:
	var ch := tile_at(global_tile)
	return ch != "" and SOLID.contains(ch)


## World position (bottom-centre of the tile) for an entity's `at`.
func entity_position(room_data: Dictionary, at: Array) -> Vector2:
	var origin: Vector2i = room_tile_origin(room_data)
	return Vector2((origin.x + int(at[0])) * Consts.TILE + Consts.TILE / 2.0, (origin.y + int(at[1])) * Consts.TILE + Consts.TILE)


func total_cells() -> int:
	return cell_room.size()


## Schema problems that would break loading. Deeper design checks live in tools/level_tools.py.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var known_enemies := Db.enemies()
	for id: String in order:
		var r: Dictionary = rooms[id]
		var size_tiles := room_size_tiles(r)
		var rows: Array = r["tiles"]
		if rows.size() != size_tiles.y:
			problems.append("%s: %d rows, expected %d" % [id, rows.size(), size_tiles.y])
			continue
		for y in rows.size():
			var row: String = rows[y]
			if row.length() != size_tiles.x:
				problems.append("%s row %d: %d columns, expected %d" % [id, y, row.length(), size_tiles.x])
			for ch in row:
				if not LEGEND.contains(ch):
					problems.append("%s row %d: unknown tile '%s'" % [id, y, ch])
		if not Db.areas()["areas"].has(r["area"]):
			problems.append("%s: unknown area '%s'" % [id, r["area"]])
		for entity: Dictionary in r["entities"]:
			var at: Array = entity["at"]
			if int(at[0]) < 0 or int(at[0]) >= size_tiles.x or int(at[1]) < 0 or int(at[1]) >= size_tiles.y:
				problems.append("%s: %s at %s is outside the room" % [id, entity["type"], str(at)])
			if entity["type"] == "enemy" and not known_enemies.has(entity["id"]):
				problems.append("%s: unknown enemy '%s'" % [id, entity["id"]])
		var has_target := false
		var has_shutter := false
		for row: String in rows:
			has_target = has_target or row.contains("T")
			has_shutter = has_shutter or row.contains("C")
		if has_target != has_shutter:
			problems.append("%s: a mitt target needs a conduit shutter, and the other way round" % id)
	return problems
