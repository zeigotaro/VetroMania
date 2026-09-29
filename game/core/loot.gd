class_name Loot
extends RefCounted
## Drop tables, rarity odds with Loot Luck, item rolls and bad-luck protection
## (docs/design/progression-and-loot.md#drops). Every function takes the RNG so runs are reproducible.

const DROP_TABLES := {
	"fodder": {"nothing": 70.0, "bucks": 17.0, "consumable": 6.0, "gear": 5.0, "gem": 2.0},
	"elite": {"nothing": 30.0, "bucks": 30.0, "consumable": 10.0, "gear": 20.0, "gem": 10.0},
}
const ELITE_ROLLS := 3
## Diminishing returns constant K per tier; magic has no cap (-1).
const LUCK_K := {"magic": -1.0, "rare": 600.0, "set": 500.0, "legendary": 250.0}
const PITY_LEGENDARY := 40
const PITY_SET := 30
const SLOT_WEIGHTS := {"armor": 60.0, "weapon": 25.0, "ring": 15.0}
const FORCED_RARE_UP := {
	"boss": {"rare": 65.0, "set": 10.0, "legendary": 25.0},
	"chest": {"rare": 75.0, "set": 10.0, "legendary": 15.0},
}
const GEM_PACKS := {
	"mob": {"white": 70.0, "blue": 25.0, "ruby": 5.0},
	"boss": {"blue": 70.0, "ruby": 30.0},
	"chest": {"white": 40.0, "blue": 45.0, "ruby": 15.0},
}
const PACK_SIZE := {"white": 1, "blue": 3, "ruby": 5}
const MAX_PREFIXES := {"magic": 1, "rare": 3, "legendary": 3, "set": 3}
const AFFIX_COUNT := {"common": [0, 0], "magic": [1, 2], "rare": [3, 5], "set": [2, 3], "legendary": [4, 4]}
const RING_LEAN_WEIGHT := 3.0
const TOP_TIER_CHANCE := 0.6


static func new_counters() -> Dictionary:
	return {"since_legendary": 0, "since_set": 0}


## Multiplier on a rarity's weight: 1 + LL_t / 100 where LL_t = LL x K / (LL + K).
static func luck_factor(rarity: String, luck: float) -> float:
	if luck <= 0.0 or rarity == "common":
		return 1.0
	var k: float = LUCK_K[rarity]
	var effective := luck if k < 0.0 else luck * k / (luck + k)
	return 1.0 + effective / 100.0


static func pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key: String in weights:
		total += maxf(0.0, float(weights[key]))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var last := ""
	for key: String in weights:
		var w := maxf(0.0, float(weights[key]))
		if w <= 0.0:
			continue
		last = key
		if roll < w:
			return key
		roll -= w
	return last


static func rarity_weights(source: String, luck: float, pools: Dictionary = {}) -> Dictionary:
	var out := {}
	var base: Dictionary = Db.base_items()["drop_weights"][source] if Db.base_items()["drop_weights"].has(source) else FORCED_RARE_UP[source]
	for rarity: String in Consts.RARITIES:
		var w := float(base.get(rarity, 0.0))
		if rarity == "legendary" and _pool(pools, "legendary").is_empty():
			w = 0.0
		if rarity == "set" and _pool(pools, "set").is_empty():
			w = 0.0
		out[rarity] = w * luck_factor(rarity, luck)
	return out


static func _pool(pools: Dictionary, key: String) -> Array:
	return pools.get(key, [])


## Picks a rarity for a drop and applies bad-luck protection. Rare-or-better drops count toward the pity counters.
static func pick_rarity(rng: RandomNumberGenerator, source: String, luck: float, counters: Dictionary, pools: Dictionary = {}) -> String:
	var rarity := pick_weighted(rng, rarity_weights(source, luck, pools))
	if rarity == "":
		rarity = "common"
	if rarity in ["rare", "set", "legendary"]:
		var legendary_due := int(counters["since_legendary"]) >= PITY_LEGENDARY and not _pool(pools, "legendary").is_empty()
		var set_due := int(counters["since_set"]) >= PITY_SET and not _pool(pools, "set").is_empty()
		if legendary_due:
			rarity = "legendary"
		elif set_due and rarity == "rare":
			rarity = "set"
		counters["since_legendary"] = 0 if rarity == "legendary" else int(counters["since_legendary"]) + 1
		counters["since_set"] = 0 if rarity == "set" else int(counters["since_set"]) + 1
	return rarity


