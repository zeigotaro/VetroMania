class_name GameState
extends RefCounted
## The running game: the save data plus everything derived from it. One instance lives in GameState.current.
## Pure logic with signals, no scene dependencies, so the same code runs in the game and in headless tests.

signal changed
signal toast(text: String, color: Color)
signal leveled_up(level: int)
signal item_gained(item: Dictionary, equipped: bool)
signal tally_event(enemy_id: String, event: String)
signal ability_gained(id: String)
signal montage_ready

static var current: GameState

var data: Dictionary
var slot := 1
var rng := RandomNumberGenerator.new()
var derived: Dictionary = {}
var hp := 1.0
var ep := 1.0
var combat_timer := 0.0
var runtime_flags := {}
var pools := {}


static func begin(slot_number: int = 1, difficulty: String = "normal", seed_value: int = -1) -> GameState:
	var state := GameState.new()
	state.slot = slot_number
	state.data = SaveCodec.new_game(difficulty)
	state._boot(seed_value)
	return state


static func from_save(slot_number: int, save_data: Dictionary, seed_value: int = -1) -> GameState:
	var state := GameState.new()
	state.slot = slot_number
	state.data = save_data
	state._boot(seed_value)
	return state


func _boot(seed_value: int) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var legendary := Db.legendary_data()
	pools = {"legendary": legendary["legendaries"], "set": legendary["sets"]}
	recompute()
	var saved_hp := float(data["player"]["hp"])
	var saved_ep := float(data["player"]["ep"])
	hp = float(derived["max_hp"]) if saved_hp < 0.0 else minf(saved_hp, float(derived["max_hp"]))
	ep = float(derived["max_ep"]) if saved_ep < 0.0 else minf(saved_ep, float(derived["max_ep"]))


func mode() -> Dictionary:
	return Db.difficulty()["modes"][data["difficulty"]]


# --- character ---------------------------------------------------------------------------------

var level: int:
	get:
		return int(data["player"]["level"])


var xp: int:
	get:
		return int(data["player"]["xp"])


func xp_needed() -> int:
	return Stats.xp_to_next(level)


func recompute() -> void:
	derived = Gear.derive(level, data["player"]["allocated"], data["equipped"], Tallies.trait_stats(data["tallies"]), 0.0)
	hp = minf(hp, float(derived["max_hp"]))
	ep = minf(ep, float(derived["max_ep"]))
	changed.emit()


func heal(amount: float) -> void:
	hp = clampf(hp + amount, 0.0, float(derived["max_hp"]))
	changed.emit()


func restore_ep(amount: float) -> void:
	ep = clampf(ep + amount, 0.0, float(derived["max_ep"]))


func full_restore() -> void:
	hp = float(derived["max_hp"])
	ep = float(derived["max_ep"])
	changed.emit()


func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	combat_timer = 5.0
	changed.emit()


func is_dead() -> bool:
	return hp <= 0.0


## Adds XP and returns the levels gained. Reaching a Training Montage level raises montage_ready.
func add_xp(amount: int) -> Array[int]:
	var gained: Array[int] = []
	if level >= Consts.LEVEL_CAP:
		return gained
	data["player"]["xp"] = xp + amount
	while level < Consts.LEVEL_CAP and xp >= xp_needed():
		data["player"]["xp"] = xp - xp_needed()
		data["player"]["level"] = level + 1
		gained.append(level)
	if level >= Consts.LEVEL_CAP:
		data["player"]["xp"] = 0
	if not gained.is_empty():
		var old_max := float(derived["max_hp"])
		recompute()
		hp = minf(float(derived["max_hp"]), hp + (float(derived["max_hp"]) - old_max))
		for reached in gained:
			leveled_up.emit(reached)
		if montage_pending():
			montage_ready.emit()
	changed.emit()
	return gained


func montage_points_earned() -> int:
	return Stats.montage_points(level)


func montage_points_spent() -> int:
	var total := 0
	for stat: String in data["player"]["allocated"]:
		total += int(data["player"]["allocated"][stat])
	return total


func montage_points_free() -> int:
	return montage_points_earned() - montage_points_spent()


## A Training Montage plays each time a multiple of 5 is reached; free points wait until spent.
func montage_pending() -> bool:
	return level / Consts.TRAINING_MONTAGE_EVERY * Consts.TRAINING_MONTAGE_EVERY > int(data["player"]["montage_done"])


func montage_seen() -> void:
	data["player"]["montage_done"] = level / Consts.TRAINING_MONTAGE_EVERY * Consts.TRAINING_MONTAGE_EVERY


func allocate(stat: String) -> bool:
	if montage_points_free() <= 0 or stat not in Stats.NAMES:
		return false
	data["player"]["allocated"][stat] = int(data["player"]["allocated"].get(stat, 0)) + 1
	recompute()
	return true


