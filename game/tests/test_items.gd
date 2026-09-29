extends TestCase
## Item math against the worked examples in docs/design/progression-and-loot.md.


func _boots(upgrades: int = 0) -> Dictionary:
	var item := Items.make("boots", "boots", 1, 0, 22, "rare")
	item["upgrades"] = upgrades
	return item


func _affix(id: String, tier: int, value: float) -> Dictionary:
	return {"id": id, "tier": tier, "value": value}


func test_mockup_boots_and_upgrade_ladder() -> void:
	var boots := _boots()
	eq(boots["base"], "Mag-Boots", "Exceptional boots from the mockup")
	eq(Items.base_value(boots), 44, "0.9 x 44.2 x 1.1")
	var ladder := [44, 48, 52, 57, 61, 66]
	for n in ladder.size():
		eq(Items.upgraded_value(boots, n), ladder[n], "boots +%d" % n)
	eq(Items.required_level(boots), 18, "iLvl 22 requires Lv 18")


func test_legendary_beam_bat_is_50_at_ilvl_21() -> void:
	var bat := Items.make("weapon", "bat", 1, 0, 21, "legendary")
	eq(bat["base"], "Beam Bat")
	eq(Items.base_value(bat), 50)
	eq(Items.required_level(bat), 19, "legendary requires iLvl - 2")


func test_required_level_floor_and_rarity() -> void:
	eq(Items.required_level(Items.make("boots", "boots", 0, 0, 3, "common")), 1)
	eq(Items.required_level(Items.make("boots", "boots", 0, 0, 10, "set")), 8)


func test_common_items_upgrade_by_15_percent() -> void:
	var bat := Items.make("weapon", "bat", 0, 0, 1, "common")
	eq(Items.base_value(bat), 10)
	eq(Items.upgraded_value(bat, 1), 11, "floor(10 x 1.15)")
	eq(Items.upgraded_value(bat, 2), 13)
	eq(Items.upgraded_value(bat, 5), 17, "floor(10 x 1.75)")


func test_base_tiers_and_affix_tiers_by_item_level() -> void:
	eq([Items.base_tier(1), Items.base_tier(16), Items.base_tier(17), Items.base_tier(33), Items.base_tier(34), Items.base_tier(50)], [0, 0, 1, 1, 2, 2])
	var expected := {1: 1, 12: 1, 13: 2, 24: 2, 25: 3, 36: 3, 37: 4, 47: 4, 48: 5, 50: 5}
	for ilvl: int in expected:
		eq(Items.max_affix_tier(ilvl), expected[ilvl], "affix tier at iLvl %d" % ilvl)


func test_affix_band_and_upgrade_step_match_the_mockup_tooltip() -> void:
	## +1 -> +15 spans five bands of 2.8. At iLvl 22 the tier-2 band is 3.8-6.6, a +6 DEX roll
	## fits, and one upgrade step (a fifth of the band, at least 1) makes it +7.
	var ninja := Db.affix("ninja")
	var band := Items.affix_band(ninja, 2)
	near(band.x, 3.8, 0.001)
	near(band.y, 6.6, 0.001)
	near(Items.affix_step(ninja, 2), 1.0, 0.001, "step floors at 1")
	near(Items.affix_step(Db.affix("sturdy"), 5), 2.0, 0.001, "armor% tier 5: band 10 -> step 2")
	near(Items.affix_step(Db.affix("vampiric"), 3), 0.1, 0.001, "decimals keep a 0.1 step")


func test_rare_name_uses_the_highest_tier_prefix_and_suffix() -> void:
	var boots := _boots()
	boots["affixes"] = [
		_affix("insulated", 1, 9.0), _affix("overclocked", 3, 14.0), _affix("lucky", 2, 8.0),
		_affix("ninja", 1, 6.0), _affix("leeroy", 2, 18.0),
	]
	eq(Items.compose_name(boots), "Overclocked Mag-Boots of the Leeroy", "the mockup's boots")


func test_magic_and_common_names() -> void:
	var magic := Items.make("helmet", "helmet", 1, 0, 20, "magic")
	magic["affixes"] = [_affix("hearty", 2, 30.0)]
	eq(Items.compose_name(magic), "Hearty Helm-Visor")
	magic["affixes"].append(_affix("bro", 2, 5.0))
	eq(Items.compose_name(magic), "Hearty Helm-Visor of the Bro")
	eq(Items.compose_name(Items.make("boots", "boots", 0, 1, 5, "common")), "Moon Boots")


