extends TestCase
## Level model and collision merging on small synthetic rooms.


func _room(id: String, cell: Vector2i, marks: Dictionary, size: Vector2i = Vector2i.ONE, entities: Array = []) -> Dictionary:
	var rows: Array = []
	for _y in size.y * Consts.CELL_TILES.y:
		rows.append(".".repeat(size.x * Consts.CELL_TILES.x))
	for pos: Vector2i in marks:
		var row: String = rows[pos.y]
		rows[pos.y] = row.substr(0, pos.x) + String(marks[pos]) + row.substr(pos.x + 1)
	return {"id": id, "area": "crash", "cell": [cell.x, cell.y], "size": [size.x, size.y], "tiles": rows, "entities": entities}


func _level(rooms: Array) -> Level:
	var level := Level.new()
	for data: Dictionary in rooms:
		level.add_room(data)
	return level


func _fill(marks: Dictionary, rect: Rect2i, ch: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			marks[Vector2i(x, y)] = ch


func _covered(rects: Array, tile: Vector2i) -> int:
	var count := 0
	for rect: Rect2i in rects:
		if rect.has_point(tile):
			count += 1
	return count


func test_a_block_of_ground_becomes_one_rectangle() -> void:
	var marks := {}
	_fill(marks, Rect2i(5, 10, 3, 2), "#")
	var geometry := LevelGeometry.build(_level([_room("a", Vector2i.ZERO, marks)]))
	check(Rect2i(5, 10, 3, 2) in geometry["solids"], "3x2 block merges into a single rect")


func test_solids_cover_exactly_the_solid_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var marks := {}
	for _i in 400:
		marks[Vector2i(rng.randi_range(0, 39), rng.randi_range(0, 22))] = ["#", "B", "Z", "%", "X", "=", "^", "w"][rng.randi() % 8]
	var level := _level([_room("a", Vector2i.ZERO, marks)])
	var geometry := LevelGeometry.build(level)
	var bounds: Rect2i = geometry["bounds"]
	var mismatches := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			var ch := level.tile_at(tile)
			var want := 1 if (ch == "" or "#BZ".contains(ch)) else 0
			if _covered(geometry["solids"], tile) != want:
				mismatches += 1
	eq(mismatches, 0, "every static solid tile is covered exactly once, and nothing else is")


func test_the_outside_of_the_map_is_solid() -> void:
	var geometry := LevelGeometry.build(_level([_room("a", Vector2i.ZERO, {})]))
	check(_covered(geometry["solids"], Vector2i(-1, 5)) == 1, "left of the map")
	check(_covered(geometry["solids"], Vector2i(40, 5)) == 1, "right of the map")
	check(_covered(geometry["solids"], Vector2i(10, -1)) == 1, "above the map")
	check(_covered(geometry["solids"], Vector2i(10, 23)) == 1, "below the map")
	check(_covered(geometry["solids"], Vector2i(10, 10)) == 0, "the room itself is open")


func test_gates_group_by_connectivity() -> void:
	var marks := {}
	_fill(marks, Rect2i(3, 3, 2, 2), "%")
	_fill(marks, Rect2i(10, 3, 1, 3), "%")
	_fill(marks, Rect2i(20, 5, 2, 1), "X")
	marks[Vector2i(30, 4)] = "T"
	marks[Vector2i(30, 8)] = "C"
	marks[Vector2i(31, 8)] = "C"
	marks[Vector2i(35, 12)] = "C"
	var geometry := LevelGeometry.build(_level([_room("a", Vector2i.ZERO, marks)]))
	var kinds := {"%": 0, "X": 0, "C": 0}
	for gate: Dictionary in geometry["gates"]:
		kinds[gate["kind"]] += 1
		if gate["kind"] == "%" and gate["tiles"].size() == 4:
			eq(gate["key"], "a:%:3,3", "keys name the top-left tile")
	eq(kinds, {"%": 2, "X": 1, "C": 1}, "two hollow walls, one crate bulkhead, one shutter per room")
	for gate: Dictionary in geometry["gates"]:
		if gate["kind"] == "C":
			eq(gate["tiles"].size(), 3, "every conduit tile in the room belongs to the one shutter")
	eq(geometry["targets"].size(), 1)
	eq(geometry["targets"][0]["tile"], Vector2i(30, 4))
	check(not (Rect2i(3, 3, 2, 2) in geometry["solids"]), "gates are not part of the static collision")
	eq(_covered(geometry["solids"], Vector2i(3, 3)), 0)


func test_platform_and_spike_runs() -> void:
	var marks := {}
	_fill(marks, Rect2i(4, 8, 5, 1), "=")
	_fill(marks, Rect2i(20, 22, 3, 1), "^")
	var geometry := LevelGeometry.build(_level([_room("a", Vector2i.ZERO, marks)]))
	eq(geometry["platforms"], [Rect2i(4, 8, 5, 1)] as Array[Rect2i])
	eq(geometry["spikes"], [Rect2i(20, 22, 3, 1)] as Array[Rect2i])


func test_rooms_share_one_global_grid() -> void:
	var left := {}
	left[Vector2i(39, 10)] = "B"
	var right := {}
	right[Vector2i(0, 10)] = "#"
	var level := _level([_room("left", Vector2i(0, 0), left), _room("right", Vector2i(1, 0), right)])
	eq(level.tile_at(Vector2i(39, 10)), "B")
	eq(level.tile_at(Vector2i(40, 10)), "#", "the next room starts at tile 40")
	eq(level.tile_at(Vector2i(80, 10)), "", "outside every room")
	check(level.is_solid(Vector2i(40, 10)) and not level.is_solid(Vector2i(41, 10)))
	eq(level.room_at_pixel(Vector2(700, 100))["id"], "right")
	eq(level.room_at_pixel(Vector2(639, 100))["id"], "left")
	eq(level.total_cells(), 2)


func test_entity_positions_use_the_tile_the_feet_stand_in() -> void:
	var level := _level([_room("a", Vector2i(1, 0), {})])
	eq(level.entity_position(level.room("a"), [3, 5]), Vector2(696, 96), "bottom-centre of tile (43, 5)")
	var lower := _level([_room("b", Vector2i(0, 1), {})])
	eq(lower.entity_position(lower.room("b"), [0, 0]), Vector2(8, 23 * 16 + 16))


func test_two_cell_rooms() -> void:
	var wide := _room("nave", Vector2i(4, 1), {Vector2i(79, 22): "#"}, Vector2i(2, 1))
	var level := _level([wide])
	eq(level.total_cells(), 2)
	eq(level.room_at_cell(Vector2i(5, 1))["id"], "nave", "both cells belong to the room")
	eq(level.room_rect(level.room("nave")), Rect2(4 * 640, 368, 1280, 368))
	eq(level.tile_at(Vector2i(4 * 40 + 79, 23 + 22)), "#")


func test_validate_reports_broken_rooms() -> void:
	var good := _room("good", Vector2i.ZERO, {}, Vector2i.ONE, [{"type": "enemy", "id": "space_bat", "at": [5, 5]}])
	eq(_level([good]).validate(), [] as Array[String], "a clean room has no problems")
	var short := _room("short", Vector2i.ZERO, {})
	short["tiles"][3] = "..."
	check(_has_problem(_level([short]).validate(), "3 columns"), "short row")
	var fewer := _room("fewer", Vector2i.ZERO, {})
	fewer["tiles"].pop_back()
	check(_has_problem(_level([fewer]).validate(), "22 rows"), "missing row")
	var unknown := _room("unknown", Vector2i.ZERO, {Vector2i(1, 1): "?"})
	check(_has_problem(_level([unknown]).validate(), "unknown tile"), "unknown glyph")
	var lonely := _room("lonely", Vector2i.ZERO, {Vector2i(1, 1): "T"})
	check(_has_problem(_level([lonely]).validate(), "conduit shutter"), "a target without a shutter")
	var outside := _room("outside", Vector2i.ZERO, {}, Vector2i.ONE, [{"type": "save_pod", "at": [40, 3]}])
	check(_has_problem(_level([outside]).validate(), "outside the room"), "entity out of bounds")
	var ghost := _room("ghost", Vector2i.ZERO, {}, Vector2i.ONE, [{"type": "enemy", "id": "gelatinous_cube", "at": [3, 3]}])
	check(_has_problem(_level([ghost]).validate(), "unknown enemy"), "unknown enemy id")


func _has_problem(problems: Array[String], fragment: String) -> bool:
	for problem in problems:
		if problem.contains(fragment):
			return true
	return false
