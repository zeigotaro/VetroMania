class_name WorldBuilder
extends RefCounted
## Builds the physical and visual world from a Level and its LevelGeometry.

const PLATFORM_THICKNESS := 4.0
const SPIKE_HEIGHT := 8.0

static var _tilesets := {}


static func solid_body(geometry: Dictionary) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Solids"
	body.collision_layer = 1
	body.collision_mask = 0
	for rect: Rect2i in geometry["solids"]:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size * Consts.TILE)
		shape.shape = box
		shape.position = Vector2(rect.position * Consts.TILE) + box.size / 2.0
		body.add_child(shape)
	return body


## One-way platforms live in their own body (group "platform") so the Player can drop through them.
static func platform_body(geometry: Dictionary) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Platforms"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("platform")
	for rect: Rect2i in geometry["platforms"]:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size.x * Consts.TILE, PLATFORM_THICKNESS)
		shape.shape = box
		shape.one_way_collision = true
		shape.position = Vector2(rect.position * Consts.TILE) + Vector2(box.size.x / 2.0, PLATFORM_THICKNESS / 2.0)
		body.add_child(shape)
	return body


## Spikes hurt on touch. level_for maps a global tile to the area's enemy level.
static func spike_areas(geometry: Dictionary, level_for: Callable) -> Node2D:
	var holder := Node2D.new()
	holder.name = "Spikes"
	for rect: Rect2i in geometry["spikes"]:
		var box := Vector2(rect.size.x * Consts.TILE, SPIKE_HEIGHT)
		var center := Vector2(rect.position * Consts.TILE) + Vector2(box.x / 2.0, Consts.TILE - SPIKE_HEIGHT / 2.0)
		var hit := HitArea.new(box, Vector2.ZERO)
		hit.position = center
		hit.kind = "spike"
		hit.level = int(level_for.call(rect.position))
		holder.add_child(hit)
	return holder


static func tileset(area_tileset: String) -> TileSet:
	if _tilesets.has(area_tileset):
		return _tilesets[area_tileset]
	var manifest: Dictionary = Db.manifest()["tiles"]
	var source := TileSetAtlasSource.new()
	source.texture = SpriteLib.texture(manifest["atlases"][area_tileset])
	source.texture_region_size = Vector2i(Consts.TILE, Consts.TILE)
	for name: String in manifest["index"]:
		var cell := Vector2i(int(manifest["index"][name][0]), int(manifest["index"][name][1]))
		source.create_tile(cell)
	var set := TileSet.new()
	set.tile_size = Vector2i(Consts.TILE, Consts.TILE)
	set.add_source(source, 0)
	_tilesets[area_tileset] = set
	return set


static func tile_cell(name: String) -> Vector2i:
	var index: Array = Db.manifest()["tiles"]["index"][name]
	return Vector2i(int(index[0]), int(index[1]))


## The tile name for a legend character at a global tile, or "" for nothing drawn.
static func tile_name(level: Level, tile: Vector2i, ch: String) -> String:
	match ch:
		"#":
			return "floor_fill" if level.is_solid(tile + Vector2i.UP) else "floor_top"
		"B", "%":
			return "brick"
		"Z":
			return "hazard"
		"=":
			return "platform"
		"^":
			return "spike"
		"X":
			return "crate"
		"T":
			return "mitt_target_0"
		"C":
			return "brick_conduit"
	return Level.DECOR_TILES.get(ch, "")


## Returns {layers: {area: TileMapLayer}, back: {area: TileMapLayer}} added under `parent`.
static func build_tiles(parent: Node, level: Level) -> Dictionary:
	var front := {}
	var back := {}
	for id: String in level.order:
		var room: Dictionary = level.rooms[id]
		var tileset_name: String = Db.areas()["areas"][room["area"]]["tileset"]
		if not front.has(room["area"]):
			var behind := TileMapLayer.new()
			behind.name = "Back_" + room["area"]
			behind.tile_set = tileset(tileset_name)
			behind.z_index = -5
			parent.add_child(behind)
			back[room["area"]] = behind
			var ahead := TileMapLayer.new()
			ahead.name = "Front_" + room["area"]
			ahead.tile_set = tileset(tileset_name)
			parent.add_child(ahead)
			front[room["area"]] = ahead
		var origin := level.room_tile_origin(room)
		var size := level.room_size_tiles(room)
		for y in size.y:
			for x in size.x:
				var tile := origin + Vector2i(x, y)
				var ch := level.tile_at(tile)
				var name := tile_name(level, tile, ch)
				if name == "":
					continue
				var layer: TileMapLayer = back[room["area"]] if Level.DECOR.contains(ch) or ch == "^" else front[room["area"]]
				layer.set_cell(tile, 0, tile_cell(name))
	return {"front": front, "back": back}
