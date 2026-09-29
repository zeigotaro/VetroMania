extends TestCase
## Drop tables, Loot Luck, bad-luck protection and item rolls (docs/design/progression-and-loot.md#drops).

const POOLS_KEYS := ["legendary", "set"]


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _pools() -> Dictionary:
	var data := Db.legendary_data()
	return {"legendary": data["legendaries"], "set": data["sets"]}


func _ctx(source: String, level: int = 5, extra: Dictionary = {}) -> Dictionary:
	var ctx := {"source": source, "level": level, "player_level": 5, "luck": 0.0, "counters": Loot.new_counters(), "pools": {}}
	ctx.merge(extra, true)
	return ctx


func test_luck_curve_matches_the_doc() -> void:
	near(Loot.luck_factor("rare", 100.0), 1.857, 0.005, "rare x1.86 at 100% LL")
	near(Loot.luck_factor("legendary", 100.0), 1.714, 0.005, "legendary x1.71 at 100% LL")
	near(Loot.luck_factor("magic", 100.0), 2.0, 0.0001, "magic is uncapped")
	near(Loot.luck_factor("rare", 18.0), 1.175, 0.005, "about x1.17 at the mockup's 18%")
	near(Loot.luck_factor("legendary", 18.0), 1.168, 0.005)
	near(Loot.luck_factor("legendary", 0.0), 1.0, 0.0001)
	near(Loot.luck_factor("common", 500.0), 1.0, 0.0001, "common weight never moves")


func test_rarity_weights_follow_the_table() -> void:
	var w := Loot.rarity_weights("fodder", 0.0, _pools())
	eq([w["common"], w["magic"], w["rare"], w["set"], w["legendary"]], [55.0, 32.0, 10.0, 2.0, 1.0], "fodder weights")
	var e := Loot.rarity_weights("elite", 0.0, _pools())
	eq([e["common"], e["magic"], e["rare"], e["set"], e["legendary"]], [30.0, 40.0, 22.0, 5.0, 3.0], "elite weights")
	var empty := Loot.rarity_weights("fodder", 0.0, {})
	eq([empty["set"], empty["legendary"]], [0.0, 0.0], "no pool, no set or legendary")
	var lucky := Loot.rarity_weights("fodder", 100.0, _pools())
	near(lucky["rare"], 10.0 * 1.857, 0.06)
	near(lucky["common"], 55.0, 0.0001)


func test_fodder_drop_frequencies() -> void:
	var rng := _rng(101)
	var counts := {"nothing": 0, "bucks": 0, "consumable": 0, "gear": 0, "gem": 0}
	var n := 40000
	for _i in n:
		var drops := Loot.roll_drops(rng, _ctx("fodder"))
		if drops.is_empty():
			counts["nothing"] += 1
		else:
			eq(drops.size(), 1, "fodder rolls once")
			counts[drops[0]["type"]] += 1
	near(counts["nothing"] / float(n), 0.70, 0.01, "nothing 70%")
	near(counts["bucks"] / float(n), 0.17, 0.01, "Vetro-Bucks 17%")
	near(counts["consumable"] / float(n), 0.06, 0.007, "consumable 6%")
	near(counts["gear"] / float(n), 0.05, 0.006, "gear 5%")
	near(counts["gem"] / float(n), 0.02, 0.004, "gem pack 2%")


func test_elites_roll_three_times() -> void:
	var rng := _rng(202)
	var total := 0
	var n := 10000
	for _i in n:
		total += Loot.roll_drops(rng, _ctx("elite", 7)).size()
	near(total / float(n), 3.0 * 0.70, 0.05, "3 rolls, 70% drop each")


func test_rival_moves_weight_out_of_nothing() -> void:
	var table := Loot.with_rival(Loot.DROP_TABLES["fodder"], 1.25)
	near(table["nothing"], 62.5, 0.0001)
	near(table["gear"], 6.25, 0.0001)
	var sum := 0.0
	for key: String in table:
		sum += table[key]
	near(sum, 100.0, 0.0001, "the table still sums to 100")


func test_bad_luck_protection() -> void:
	var counters := Loot.new_counters()
	counters["since_legendary"] = 40
	var pools := _pools()
	var rng := _rng(303)
	var rarity := ""
	for _i in 50:
		rarity = Loot.pick_rarity(rng, "elite", 0.0, counters, pools)
		if rarity in ["rare", "set", "legendary"]:
			break
	eq(rarity, "legendary", "the next rare-or-better after 40 without a legendary is legendary")
	eq(counters["since_legendary"], 0, "the counter resets")
	var set_counters := Loot.new_counters()
	set_counters["since_set"] = 30
	var picked := ""
	for _i in 50:
		picked = Loot.pick_rarity(rng, "elite", 0.0, set_counters, pools)
		if picked in ["rare", "set", "legendary"]:
			break
	check(picked in ["set", "legendary"], "set pity forces a set unless a legendary rolled first")
	if picked == "set":
		eq(set_counters["since_set"], 0)