func deallocate(stat: String) -> bool:
	if int(data["player"]["allocated"].get(stat, 0)) <= 0:
		return false
	data["player"]["allocated"][stat] = int(data["player"]["allocated"][stat]) - 1
	recompute()
	return true


# --- inventory ----------------------------------------------------------------------------------

var bucks: int:
	get:
		return int(data["bucks"])


func add_bucks(amount: int) -> void:
	data["bucks"] = bucks + amount
	changed.emit()


func spend_bucks(amount: int) -> bool:
	if bucks < amount:
		return false
	data["bucks"] = bucks - amount
	changed.emit()
	return true


func gems(kind: String) -> int:
	return int(data["gems"][kind])


func add_gems(kind: String, count: int) -> void:
	data["gems"][kind] = gems(kind) + count
	changed.emit()


func next_uid() -> int:
	var uid := int(data["loot"]["next_uid"])
	data["loot"]["next_uid"] = uid + 1
	return uid


## Adds an item to the inventory. Empty slots are filled automatically when the level allows it.
func add_item(item: Dictionary) -> bool:
	item["uid"] = next_uid()
	data["inventory"].append(item)
	var equipped := false
	var target := slot_for_item(item)
	if target != "" and not data["equipped"].has(target) and Gear.equip_error(item, target, level) == "":
		data["equipped"][target] = item
		equipped = true
		recompute()
	item_gained.emit(item, equipped)
	changed.emit()
	return equipped


func slot_for_item(item: Dictionary) -> String:
	if item["slot"] != "ring":
		return item["slot"]
	for candidate in ["ring1", "ring2"]:
		if Gear.slot_unlocked(candidate, level) and not data["equipped"].has(candidate):
			return candidate
	return "ring1" if Gear.slot_unlocked("ring1", level) else ""


func equip(item: Dictionary, slot_name: String) -> String:
	var problem := Gear.equip_error(item, slot_name, level)
	if problem != "":
		return problem
	for other: String in data["equipped"]:
		if other != slot_name and data["equipped"][other]["uid"] == item["uid"]:
			data["equipped"].erase(other)
			break
	data["equipped"][slot_name] = item
	recompute()
	return ""


func unequip(slot_name: String) -> void:
	data["equipped"].erase(slot_name)
	recompute()


func equipped_slot_of(item: Dictionary) -> String:
	for slot_name: String in data["equipped"]:
		if data["equipped"][slot_name]["uid"] == item["uid"]:
			return slot_name
	return ""


func item_by_uid(uid: int) -> Dictionary:
	for item: Dictionary in data["inventory"]:
		if int(item["uid"]) == uid:
			return item
	return {}


func salvage(item: Dictionary) -> int:
	var refund := Upgrades.salvage_refund(item)
	if equipped_slot_of(item) != "":
		unequip(equipped_slot_of(item))
	data["inventory"] = data["inventory"].filter(func(other: Dictionary) -> bool: return int(other["uid"]) != int(item["uid"]))
	add_gems(Upgrades.gem_kind(item), refund)
	add_bucks(Items.sell_price(item))
	return refund


func upgrade_item(item: Dictionary, affix_index: int) -> String:
	var problem := Upgrades.error_for(item, level, data["gems"], bucks)
	if problem != "":
		return problem
	var fee := Upgrades.bucks_fee(item)
	var kind := Upgrades.gem_kind(item)
	var cost := Upgrades.apply(item, affix_index)
	data["gems"][kind] = gems(kind) - cost
	data["bucks"] = bucks - fee
	recompute()
	return ""


func consumables(id: String) -> int:
	return int(data["consumables"].get(id, 0))


func add_consumable(id: String, count: int = 1) -> void:
	data["consumables"][id] = consumables(id) + count
	changed.emit()


func use_consumable(id: String) -> bool:
	if consumables(id) <= 0:
		return false
	var def: Dictionary = Db.legendary_data()["consumables"][id]
	if def.has("heal_pct"):
		heal(float(derived["max_hp"]) * float(def["heal_pct"]) / 100.0)
	if def.has("ep_pct"):
		restore_ep(float(derived["max_ep"]) * float(def["ep_pct"]) / 100.0)
	data["consumables"][id] = consumables(id) - 1
	changed.emit()
	return true


# --- abilities, seals, world flags --------------------------------------------------------------

func has_ability(id: String) -> bool:
	return id in data["abilities"]


func grant_ability(id: String) -> void:
	if not has_ability(id):
		data["abilities"].append(id)
		ability_gained.emit(id)
		changed.emit()


func has_seal(number: int) -> bool:
	return number in data["seals"]


func grant_seal(number: int) -> void:
	if not has_seal(number):
		data["seals"].append(number)
		changed.emit()


func is_opened(key: String) -> bool:
	return key in data["world"]["opened"]


func mark_opened(key: String) -> void:
	if not is_opened(key):
		data["world"]["opened"].append(key)


func is_collected(id: String) -> bool:
	return id in data["world"]["collected"]