static func pick_slot_kind(rng: RandomNumberGenerator, player_level: int) -> String:
	var kind := pick_weighted(rng, SLOT_WEIGHTS)
	if kind == "ring" and player_level < Consts.RING_DROP_MIN_LEVEL:
		return "armor"
	return kind


static func _pick_family(rng: RandomNumberGenerator, kind: String) -> Array:
	var db := Db.base_items()
	match kind:
		"armor":
			var slot: String = Consts.ARMOR_SLOTS[rng.randi() % Consts.ARMOR_SLOTS.size()]
			return [slot, slot]
		"ring":
			var rings: Array = db["rings"].keys()
			return ["ring", rings[rng.randi() % rings.size()]]
		_:
			var weapons: Array = db["weapons"].keys()
			var family: String = weapons[rng.randi() % weapons.size()]
			return [db["weapons"][family]["slot"], family]


static func slot_for_family(family: String) -> String:
	var db := Db.base_items()
	if db["armor"].has(family):
		return family
	if db["rings"].has(family):
		return "ring"
	return db["weapons"][family]["slot"]


static func roll_gear(rng: RandomNumberGenerator, ilvl: int, rarity: String, player_level: int, pools: Dictionary = {}, slot_kind: String = "") -> Dictionary:
	var item: Dictionary
	if rarity == "legendary" and not _pool(pools, "legendary").is_empty():
		item = _make_legendary(rng, ilvl, pools)
	elif rarity == "set" and not _pool(pools, "set").is_empty():
		item = _make_set_piece(rng, ilvl, pools)
	else:
		if rarity in ["legendary", "set"]:
			rarity = "rare"
		var kind := slot_kind if slot_kind != "" else pick_slot_kind(rng, player_level)
		var pair := _pick_family(rng, kind)
		if pair[0] == "ring" and rarity == "common":
			rarity = "magic"
		item = _make_base(rng, pair[0], pair[1], ilvl, rarity)
		_roll_affixes(rng, item, rng.randi_range(AFFIX_COUNT[rarity][0], AFFIX_COUNT[rarity][1]))
	item["name"] = Items.compose_name(item)
	return item


static func _make_base(rng: RandomNumberGenerator, slot: String, family: String, ilvl: int, rarity: String) -> Dictionary:
	return Items.make(slot, family, Items.base_tier(ilvl), rng.randi() % 2, ilvl, rarity)


static func _make_legendary(rng: RandomNumberGenerator, ilvl: int, pools: Dictionary) -> Dictionary:
	var pool: Array = pools["legendary"]
	var entry: Dictionary = pool[rng.randi() % pool.size()]
	var family: String = entry["family"]
	var item := _make_base(rng, slot_for_family(family), family, ilvl, "legendary")
	item["fixed_name"] = entry["name"]
	item["power"] = entry["power"]
	item["legendary_id"] = entry["id"]
	_roll_affixes(rng, item, 4)
	return item


static func _make_set_piece(rng: RandomNumberGenerator, ilvl: int, pools: Dictionary) -> Dictionary:
	var pool: Array = pools["set"]
	var set_def: Dictionary = pool[rng.randi() % pool.size()]
	var pieces: Array = set_def["pieces"]
	var piece: Dictionary = pieces[rng.randi() % pieces.size()]
	var family: String = piece["family"]
	var item := _make_base(rng, slot_for_family(family), family, ilvl, "set")
	item["fixed_name"] = piece["name"]
	item["set_id"] = set_def["id"]
	var tier := Items.max_affix_tier(ilvl)
	for id: String in piece["affixes"]:
		var def := Db.affix(id)
		item["affixes"].append({"id": id, "tier": tier, "value": Items.roll_affix_value(def, tier, rng)})
	return item


static func _roll_affixes(rng: RandomNumberGenerator, item: Dictionary, count: int) -> void:
	var max_each := int(MAX_PREFIXES.get(item["rarity"], 0))
	var prefixes := 0
	var suffixes := 0
	var groups := {}
	for _i in count:
		var weights := {}
		var by_id := {}
		for def: Dictionary in Db.affixes():
			if groups.has(def["group"]) or not Items.slot_matches(def, item):
				continue
			if def["kind"] == "prefix" and prefixes >= max_each:
				continue
			if def["kind"] == "suffix" and suffixes >= max_each:
				continue
			weights[def["id"]] = _ring_weight(item, def)
			by_id[def["id"]] = def
		var id := pick_weighted(rng, weights)
		if id == "":
			break
		var def: Dictionary = by_id[id]
		groups[def["group"]] = true
		if def["kind"] == "prefix":
			prefixes += 1
		else:
			suffixes += 1
		var tier := _roll_tier(rng, item["ilvl"])
		item["affixes"].append({"id": id, "tier": tier, "value": Items.roll_affix_value(def, tier, rng)})