func test_pity_counts_only_rare_or_better() -> void:
	var counters := Loot.new_counters()
	var rng := _rng(404)
	var rare_up := 0
	for _i in 500:
		var rarity := Loot.pick_rarity(rng, "fodder", 0.0, counters, {})
		if rarity == "rare":
			rare_up += 1
	eq(counters["since_legendary"], rare_up, "only rares count with an empty pool")


func test_no_rings_before_level_20() -> void:
	var rng := _rng(505)
	var rings_19 := 0
	var rings_20 := 0
	for _i in 4000:
		if Loot.pick_slot_kind(rng, 19) == "ring":
			rings_19 += 1
		if Loot.pick_slot_kind(rng, 20) == "ring":
			rings_20 += 1
	eq(rings_19, 0, "ring rolls become armor below Lv 20")
	near(rings_20 / 4000.0, 0.15, 0.03, "15% rings from Lv 20")


func test_common_rings_are_promoted_to_magic() -> void:
	var rng := _rng(606)
	for _i in 200:
		var ring := Loot.roll_gear(rng, 25, "common", 30, {}, "ring")
		eq(ring["slot"], "ring")
		eq(ring["rarity"], "magic", "no common rings")
		check(ring["affixes"].size() >= 1, "rings roll affixes only")
		eq(Items.base_value(ring), 0)


func test_boss_drops_are_guaranteed_rare_or_better() -> void:
	var rng := _rng(707)
	var pools := _pools()
	var legendaries := 0
	for _i in 300:
		var ctx := _ctx("boss", 10, {"pools": pools})
		var drops := Loot.roll_drops(rng, ctx)
		var gear := 0
		var gems := 0
		var bucks := 0
		for drop: Dictionary in drops:
			match drop["type"]:
				"gear":
					gear += 1
					check(drop["item"]["rarity"] in ["rare", "set", "legendary"], "boss gear is rare or better")
					eq(drop["item"]["ilvl"], 12, "boss drop is boss level + 2")
					if drop["item"]["rarity"] == "legendary":
						legendaries += 1
				"gem":
					gems += 1
					check(drop["color"] in ["blue", "ruby"], "boss packs are blue or ruby")
					eq(drop["count"], 3 if drop["color"] == "blue" else 5)
				"bucks":
					bucks += 1
					check(drop["amount"] > 0)
		eq([gear, gems, bucks], [1, 1, 1], "one gear, one pack, one pile")
	near(legendaries / 300.0, 0.25, 0.08, "about 25% of boss gear is legendary")


func test_chest_drops() -> void:
	var rng := _rng(808)
	var packs := 0
	for _i in 600:
		var drops := Loot.roll_drops(rng, _ctx("chest", 8, {"pools": _pools()}))
		var gear := 0
		for drop: Dictionary in drops:
			if drop["type"] == "gear":
				gear += 1
				check(drop["item"]["rarity"] in ["rare", "set", "legendary"])
				eq(drop["item"]["ilvl"], 8, "a chest uses its area's level")
			elif drop["type"] == "gem":
				packs += 1
		eq(gear, 1)
	near(packs / 600.0, 0.5, 0.07, "50% chance of a gem pack")


func test_gem_pack_tables() -> void:
	var rng := _rng(909)
	var colors := {"white": 0, "blue": 0, "ruby": 0}
	var armor := 0
	for _i in 6000:
		var pack := Loot.roll_gem_pack(rng, "fodder")
		colors[pack["color"]] += 1
		eq(pack["count"], Loot.PACK_SIZE[pack["color"]])
		if pack["kind"] == "armor":
			armor += 1
	near(colors["white"] / 6000.0, 0.70, 0.03)
	near(colors["blue"] / 6000.0, 0.25, 0.03)
	near(colors["ruby"] / 6000.0, 0.05, 0.02)
	near(armor / 6000.0, 0.5, 0.03, "armor and weapon gems 50/50")


