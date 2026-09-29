extends TestCase
## Gear aggregation, derived stats and the upgrade bench.


func _affix(id: String, tier: int, value: float) -> Dictionary:
	return {"id": id, "tier": tier, "value": value}


func _boots(upgrades: int = 1) -> Dictionary:
	var item := Items.make("boots", "boots", 1, 0, 22, "rare")
	item["upgrades"] = upgrades
	item["affixes"] = [_affix("overclocked", 3, 14.0), _affix("lucky", 2, 8.0), _affix("ninja", 2, 6.0)]
	return item


func _mockup_equipment() -> Dictionary:
	var chest := Items.make("chest", "chest", 1, 0, 22, "rare")
	chest["affixes"] = [_affix("hearty", 3, 30.0)]
	var helmet := Items.make("helmet", "helmet", 1, 0, 22, "rare")
	helmet["affixes"] = [_affix("charged", 3, 16.0)]
	var bat := Items.make("weapon", "bat", 1, 0, 21, "legendary")
	return {"helmet": helmet, "chest": chest, "boots": _boots(), "weapon": bat}


func test_mockup_sheet_is_reproduced_from_equipment() -> void:
	var sheet := Gear.derive(24, {"STR": 3, "CON": 2, "INT": 1, "LCK": 2}, _mockup_equipment())
	eq(sheet["stats"]["STR"], 31)
	eq(sheet["stats"]["CON"], 27)
	eq(sheet["stats"]["INT"], 18)
	eq(sheet["stats"]["DEX"], 29, "23 base + 6 from the boots")
	eq(sheet["stats"]["LCK"], 15)
	eq(sheet["max_hp"], 412, "382 + 30 from the chest affix")
	eq(sheet["max_ep"], 96, "80 + 16 from the helmet affix")
	eq(sheet["atk"], 88, "the 50-damage legendary bat plus floor(1.25 x 31)")
	eq(roundi(sheet["crit_chance"]), 7)
	near(sheet["loot_luck"], 18.0, 0.001, "10% from LCK plus the boots' 8%")
	near(sheet["crit_damage"], 1.75, 0.0001)


func test_armor_total_uses_upgrades() -> void:
	var boots := _boots(1)
	var equipped := {"boots": boots}
	eq(Gear.totals(equipped, 24)["armor"], 48, "44 upgraded once")
	boots["upgrades"] = 2
	eq(Gear.totals(equipped, 24)["armor"], 52)


func test_def_from_total_armor() -> void:
	## 13 from CON 27 plus 255 total armor / 5 = 64, as in the doc.
	eq(Damage.defense(27, 255), 64)


func test_ring_slots_unlock_by_level() -> void:
	check(not Gear.slot_unlocked("ring1", 19))
	check(Gear.slot_unlocked("ring1", 20))
	check(not Gear.slot_unlocked("ring2", 36))
	check(Gear.slot_unlocked("ring2", 37))
	var ring := Items.make("ring", "quantum_band", 1, 0, 25, "magic")
	eq(Gear.equip_error(ring, "ring1", 19), "Slot opens at Lv 20")
	eq(Gear.equip_error(ring, "ring1", 20), "Requires Lv 21", "iLvl 25 needs Lv 21")
	eq(Gear.equip_error(ring, "ring1", 22), "")
	eq(Gear.equip_error(ring, "ring2", 36), "Slot opens at Lv 37")
	eq(Gear.equip_error(ring, "boots", 40), "Wrong slot")
	eq(Gear.equip_error(Items.make("boots", "boots", 1, 0, 22, "rare"), "boots", 17), "Requires Lv 18")
	eq(Gear.equip_error(Items.make("boots", "boots", 1, 0, 22, "rare"), "boots", 18), "")
	eq(Gear.equip_error(Items.make("boots", "boots", 1, 0, 22, "rare"), "helmet", 40), "Wrong slot")


func test_locked_ring_slots_do_not_count() -> void:
	var ring := Items.make("ring", "halo_loop", 0, 0, 10, "magic")
	ring["affixes"] = [_affix("hearty", 1, 50.0)]
	eq(Gear.derive(19, {}, {"ring1": ring})["max_hp"], Stats.max_hp(Stats.base_stat("CON", 19), 19), "ring slot still locked")
	eq(Gear.derive(20, {}, {"ring1": ring})["max_hp"], Stats.max_hp(Stats.base_stat("CON", 20), 20, 50), "unlocked at 20")


func test_mullet_of_theseus_and_leeroy() -> void:
	var helm := Items.make("helmet", "helmet", 0, 0, 10, "legendary")
	helm["power"] = "mullet"
	var at_25 := Gear.derive(25, {}, {"helmet": helm})
	var plain := Stats.final_stats(25, {}, {})
	for stat: String in Stats.NAMES:
		eq(at_25["stats"][stat], plain[stat] + 2, "+2 %s at Lv 25" % stat)
	eq(Gear.derive(9, {}, {"helmet": helm})["stats"]["STR"], Stats.base_stat("STR", 9), "nothing below Lv 10")
	near(Powers.leeroy_mult(0.19), 1.3, 0.0001)
	near(Powers.leeroy_mult(0.2), 1.0, 0.0001)
	eq(Powers.mullet_bonus(49), 4)


