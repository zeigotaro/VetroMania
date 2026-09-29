class_name LevelGeometry
extends RefCounted
## Turns a Level into collision geometry: solid tiles merged into as few rectangles as possible (so the
## player never snags on seams between tiles), plus one-way platform runs, spike runs and gate groups.
## Everything here is in tile units, in the level's global tile grid.

const STATIC_SOLID := "#BZ"


## Returns {solids: Array[Rect2i], platforms: Array[Rect2i], spikes: Array[Rect2i],
##          gates: Array[{kind, room, tiles}], targets: Array[{room, tile}], bounds: Rect2i}
static func build(level: Level) -> Dictionary:
	var bounds := _bounds(level)
	var solids := _merge_rects(bounds, func(tile: Vector2i) -> bool: return _is_static_solid(level, tile))
	return {
		"solids": solids,
		"platforms": _runs(level, bounds, "="),
		"spikes": _runs(level, bounds, "^"),
		"gates": _gates(level),
		"targets": _targets(level),
		"bounds": bounds,
	}


## Tile bounds of the map plus a one-tile ring of solid "outside" so nothing can leave the level.
static func _bounds(level: Level) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for id: String in level.order:
		var r: Dictionary = level.rooms[id]
		var origin := level.room_tile_origin(r)
		var size := level.room_size_tiles(r)
		lo = Vector2i(mini(lo.x, origin.x), mini(lo.y, origin.y))
		hi = Vector2i(maxi(hi.x, origin.x + size.x), maxi(hi.y, origin.y + size.y))
	return Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(2, 2))


## Outside any room counts as solid; inside, only static solids (gates are separate bodies).
static func _is_static_solid(level: Level, tile: Vector2i) -> bool:
	var ch := level.tile_at(tile)
	return ch == "" or STATIC_SOLID.contains(ch)


static func _merge_rects(bounds: Rect2i, is_filled: Callable) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var open := {}
	for y in range(bounds.position.y, bounds.end.y + 1):
		var runs := {}
		if y < bounds.end.y:
			var x := bounds.position.x
			while x < bounds.end.x:
				if is_filled.call(Vector2i(x, y)):
					var start := x
					while x < bounds.end.x and is_filled.call(Vector2i(x, y)):
						x += 1
					runs[Vector2i(start, x)] = true
				else:
					x += 1
		var next_open := {}
		for span: Vector2i in open:
			if runs.has(span):
				next_open[span] = open[span]
				runs.erase(span)
			else:
				out.append(Rect2i(span.x, open[span], span.y - span.x, y - open[span]))
		for span: Vector2i in runs:
			next_open[span] = y
		open = next_open
	return out


static func _runs(level: Level, bounds: Rect2i, ch: String) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for y in range(bounds.position.y, bounds.end.y):
		var x := bounds.position.x
		while x < bounds.end.x:
			if level.tile_at(Vector2i(x, y)) == ch:
				var start := x
				while x < bounds.end.x and level.tile_at(Vector2i(x, y)) == ch:
					x += 1
				out.append(Rect2i(start, y, x - start, 1))
			else:
				x += 1
	return out


## Breakable groups: 4-connected tiles of the same gate character. Every C tile in a room is one shutter.
static func _gates(level: Level) -> Array:
	var out: Array = []
	for id: String in level.order:
		var r: Dictionary = level.rooms[id]
		var origin := level.room_tile_origin(r)
		var size := level.room_size_tiles(r)
		var seen := {}
		for ch: String in ["%", "X", "C"]:
			for y in size.y:
				for x in size.x:
					var tile := origin + Vector2i(x, y)
					if seen.has(tile) or level.tile_at(tile) != ch:
						continue
					var group: Array[Vector2i] = []
					var stack: Array[Vector2i] = [tile]
					while not stack.is_empty():
						var at: Vector2i = stack.pop_back()
						if seen.has(at) or level.tile_at(at) != ch:
							continue
						seen[at] = true
						group.append(at)
						for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							stack.append(at + step)
					if ch == "C" and not out.is_empty():
						var merged := false
						for gate: Dictionary in out:
							if gate["kind"] == "C" and gate["room"] == id:
								gate["tiles"].append_array(group)
								merged = true
								break
						if merged:
							continue
					var lowest := group[0]
					for t in group:
						if t.y < lowest.y or (t.y == lowest.y and t.x < lowest.x):
							lowest = t
					out.append({"kind": ch, "room": id, "tiles": group, "key": "%s:%s:%d,%d" % [id, ch, lowest.x, lowest.y]})
	return out


static func _targets(level: Level) -> Array:
	var out: Array = []
	for id: String in level.order:
		var r: Dictionary = level.rooms[id]
		var origin := level.room_tile_origin(r)
		var size := level.room_size_tiles(r)
		for y in size.y:
			for x in size.x:
				if level.tile_at(origin + Vector2i(x, y)) == "T":
					out.append({"room": id, "tile": origin + Vector2i(x, y), "key": "%s:T:%d,%d" % [id, origin.x + x, origin.y + y]})
	return out