func test_random_items_obey_the_affix_rules() -> void:
	var rng := _rng(1001)
	var pools := _pools()
	for i in 3000:
		var ilvl := rng.randi_range(1, 50)
		var rarity: String = ["common", "magic", "rare", "rare", "legendary", "set"][i % 6]
		var item := Loot.roll_gear(rng, ilvl, rarity, 50, pools)
		var kinds := {"prefix": 0, "suffix": 0}
		var groups := {}
		for entry: Dictionary in item["affixes"]:
			var def := Db.affix(entry["id"])
			kinds[def["kind"]] += 1
			check(not groups.has(def["group"]), "no stacking within a group (%s)" % def["group"])
			groups[def["group"]] = true
			check(Items.slot_matches(def, item), "%s is legal on %s" % [def["id"], item["slot"]])
			check(entry["tier"] <= Items.max_affix_tier(ilvl), "tier %d needs a higher iLvl than %d" % [entry["tier"], ilvl])
			var band := Items.affix_band(def, entry["tier"])
			check(entry["value"] >= band.x - 0.51 and entry["value"] <= band.y + 0.51, "%s value %s is inside its tier band" % [def["id"], str(entry["value"])])
		match item["rarity"]:
			"common":
				eq(item["affixes"].size(), 0, "common has none")
			"magic":
				check(item["affixes"].size() >= 1 and item["affixes"].size() <= 2, "magic 1-2")
				check(kinds["prefix"] <= 1 and kinds["suffix"] <= 1, "magic: one prefix and one suffix at most")
			"rare":
				check(item["affixes"].size() >= 3 and item["affixes"].size() <= 5, "rare 3-5")
				check(kinds["prefix"] <= 3 and kinds["suffix"] <= 3, "rare: three of each at most")
			"legendary":
				eq(item["affixes"].size(), 4, "legendary rolls 4")
				check(String(item["power"]) != "" and String(item["fixed_name"]) != "", "and a fixed power and name")
			"set":
				check(String(item["set_id"]) != "" and String(item["fixed_name"]) != "", "set pieces have a set and a name")
		eq(item["name"], Items.compose_name(item))
		eq(item["tier"], Items.base_tier(ilvl), "base tier follows iLvl")


func test_legendary_and_set_items_use_the_data() -> void:
	var rng := _rng(1102)
	var pools := _pools()
	var names := {}
	for _i in 60:
		var item := Loot.roll_gear(rng, 10, "legendary", 10, pools)
		names[item["name"]] = true
		check(item["fixed_name"] in ["The Bobson", "Leeroy's Last Stand", "Cardboard Box", "Power Glove of Badness", "Mullet of Theseus"], "legendary name from data")
		eq(Items.slot_matches(Db.affix("hearty"), item), item["slot"] != "weapon", "sanity on slot")
	check(names.size() >= 4, "several legendaries appear")
	var piece := Loot.roll_gear(rng, 10, "set", 10, pools)
	eq(piece["set_id"], "dugnutts_dugout")
	check(piece["fixed_name"].begins_with("Dugnutt's"), "piece name")
	check(piece["affixes"].size() in [2, 3], "set pieces carry 2-3 fixed affixes")
	var fallback := Loot.roll_gear(rng, 10, "legendary", 10, {})
	eq(fallback["rarity"], "rare", "no pool means a rare, never a broken item")


func test_bucks_scale_with_level_and_elites() -> void:
	var rng := _rng(1203)
	var normal := 0.0
	var elite := 0.0
	for _i in 2000:
		normal += Loot.bucks_amount(rng, 10)
		elite += Loot.bucks_amount(rng, 10, true)
	near(normal / 2000.0, 17.0, 0.6, "2 + 1.5 x 10")
	near(elite / normal, 5.0, 0.2, "elites x5")
	var salty := Loot.bucks_amount(_rng(5), 10, true, 0.0, true)
	var plain := Loot.bucks_amount(_rng(5), 10, true, 0.0, false)
	check(salty > plain, "Extra Salty elites drop more")


func test_runs_are_reproducible() -> void:
	var a := Loot.roll_drops(_rng(42), _ctx("boss", 10, {"pools": _pools()}))
	var b := Loot.roll_drops(_rng(42), _ctx("boss", 10, {"pools": _pools()}))
	eq(JSON.stringify(a), JSON.stringify(b), "same seed, same drops")


func test_rings_lean_by_family() -> void:
	var rng := _rng(1304)
	var offense_on_quantum := 0
	var defense_on_quantum := 0
	for _i in 800:
		var ring := Loot.roll_gear(rng, 30, "rare", 40, {}, "ring")
		if ring["family"] != "quantum_band":
			continue
		for entry: Dictionary in ring["affixes"]:
			var tags: Array = Db.affix(entry["id"])["tags"]
			if "offense" in tags:
				offense_on_quantum += 1
			if "defense" in tags:
				defense_on_quantum += 1
	check(offense_on_quantum > defense_on_quantum, "Quantum Bands favor offense (%d vs %d)" % [offense_on_quantum, defense_on_quantum])
