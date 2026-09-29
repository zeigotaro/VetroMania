class_name SaveCodec
extends RefCounted
## Versioned save format (schema 1). encode() writes sorted, indented JSON; decode() migrates older
## schemas step by step, fills defaults and validates. Pure data, no file access (see SaveFiles).

const SCHEMA := 1


static func new_game(difficulty: String = "normal") -> Dictionary:
	return {
		"schema": SCHEMA, "difficulty": difficulty, "playtime": 0.0, "saved_at": 0, "deaths": 0,
		"player": {"level": 1, "xp": 0, "hp": -1, "ep": -1, "allocated": {}, "montage_done": 0},
		"bucks": 0, "gems": {"armor": 0, "weapon": 0},
		"inventory": [], "equipped": {}, "consumables": {},
		"abilities": [], "seals": [],
		"tallies": Tallies.new_state(),
		"map": {"visited": []},
		"world": {"opened": [], "collected": [], "bosses": {}, "flags": {}, "talked": []},
		"loot": {"counters": Loot.new_counters(), "next_uid": 1},
		"checkpoint": {"room": "crash_1", "spawn": "start"},
	}


static func encode(state: Dictionary) -> String:
	return JSON.stringify(state, "\t", true)


## Returns {ok, state, error, migrated_from}.
static func decode(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _fail("Save file is not valid JSON (line %d: %s)" % [parser.get_error_line(), parser.get_error_message()])
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("Save file is not a JSON object")
	var data: Dictionary = _normalize(parsed)
	var version := int(data.get("schema", data.get("version", 0)))
	if version > SCHEMA:
		return _fail("Save was made by a newer version (schema %d)" % version)
	var from := version
	while version < SCHEMA:
		data = _migrate(data, version)
		version += 1
	var merged := _fill_defaults(data, new_game(String(data.get("difficulty", "normal"))))
	var problem := validate(merged)
	if problem != "":
		return _fail(problem)
	return {"ok": true, "state": merged, "error": "", "migrated_from": from}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message, "migrated_from": -1}


static func validate(state: Dictionary) -> String:
	var level := int(state["player"]["level"])
	if level < 1 or level > Consts.LEVEL_CAP:
		return "Level %d is out of range" % level
	if int(state["bucks"]) < 0:
		return "Negative Vetro-Bucks"
	for item: Dictionary in state["inventory"]:
		for field: String in ["slot", "family", "ilvl", "rarity", "affixes", "upgrades"]:
			if not item.has(field):
				return "Inventory item is missing '%s'" % field
	return ""


## Integral floats become ints, since JSON has one number type.
static func _normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				out[key] = _normalize(value[key])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for entry: Variant in value:
				out.append(_normalize(entry))
			return out
		TYPE_FLOAT:
			if is_equal_approx(value, roundf(value)) and absf(value) < 1.0e15:
				return int(value)
	return value


## Adds any key missing from data (recursively) using the defaults.
static func _fill_defaults(data: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	for key: String in defaults:
		if not out.has(key):
			out[key] = defaults[key]
		elif typeof(defaults[key]) == TYPE_DICTIONARY and typeof(out[key]) == TYPE_DICTIONARY and key not in ["allocated", "bosses", "flags", "equipped", "consumables"]:
			out[key] = _fill_defaults(out[key], defaults[key])
	return out


static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	match from_version:
		0:
			return _migrate_0_to_1(data)
	return data


## Schema 0 was a flat prototype layout: lvl, exp, money, hp, items, "a,b" abilities, "x,y;x,y" visited, room.
static func _migrate_0_to_1(old: Dictionary) -> Dictionary:
	var state := new_game(String(old.get("difficulty", "normal")))
	state["player"]["level"] = int(old.get("lvl", 1))
	state["player"]["xp"] = int(old.get("exp", 0))
	state["player"]["hp"] = int(old.get("hp", -1))
	state["bucks"] = int(old.get("money", 0))
	for ability: String in String(old.get("abilities", "")).split(",", false):
		state["abilities"].append(ability)
	for cell: String in String(old.get("visited", "")).split(";", false):
		state["map"]["visited"].append(cell)
	state["checkpoint"]["room"] = String(old.get("room", "crash_1"))
	var uid := 1
	for entry: Dictionary in old.get("items", []):
		var family := String(entry.get("t", ""))
		var slot := Loot.slot_for_family(family) if _known_family(family) else ""
		if slot == "":
			continue
		var ilvl := int(entry.get("il", 1))
		var item := Items.make(slot, family, Items.base_tier(ilvl), 0, ilvl, String(entry.get("r", "common")))
		item["uid"] = uid
		uid += 1
		state["inventory"].append(item)
	state["loot"]["next_uid"] = uid
	return state


static func _known_family(family: String) -> bool:
	var db := Db.base_items()
	return db["armor"].has(family) or db["rings"].has(family) or db["weapons"].has(family)
