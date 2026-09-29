class_name Settings
extends RefCounted
## Player options, saved to user://settings.json. Static (like GameState.current) so headless tests need no autoload.

const SPEEDS: Array[float] = [0.7, 0.8, 0.9, 1.0]

static var path := "user://settings.json"
static var music := 0.8
static var sfx := 1.0
static var shake := 1.0
static var damage_numbers := true
static var speed := 1.0
static var seal_assist := false
static var fullscreen := false


static func reset() -> void:
	music = 0.8
	sfx = 1.0
	shake = 1.0
	damage_numbers = true
	speed = 1.0
	seal_assist = false
	fullscreen = false


static func to_dict() -> Dictionary:
	return {
		"music": music, "sfx": sfx, "shake": shake, "damage_numbers": damage_numbers,
		"speed": speed, "seal_assist": seal_assist, "fullscreen": fullscreen,
	}


static func from_dict(data: Dictionary) -> void:
	music = clampf(float(data.get("music", music)), 0.0, 1.0)
	sfx = clampf(float(data.get("sfx", sfx)), 0.0, 1.0)
	shake = clampf(float(data.get("shake", shake)), 0.0, 1.0)
	damage_numbers = bool(data.get("damage_numbers", damage_numbers))
	speed = nearest_speed(float(data.get("speed", speed)))
	seal_assist = bool(data.get("seal_assist", seal_assist))
	fullscreen = bool(data.get("fullscreen", fullscreen))


static func nearest_speed(value: float) -> float:
	var best := SPEEDS[SPEEDS.size() - 1]
	for candidate in SPEEDS:
		if absf(candidate - value) < absf(best - value):
			best = candidate
	return best


static func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		from_dict(parser.data)


static func save_file() -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t", true))
	return OK


## Pushes the options into the engine: game speed, audio levels and the window mode.
static func apply() -> void:
	Engine.time_scale = speed
	if AudioService.instance != null:
		AudioService.instance.sfx_volume = sfx
		AudioService.instance.music_volume = music
		AudioService.instance.refresh_music_volume()
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
