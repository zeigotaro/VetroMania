class_name Gear
extends RefCounted
## Equipped items -> totals -> derived character stats (docs/design/progression-and-loot.md#stats).

## Every stat key an affix may grant. None of them is a traversal ability.
const STAT_KEYS: Array[String] = [
	"armor_pct", "damage_pct", "hp", "ep", "resist_cryo", "resist_heat", "resist_volt",
	"dmg_heat", "dmg_cryo", "dmg_volt", "dmg_bio", "loot_luck", "slide_pct", "vamp_pct",
	"str", "con", "int", "dex", "lck", "crit_chance", "crit_damage", "attack_speed",
	"hp_regen", "thorns_pct", "bucks_pct", "battle_cry",
]
const ELEMENTS: Array[String] = ["HEAT", "CRYO", "VOLT", "BIO"]


static func slot_unlocked(slot: String, level: int) -> bool:
	match slot:
		"ring1":
			return level >= int(Consts.RING_SLOT_LEVELS[0])
		"ring2":
			return level >= int(Consts.RING_SLOT_LEVELS[1])
	return true


## Empty string when the item can be worn in that equipment slot, otherwise the reason.
static func equip_error(item: Dictionary, slot: String, level: int) -> String:
	var item_slot: String = item["slot"]
	if slot in ["ring1", "ring2"]:
		if item_slot != "ring":
			return "Not a ring"
		if not slot_unlocked(slot, level):
			return "Slot opens at Lv %d" % Consts.RING_SLOT_LEVELS[0 if slot == "ring1" else 1]
	elif item_slot != slot:
		return "Wrong slot"
	if level < Items.required_level(item):
		return "Requires Lv %d" % Items.required_level(item)
	return ""


static func totals(equipped: Dictionary, level: int) -> Dictionary:
	var out := {
		"armor": 0, "weapon_damage": 0, "sub_damage": 0, "stats": {}, "dmg": {}, "resist": {},
		"powers": [], "set_counts": {}, "set_flags": {}, "bonus": {},
	}
	var bonus: Dictionary = out["bonus"]
	for key: String in STAT_KEYS:
		bonus[key] = 0.0
	for slot: String in equipped:
		var item: Dictionary = equipped[slot]
		if item.is_empty() or not slot_unlocked(slot, level):
			continue
		var effective := Items.effective_value(item)
		if Items.is_armor_slot(item["slot"]):
			out["armor"] += effective
		elif item["slot"] == "weapon":
			out["weapon_damage"] += effective
		elif item["slot"] == "sub":
			out["sub_damage"] += effective
		for entry: Dictionary in item["affixes"]:
			var stat: String = Db.affix(entry["id"])["stat"]
			bonus[stat] = float(bonus[stat]) + float(entry["value"])
		if String(item.get("power", "")) != "":
			out["powers"].append(item["power"])
		if String(item.get("set_id", "")) != "":
			out["set_counts"][item["set_id"]] = int(out["set_counts"].get(item["set_id"], 0)) + 1
	_apply_sets(out)
	_apply_powers(out, level)
	var stats: Dictionary = out["stats"]
	for pair: Array in [["STR", "str"], ["CON", "con"], ["INT", "int"], ["DEX", "dex"], ["LCK", "lck"]]:
		stats[pair[0]] = int(stats.get(pair[0], 0)) + roundi(float(bonus[pair[1]]))
	for element: String in ELEMENTS:
		out["dmg"][element] = float(bonus["dmg_" + element.to_lower()])
		if element != "BIO":
			out["resist"][element] = float(bonus["resist_" + element.to_lower()])
	return out


static func _apply_sets(out: Dictionary) -> void:
	for set_def: Dictionary in Db.legendary_data()["sets"]:
		var count := int(out["set_counts"].get(set_def["id"], 0))
		for bonus: Dictionary in set_def["bonuses"]:
			if count >= int(bonus["pieces"]):
				var stat: String = bonus["stat"]
				if out["bonus"].has(stat):
					out["bonus"][stat] = float(out["bonus"][stat]) + float(bonus["value"])
				else:
					out["set_flags"][stat] = true


static func _apply_powers(out: Dictionary, level: int) -> void:
	if "mullet" in out["powers"]:
		var extra := Powers.mullet_bonus(level)
		for stat: String in Stats.NAMES:
			out["stats"][stat] = int(out["stats"].get(stat, 0)) + extra


static func has_power(gear: Dictionary, power: String) -> bool:
	return power in gear["powers"]


## Full derived sheet. trait_stats are Kill Tally trait bonuses like {"INT": 2}; trait_crit is their crit total.
static func derive(level: int, allocated: Dictionary, equipped: Dictionary, trait_stats: Dictionary = {}, trait_crit: float = 0.0) -> Dictionary:
	var g := totals(equipped, level)
	var gear_stats: Dictionary = g["stats"].duplicate()
	for stat: String in trait_stats:
		gear_stats[stat] = int(gear_stats.get(stat, 0)) + int(trait_stats[stat])
	var stats := Stats.final_stats(level, allocated, gear_stats)
	var bonus: Dictionary = g["bonus"]
	return {
		"level": level,
		"stats": stats,
		"max_hp": Stats.max_hp(stats["CON"], level, roundi(float(bonus["hp"]))),
		"max_ep": Stats.max_ep(stats["INT"], level, roundi(float(bonus["ep"]))),
		"atk": Damage.melee_atk(g["weapon_damage"], stats["STR"]),
		"sub_atk": Damage.sub_atk(g["sub_damage"], stats["DEX"], stats["INT"]),
		"def": Damage.defense(stats["CON"], g["armor"]),
		"armor": g["armor"],
		"crit_chance": Stats.crit_chance(stats["DEX"], float(bonus["crit_chance"]) + trait_crit),
		"crit_damage": Damage.CRIT_MULT + float(bonus["crit_damage"]) / 100.0,
		"loot_luck": Stats.loot_luck(stats["LCK"], float(bonus["loot_luck"])),
		"attack_speed": float(bonus["attack_speed"]),
		"bucks_pct": float(bonus["bucks_pct"]),
		"hp_regen": float(bonus["hp_regen"]),
		"vamp_pct": float(bonus["vamp_pct"]),
		"thorns_pct": float(bonus["thorns_pct"]),
		"slide_pct": float(bonus["slide_pct"]),
		"battle_cry": float(bonus["battle_cry"]),
		"dmg": g["dmg"],
		"resist": g["resist"],
		"powers": g["powers"],
		"set_flags": g["set_flags"],
	}
