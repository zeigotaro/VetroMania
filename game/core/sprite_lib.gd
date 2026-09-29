class_name SpriteLib
extends RefCounted
## Builds SpriteFrames from res://assets/manifest.json. Every sprite is a horizontal strip of equal frames
## with a pivot (the point that sits at the node's origin, e.g. the feet). Sprites face right.

static var _textures := {}
static var _frames := {}


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load("res://assets/" + path)
	return _textures[path]


static func info(key: String) -> Dictionary:
	return Db.manifest()["sprites"].get(key, {})


static func anim_name(key: String) -> String:
	return key.replace("/", "_")


## One SpriteFrames holding an animation per key ("sleve/run" is animation "sleve_run").
static func frames_for(keys: Array) -> SpriteFrames:
	var id := ",".join(keys)
	if _frames.has(id):
		return _frames[id]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for key: String in keys:
		var entry := info(key)
		if entry.is_empty():
			push_error("SpriteLib: no sprite '%s' in the manifest" % key)
			continue
		var strip := texture(entry["file"])
		var size := Vector2i(int(entry["frame_size"][0]), int(entry["frame_size"][1]))
		var name := anim_name(key)
		frames.add_animation(name)
		frames.set_animation_speed(name, float(entry["fps"]))
		frames.set_animation_loop(name, bool(entry["loop"]))
		for i in int(entry["frames"]):
			var atlas := AtlasTexture.new()
			atlas.atlas = strip
			atlas.region = Rect2(i * size.x, 0, size.x, size.y)
			frames.add_frame(name, atlas)
	_frames[id] = frames
	return frames


## Offset that places the sprite's pivot at the node origin, mirrored when flipped.
static func offset_for(key: String, flipped: bool) -> Vector2:
	var entry := info(key)
	if entry.is_empty():
		return Vector2.ZERO
	var size_x := float(entry["frame_size"][0])
	var pivot := Vector2(float(entry["pivot"][0]), float(entry["pivot"][1]))
	return Vector2(-(size_x - pivot.x) if flipped else -pivot.x, -pivot.y)


static func frame_size(key: String) -> Vector2:
	var entry := info(key)
	return Vector2(float(entry["frame_size"][0]), float(entry["frame_size"][1])) if not entry.is_empty() else Vector2.ZERO
