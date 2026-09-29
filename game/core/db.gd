class_name Db
extends RefCounted
## Read-only game data from res://data/*.json, parsed once. Numbers come back as floats.

static var _cache := {}


static func json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Db: missing data file %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Db: bad JSON in %s" % path)
		return {}
	_cache[path] = parsed
	return parsed


static func base_items() -> Dictionary:
	return json("res://data/base_items.json")


static func affixes() -> Array:
	return json("res://data/affixes.json")["affixes"]


static func affix_tier_ilvl() -> Array:
	return json("res://data/affixes.json")["tier_ilvl"]


static func affix(id: String) -> Dictionary:
	for entry: Dictionary in affixes():
		if entry["id"] == id:
			return entry
	return {}


static func perks() -> Dictionary:
	return json("res://data/perks.json")


static func enemies() -> Dictionary:
	return json("res://data/enemies.json")["enemies"]


static func enemy(id: String) -> Dictionary:
	return enemies().get(id, {})


static func boss(id: String) -> Dictionary:
	return json("res://data/enemies.json")["bosses"].get(id, {})


static func elite() -> Dictionary:
	return json("res://data/enemies.json")["elite"]


static func areas() -> Dictionary:
	return json("res://data/areas.json")


static func legendary_data() -> Dictionary:
	return json("res://data/legendaries.json")


static func difficulty() -> Dictionary:
	return json("res://data/difficulty.json")


static func roster() -> Dictionary:
	return json("res://data/roster.json")


static func manifest() -> Dictionary:
	return json("res://assets/manifest.json")


static func audio_manifest() -> Dictionary:
	return json("res://assets/audio/manifest.json")