func mark_collected(id: String) -> void:
	if not is_collected(id):
		data["world"]["collected"].append(id)


func flag(name: String, fallback: Variant = false) -> Variant:
	return data["world"]["flags"].get(name, fallback)


func set_flag(name: String, value: Variant) -> void:
	data["world"]["flags"][name] = value


func boss_state(id: String) -> Dictionary:
	return data["world"]["bosses"].get(id, {"defeated": false, "hp_frac": 1.0})


func set_boss_state(id: String, defeated: bool, hp_frac: float) -> void:
	data["world"]["bosses"][id] = {"defeated": defeated, "hp_frac": hp_frac}


# --- map -----------------------------------------------------------------------------------------

## Marks a cell visited. Returns true the first time.
func visit_cell(cell: Vector2i) -> bool:
	var key := MapCells.key(cell)
	if key in data["map"]["visited"]:
		return false
	data["map"]["visited"].append(key)
	changed.emit()
	return true


func has_visited(cell: Vector2i) -> bool:
	return MapCells.key(cell) in data["map"]["visited"]


func visited_count() -> int:
	return data["map"]["visited"].size()


# --- kills, drops --------------------------------------------------------------------------------

## The level an enemy spawns at: an explicit level, else the area's, with the hub tracking progress.
func enemy_level(area_id: String, spawn_level: int = 0) -> int:
	if spawn_level > 0:
		return spawn_level
	var area: Dictionary = Db.areas()["areas"][area_id]
	if area.get("hub", false):
		return hub_level()
	return int(area["levels"][0])


## Hull Cathedral matches the lowest level of the newest area the player can enter.
func hub_level() -> int:
	var newest := 1
	for id: String in Db.areas()["order"]:
		var area: Dictionary = Db.areas()["areas"][id]
		if area.get("hub", false):
			continue
		var needs: String = area["entry_needs"]
		if needs == "" or has_ability(needs):
			newest = int(area["levels"][0])
	return newest


func drop_context(source: String, enemy_level_value: int, elite_salty: bool = false, rival: bool = false) -> Dictionary:
	return {
		"source": source, "level": enemy_level_value, "player_level": level,
		"luck": float(derived["loot_luck"]) + float(mode()["loot_luck"]),
		"counters": data["loot"]["counters"], "pools": pools, "rival": rival,
		"rival_mult": float(Db.perks()["rival_drop_mult"]), "bucks_pct": float(derived["bucks_pct"]), "salty": elite_salty,
	}


## Applies a kill: XP, tally progress and the loot to spawn. Returns {xp, drops, events, levels}.
func register_kill(enemy_id: String, enemy_level_value: int, elite: bool, salty: bool = false, boss: bool = false) -> Dictionary:
	var first := Tallies.is_first_kill(data["tallies"], enemy_id)
	var amount := float(Stats.enemy_xp(enemy_level_value)) * Stats.xp_level_factor(enemy_level_value, level)
	if boss:
		amount *= float(Db.boss(enemy_id).get("xp_mult", 25))
	elif elite:
		amount *= 3.0
	if first:
		amount *= float(Db.perks()["first_kill_xp_mult"])
	var events: Array[String] = []
	if not boss:
		events = Tallies.add_kill(data["tallies"], enemy_id)
		for event in events:
			tally_event.emit(enemy_id, event)
		if "complete" in events:
			recompute()
	var rival := not boss and Tallies.rival_active(data["tallies"], enemy_id)
	var source := "boss" if boss else ("elite" if elite else "fodder")
	var drops := Loot.roll_drops(rng, drop_context(source, enemy_level_value, salty, rival))
	var levels := add_xp(maxi(1, roundi(amount)))
	return {"xp": maxi(1, roundi(amount)), "drops": drops, "events": events, "levels": levels, "first": first}


## Hands a drop to the player (currency and consumables immediately, gear into the inventory).
func collect(drop: Dictionary) -> void:
	match drop["type"]:
		"bucks":
			add_bucks(int(drop["amount"]))
		"gem":
			add_gems(drop["kind"], int(drop["count"]))
		"consumable":
			add_consumable(drop["id"])
		"gear":
			add_item(drop["item"])


# --- saving --------------------------------------------------------------------------------------

## Where Death and Continue put Sleve back. With a position (pods, area autosaves) that exact spot is used,
## otherwise the room's named spawn.
func checkpoint(room_id: String, spawn: String, pos: Variant = null) -> void:
	var entry := {"room": room_id, "spawn": spawn}
	if pos is Vector2:
		entry["pos"] = [snappedf((pos as Vector2).x, 0.1), snappedf((pos as Vector2).y, 0.1)]
	data["checkpoint"] = entry


func save() -> Error:
	data["player"]["hp"] = roundi(hp)
	data["player"]["ep"] = roundi(ep)
	data["saved_at"] = int(Time.get_unix_time_from_system())
	return SaveFiles.write(slot, data)