func test_set_bonuses() -> void:
	var slugger := Items.make("weapon", "bat", 0, 0, 10, "set")
	slugger["set_id"] = "dugnutts_dugout"
	var mitts := Items.make("gloves", "gloves", 0, 0, 10, "set")
	mitts["set_id"] = "dugnutts_dugout"
	var cap := Items.make("helmet", "helmet", 0, 0, 10, "set")
	cap["set_id"] = "dugnutts_dugout"
	var one := Gear.totals({"weapon": slugger}, 10)
	near(one["bonus"]["crit_chance"], 0.0, 0.0001, "one piece gives nothing")
	var two := Gear.totals({"weapon": slugger, "gloves": mitts}, 10)
	near(two["bonus"]["crit_chance"], 10.0, 0.0001, "2-piece: +10% crit chance")
	check(not two["set_flags"].has("home_runs_crit"))
	var three := Gear.totals({"weapon": slugger, "gloves": mitts, "helmet": cap}, 10)
	check(three["set_flags"].has("home_runs_crit"), "full set: Home Runs always crit")


func test_trait_perks_add_stats() -> void:
	var sheet := Gear.derive(10, {}, {}, {"INT": 2})
	eq(sheet["stats"]["INT"], Stats.base_stat("INT", 10) + 2)


func test_upgrade_ladder_costs_and_caps() -> void:
	var boots := _boots(0)
	var costs: Array[int] = []
	var fees: Array[int] = []
	for step in 5:
		costs.append(Upgrades.gem_cost(boots))
		fees.append(Upgrades.bucks_fee(boots))
		boots["upgrades"] = int(boots["upgrades"]) + 1
	eq(costs, [1, 3, 5, 8, 12] as Array[int], "gem costs")
	eq(fees, [25 * 22 * 1, 25 * 22 * 2, 25 * 22 * 3, 25 * 22 * 4, 25 * 22 * 5] as Array[int], "fee = 25 x iLvl x (n + 1)")
	var caps := {1: 1, 12: 1, 13: 2, 25: 3, 37: 4, 49: 4, 50: 5}
	for level: int in caps:
		eq(Upgrades.cap_for_level(level), caps[level], "cap at Lv %d" % level)
	var item := _boots(1)
	check(not Upgrades.can_upgrade(item, 12), "+1 is the cap at Lv 12")
	check(Upgrades.can_upgrade(item, 13), "+2 opens at Lv 13")
	item["upgrades"] = 2
	check(not Upgrades.can_upgrade(item, 24) and Upgrades.can_upgrade(item, 25), "the cap follows the character, not the item")


func test_mockup_upgrade_step() -> void:
	## Lv 24, boots +1: the next step costs 3 armor gems and gives armor 52 and +7 DEX.
	var boots := _boots(1)
	var preview := Upgrades.preview(boots, 2)
	eq(preview["gems"], 3)
	eq(preview["kind"], "armor")
	eq(preview["value_now"], 48)
	eq(preview["value_next"], 52)
	near(preview["affix_gain"], 1.0, 0.001)
	eq(Upgrades.error_for(boots, 24, {"armor": 2, "weapon": 9}, 9999), "Needs 3 armor gems")
	eq(Upgrades.error_for(boots, 24, {"armor": 3}, 10), "Needs %d Vetro-Bucks" % (25 * 22 * 2))
	eq(Upgrades.error_for(boots, 24, {"armor": 3}, 9999), "")
	var spent := Upgrades.apply(boots, 2)
	eq(spent, 3)
	eq(boots["upgrades"], 2)
	eq(Items.upgraded_value(boots), 52)
	near(boots["affixes"][2]["value"], 7.0, 0.001, "+6 DEX became +7 DEX")
	eq(boots["gems_spent"], 3)
	eq(Upgrades.error_for(boots, 24, {"armor": 99}, 99999), "Reach a higher level to upgrade further")


func test_salvage_refunds_half_the_gems_rounded_down() -> void:
	var boots := _boots(0)
	for _i in 3:
		Upgrades.apply(boots, 0)
	eq(boots["gems_spent"], 1 + 3 + 5)
	eq(Upgrades.salvage_refund(boots), 4)
	eq(Upgrades.salvage_refund(_boots(0)), 0)
	var one := _boots(0)
	Upgrades.apply(one, 0)
	eq(Upgrades.salvage_refund(one), 0, "1 gem spent refunds 0")


func test_gem_kinds() -> void:
	eq(Upgrades.gem_kind(Items.make("ring", "halo_loop", 0, 0, 20, "magic")), "armor", "rings use armor gems")
	eq(Upgrades.gem_kind(Items.make("weapon", "bat", 0, 0, 1, "common")), "weapon")
	eq(Upgrades.gem_kind(Items.make("sub", "mitt_cannon", 0, 0, 1, "common")), "weapon")
	eq(Upgrades.gem_kind(Items.make("gloves", "gloves", 0, 0, 1, "common")), "armor")


func test_common_items_and_rings_upgrade_without_a_chosen_affix() -> void:
	var bat := Items.make("weapon", "bat", 0, 0, 1, "common")
	Upgrades.apply(bat)
	eq(Items.upgraded_value(bat), 11, "+15% on a common item")
	var ring := Items.make("ring", "quantum_band", 1, 0, 20, "magic")
	ring["affixes"] = [_affix("sniper", 1, 1.0)]
	Upgrades.apply(ring, 0)
	near(ring["affixes"][0]["value"], 1.0 + Items.affix_step(Db.affix("sniper"), 1), 0.001)
	eq(Items.upgraded_value(ring), 0, "rings never gain base armor")