func test_tiered_affix_names() -> void:
	var entry := _affix("sturdy", 5, 60.0)
	eq(Items.affix_name(entry), "Adamant")
	eq(Items.affix_name(_affix("sturdy", 1, 10.0)), "Sturdy")
	eq(Items.affix_name(_affix("lucky", 4, 12.0)), "Lucky", "single-name affixes keep their name")


func test_percent_affixes_scale_the_item_itself() -> void:
	var boots := _boots()
	boots["affixes"] = [_affix("sturdy", 2, 50.0)]
	eq(Items.effective_value(boots), 66, "44 x 1.5")
	var bat := Items.make("weapon", "bat", 0, 0, 1, "rare")
	bat["affixes"] = [_affix("sharp", 1, 20.0)]
	eq(Items.effective_value(bat), floori(Items.base_value(bat) * 1.2))


func test_rings_have_no_base_value() -> void:
	var ring := Items.make("ring", "quantum_band", 1, 0, 20, "magic")
	eq(Items.base_value(ring), 0)
	eq(Items.upgraded_value(ring, 3), 0)
	eq(ring["base"], "Quantum Band")


func test_slot_rules_for_affixes() -> void:
	var boots := _boots()
	check(Items.slot_matches(Db.affix("overclocked"), boots), "Overclocked fits boots")
	check(not Items.slot_matches(Db.affix("overclocked"), Items.make("helmet", "helmet", 0, 0, 5, "rare")), "not helmets")
	check(Items.slot_matches(Db.affix("hearty"), Items.make("ring", "halo_loop", 0, 0, 20, "magic")), "armor+ring affix fits rings")
	check(not Items.slot_matches(Db.affix("hearty"), Items.make("weapon", "bat", 0, 0, 5, "rare")), "not weapons")
	check(Items.slot_matches(Db.affix("sharp"), Items.make("sub", "mitt_cannon", 0, 0, 5, "rare")), "weapon affix fits sub-weapons")
	check(not Items.slot_matches(Db.affix("sharp"), Items.make("chest", "chest", 0, 0, 5, "rare")), "not armor")
	check(Items.slot_matches(Db.affix("bro"), Items.make("gloves", "gloves", 0, 0, 5, "rare")), "stat suffixes fit anything")


func test_sell_price() -> void:
	eq(Items.sell_price(_boots()), 880, "10 x 22 x 4 for a rare")
	eq(Items.sell_price(Items.make("boots", "boots", 0, 0, 7, "common")), 70)


func test_data_lint_no_affix_grants_traversal() -> void:
	var seen := {}
	for def: Dictionary in Db.affixes():
		check(def["stat"] in Gear.STAT_KEYS, "affix %s grants a known stat" % def["id"])
		check(float(def["min"]) < float(def["max"]), "%s has a range" % def["id"])
		check(not def["names"].is_empty() and not def["slots"].is_empty(), "%s has names and slots" % def["id"])
		check(def["kind"] in ["prefix", "suffix"], "%s kind" % def["id"])
		check(not seen.has(def["id"]), "%s is unique" % def["id"])
		seen[def["id"]] = true
		for banned in ["traversal", "gate", "jump", "fly", "wall", "door"]:
			check(String(def["stat"]).find(banned) == -1 and String(def["id"]).find(banned) == -1, "%s must not touch traversal (%s)" % [def["id"], banned])


func test_base_item_catalogue_is_complete() -> void:
	var db := Db.base_items()
	var armor := 0
	for family: String in db["armor"]:
		var bases: Array = db["armor"][family]["bases"]
		eq(bases.size(), 3, "%s has three tiers" % family)
		for tier: Array in bases:
			eq(tier.size(), 2, "%s has two variants per tier" % family)
			armor += 2
	eq(armor, 36, "36 armor bases")
	var weapons := 0
	for family: String in db["weapons"]:
		for tier: Array in db["weapons"][family]["bases"]:
			eq(tier.size(), 2)
			weapons += 2
	eq(weapons, 42, "42 weapon bases")
	eq(Consts.ARMOR_SLOTS.size(), db["armor"].size(), "one family per armor slot")
