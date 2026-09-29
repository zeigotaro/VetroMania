class_name Items
extends RefCounted
## Item model: bases, base values, affix rolls, names. An item is a plain Dictionary so it saves as JSON:
## {uid, slot, family, base, tier, ilvl, rarity, affixes:[{id, tier, value}], upgrades, gems_spent,
##  name, fixed_name, power, set_id}
## slot is one of Consts.SLOTS families: helmet chest gauntlets gloves leggings boots ring weapon sub.

const ARMOR_BASE := 9.0
const WEAPON_BASE := 8.0
const PER_ILVL := 1.6


static func is_armor_slot(slot: String) -> bool:
	return Consts.ARMOR_SLOTS.has(slot)


static func family_data(item: Dictionary) -> Dictionary:
	var db := Db.base_items()
	var family: String = item["family"]
	if db["armor"].has(family):
		return db["armor"][family]
	if db["rings"].has(family):
		return db["rings"][family]
	return db["weapons"].get(family, {})


## Base tier index: 0 Normal, 1 Exceptional, 2 Elite.
static func base_tier(ilvl: int) -> int:
	var thresholds: Array = Db.base_items()["tier_ilvl"]
	var tier := 0
	for i in thresholds.size():
		if ilvl >= int(thresholds[i]):
			tier = i
	return tier


## Highest affix tier (1-5) an item of this level can roll.
static func max_affix_tier(ilvl: int) -> int:
	var thresholds: Array = Db.affix_tier_ilvl()
	var tier := 1
	for i in thresholds.size():
		if ilvl >= int(thresholds[i]):
			tier = i + 1
	return tier


static func rarity_mult(rarity: String) -> float:
	return float(Db.base_items()["rarity"][rarity]["mult"])


static func base_value(item: Dictionary) -> int:
	var slot: String = item["slot"]
	if slot == "ring":
		return 0
	var data := family_data(item)
	var weight := float(data.get("weight", 1.0))
	var base := ARMOR_BASE if is_armor_slot(slot) else WEAPON_BASE
	return roundi(weight * (base + PER_ILVL * int(item["ilvl"])) * rarity_mult(item["rarity"]))


## Base value after upgrades: +10% of the base per step (+15% for common items), rounded down.
static func upgraded_value(item: Dictionary, upgrades: int = -1) -> int:
	var n := int(item.get("upgrades", 0)) if upgrades < 0 else upgrades
	var base := base_value(item)
	var pct := 15 if item["rarity"] == "common" else 10
	return floori(float(base * (100 + pct * n)) / 100.0)


static func required_level(item: Dictionary) -> int:
	var gap := 2 if item["rarity"] in ["set", "legendary"] else 4
	return maxi(1, int(item["ilvl"]) - gap)


static func sell_price(item: Dictionary) -> int:
	return 10 * int(item["ilvl"]) * int(Db.base_items()["rarity"][item["rarity"]]["sell"])


## Each affix spans min..max over five equal tier bands.
static func affix_band(def: Dictionary, tier: int) -> Vector2:
	var width := (float(def["max"]) - float(def["min"])) / 5.0
	var lo := float(def["min"]) + width * (tier - 1)
	return Vector2(lo, lo + width)


static func affix_decimals(def: Dictionary) -> int:
	return int(def.get("dec", 0))


static func round_value(def: Dictionary, value: float) -> float:
	var decimals := affix_decimals(def)
	var scale := pow(10.0, decimals)
	return roundf(value * scale) / scale


## One step of an upgrade: a fifth of the tier band, at least the smallest displayed unit.
static func affix_step(def: Dictionary, tier: int) -> float:
	var band := affix_band(def, tier)
	var unit := 1.0 / pow(10.0, affix_decimals(def))
	return maxf(unit, round_value(def, (band.y - band.x) / 5.0))


static func roll_affix_value(def: Dictionary, tier: int, rng: RandomNumberGenerator) -> float:
	var band := affix_band(def, tier)
	return round_value(def, rng.randf_range(band.x, band.y))


static func affix_text(entry: Dictionary) -> String:
	var def := Db.affix(entry["id"])
	var value := float(entry["value"])
	var shown := ("%.1f" % value) if affix_decimals(def) > 0 else str(roundi(value))
	return String(def["text"]).replace("{v}", shown)


static func affix_name(entry: Dictionary) -> String:
	var def := Db.affix(entry["id"])
	var names: Array = def["names"]
	return names[mini(int(entry["tier"]) - 1, names.size() - 1)]


## Rares are named for their highest-tier prefix and suffix; magics use every affix they have.
static func compose_name(item: Dictionary) -> String:
	if String(item.get("fixed_name", "")) != "":
		return item["fixed_name"]
	var prefixes: Array = []
	var suffixes: Array = []
	for entry: Dictionary in item["affixes"]:
		if Db.affix(entry["id"])["kind"] == "prefix":
			prefixes.append(entry)
		else:
			suffixes.append(entry)
	var top_prefix := _top_tier(prefixes)
	var top_suffix := _top_tier(suffixes)
	var parts: Array[String] = []
	if not top_prefix.is_empty():
		parts.append(affix_name(top_prefix))
	parts.append(item["base"])
	if not top_suffix.is_empty():
		parts.append(affix_name(top_suffix))
	return " ".join(parts)


static func _top_tier(entries: Array) -> Dictionary:
	var best := {}
	for entry: Dictionary in entries:
		if best.is_empty() or int(entry["tier"]) > int(best["tier"]):
			best = entry
	return best


static func slot_matches(def: Dictionary, item: Dictionary) -> bool:
	var slot: String = item["slot"]
	for token: String in def["slots"]:
		match token:
			"any":
				return true
			"armor":
				if is_armor_slot(slot):
					return true
			"ring":
				if slot == "ring":
					return true
			"weapon":
				if slot == "weapon" or slot == "sub":
					return true
			_:
				if token == slot:
					return true
	return false


## Stat totals contributed by one item's affixes.
static func affix_totals(item: Dictionary) -> Dictionary:
	var totals := {}
	for entry: Dictionary in item["affixes"]:
		var stat: String = Db.affix(entry["id"])["stat"]
		totals[stat] = float(totals.get(stat, 0.0)) + float(entry["value"])
	return totals


## The item's own armor or damage after upgrades and +% affixes.
static func effective_value(item: Dictionary) -> int:
	var value := upgraded_value(item)
	var totals := affix_totals(item)
	if item["slot"] == "weapon" or item["slot"] == "sub":
		value = floori(value * (1.0 + float(totals.get("damage_pct", 0.0)) / 100.0))
	elif is_armor_slot(item["slot"]):
		value = floori(value * (1.0 + float(totals.get("armor_pct", 0.0)) / 100.0))
	return value


static func make(slot: String, family: String, tier: int, variant: int, ilvl: int, rarity: String) -> Dictionary:
	var db := Db.base_items()
	var base_name := ""
	if slot == "ring":
		base_name = db["rings"][family]["bases"][tier]
	elif is_armor_slot(slot):
		base_name = db["armor"][family]["bases"][tier][variant]
	else:
		base_name = db["weapons"][family]["bases"][tier][variant]
	return {
		"uid": 0, "slot": slot, "family": family, "base": base_name, "tier": tier, "ilvl": ilvl,
		"rarity": rarity, "affixes": [], "upgrades": 0, "gems_spent": 0, "name": base_name,
		"fixed_name": "", "power": "", "set_id": "",
	}