static func _ring_weight(item: Dictionary, def: Dictionary) -> float:
	if item["slot"] != "ring":
		return 1.0
	var lean: String = Items.family_data(item).get("lean", "")
	return RING_LEAN_WEIGHT if lean in def.get("tags", []) else 1.0


static func _roll_tier(rng: RandomNumberGenerator, ilvl: int) -> int:
	var top := Items.max_affix_tier(ilvl)
	if top == 1 or rng.randf() < TOP_TIER_CHANCE:
		return top
	return top - 1


static func bucks_amount(rng: RandomNumberGenerator, level: int, elite: bool = false, bonus_pct: float = 0.0, salty: bool = false) -> int:
	var amount := (2.0 + 1.5 * level) * rng.randf_range(0.8, 1.2)
	if elite:
		amount *= 5.0
	if salty:
		amount *= float(Db.elite()["salty_bucks_mult"])
	return maxi(1, roundi(amount * (1.0 + bonus_pct / 100.0)))


static func roll_gem_pack(rng: RandomNumberGenerator, source: String) -> Dictionary:
	var table_key := "mob" if source in ["fodder", "elite"] else source
	var color := pick_weighted(rng, GEM_PACKS[table_key])
	var kind := "armor" if rng.randf() < 0.5 else "weapon"
	return {"type": "gem", "kind": kind, "color": color, "count": int(PACK_SIZE[color])}


static func roll_consumable(rng: RandomNumberGenerator) -> Dictionary:
	var weights: Dictionary = Db.legendary_data()["consumable_weights"]
	return {"type": "consumable", "id": pick_weighted(rng, weights)}


## The Rival tally milestone: any drop happens 25% more often, taken out of the "nothing" weight.
static func with_rival(table: Dictionary, mult: float) -> Dictionary:
	var out := table.duplicate()
	var extra := 0.0
	for key: String in table:
		if key != "nothing":
			out[key] = float(table[key]) * mult
			extra += float(out[key]) - float(table[key])
	out["nothing"] = maxf(0.0, float(table["nothing"]) - extra)
	return out


## ctx: source (fodder|elite|boss|chest), level, player_level, luck, counters, pools, rival,
##      bucks_pct, salty, rival_mult, extra_gem_chance
static func roll_drops(rng: RandomNumberGenerator, ctx: Dictionary) -> Array:
	var source: String = ctx["source"]
	var level := int(ctx["level"])
	var drops: Array = []
	var pools: Dictionary = ctx.get("pools", {})
	var counters: Dictionary = ctx["counters"]
	var luck := float(ctx.get("luck", 0.0))
	var player_level := int(ctx.get("player_level", 1))
	match source:
		"boss", "chest":
			var ilvl := level + (2 if source == "boss" else 0)
			var rarity := pick_rarity(rng, source, luck, counters, pools)
			drops.append({"type": "gear", "item": roll_gear(rng, ilvl, rarity, player_level, pools)})
			if source == "boss" or rng.randf() < 0.5:
				drops.append(roll_gem_pack(rng, source))
			if source == "boss":
				drops.append({"type": "bucks", "amount": bucks_amount(rng, level, false, float(ctx.get("bucks_pct", 0.0))) * 12})
		_:
			var table: Dictionary = DROP_TABLES[source]
			if ctx.get("rival", false):
				table = with_rival(table, float(ctx.get("rival_mult", 1.25)))
			var rolls := ELITE_ROLLS if source == "elite" else 1
			for _i in rolls:
				var drop := _roll_once(rng, table, source, level, player_level, luck, counters, pools, ctx)
				if not drop.is_empty():
					drops.append(drop)
	return drops


static func _roll_once(rng: RandomNumberGenerator, table: Dictionary, source: String, level: int, player_level: int, luck: float, counters: Dictionary, pools: Dictionary, ctx: Dictionary) -> Dictionary:
	match pick_weighted(rng, table):
		"bucks":
			var amount := bucks_amount(rng, level, source == "elite", float(ctx.get("bucks_pct", 0.0)), bool(ctx.get("salty", false)))
			return {"type": "bucks", "amount": amount}
		"consumable":
			return roll_consumable(rng)
		"gear":
			var rarity := pick_rarity(rng, source, luck, counters, pools)
			return {"type": "gear", "item": roll_gear(rng, level, rarity, player_level, pools)}
		"gem":
			return roll_gem_pack(rng, source)
	return {}
