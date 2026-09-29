extends TestCase
## Stats and Damage against the worked examples in the design docs.


func test_xp_curve_matches_doc_table() -> void:
	var expected := {1: 95, 5: 765, 10: 3245, 12: 4809, 13: 5721, 20: 14640, 24: 21827, 25: 23871, 30: 35613,
		32: 41035, 36: 53151, 37: 56448, 40: 66996, 45: 86791, 49: 104658}
	for level: int in expected:
		eq(Stats.xp_to_next(level), expected[level], "xp_to_next(%d)" % level)
	eq(Stats.xp_to_next(50), 0, "max level needs no xp")
	eq(Stats.total_xp_to_reach(50), 1657786, "total xp to Lv 50")
	eq(Stats.total_xp_to_reach(24), 154152, "total xp to Lv 24")


func test_enemy_xp_and_level_factor() -> void:
	eq(Stats.enemy_xp(1), 7)
	eq(Stats.enemy_xp(24), 162)
	eq(Stats.enemy_xp(50), 529)
	near(Stats.xp_level_factor(30, 30), 1.0, 0.0001)
	near(Stats.xp_level_factor(5, 30), 0.1, 0.0001, "farming the crash site at Lv 30")
	near(Stats.xp_level_factor(40, 30), 1.5, 0.0001)
	near(Stats.xp_level_factor(32, 30), 1.2, 0.0001)


func test_stat_growth_table() -> void:
	var rows := {
		1: [8, 7, 6, 7, 5, 113, 33],
		10: [16, 14, 10, 13, 8, 210, 50],
		20: [25, 22, 15, 20, 11, 320, 70],
		30: [34, 30, 20, 27, 15, 430, 90],
		40: [43, 38, 25, 34, 18, 540, 110],
		50: [52, 46, 30, 41, 22, 650, 130],
	}
	for level: int in rows:
		var row: Array = rows[level]
		var stats := Stats.final_stats(level, {}, {})
		for i in Stats.NAMES.size():
			eq(stats[Stats.NAMES[i]], row[i], "Lv %d %s" % [level, Stats.NAMES[i]])
		eq(Stats.max_hp(stats["CON"], level), row[5], "Lv %d HP" % level)
		eq(Stats.max_ep(stats["INT"], level), row[6], "Lv %d EP" % level)


func test_montage_points() -> void:
	eq(Stats.montage_points(4), 0)
	eq(Stats.montage_points(5), 2)
	eq(Stats.montage_points(24), 8)
	eq(Stats.montage_points(50), 20, "20 points in total by Lv 50")


func test_upgrade_cap_bands() -> void:
	var expected := {1: 1, 12: 1, 13: 2, 24: 2, 25: 3, 36: 3, 37: 4, 49: 4, 50: 5}
	for level: int in expected:
		eq(Stats.upgrade_cap(level), expected[level], "cap at Lv %d" % level)


func test_equipment_mockup_numbers() -> void:
	## docs: Lv 24, Montage STR+3 CON+2 INT+1 LCK+2, boots +6 DEX, chest +30 HP, helm +16 EP,
	## legendary bat 50 dmg, 255 total armor, boots +8% Loot Luck.
	var level := 24
	var stats := Stats.final_stats(level, {"STR": 3, "CON": 2, "INT": 1, "LCK": 2}, {"DEX": 6})
	eq(stats["STR"], 31)
	eq(stats["CON"], 27)
	eq(stats["INT"], 18)
	eq(stats["DEX"], 29)
	eq(stats["LCK"], 15)
	eq(Stats.max_hp(stats["CON"], level, 30), 412, "HP")
	eq(Stats.max_ep(stats["INT"], level, 16), 96, "EP")
	eq(Damage.melee_atk(50, stats["STR"]), 88, "ATK")
	eq(Damage.defense(stats["CON"], 255), 64, "DEF")
	eq(roundi(Stats.crit_chance(stats["DEX"])), 7, "crit rounds to 7%")
	near(Stats.loot_luck(stats["LCK"], 8.0), 18.0, 0.0001, "Loot Luck")


func test_worked_damage_example() -> void:
	eq(Damage.hit(88.0, 1.0, Damage.enemy_def(24)), 62, "player hits a Lv 24 enemy")
	eq(Damage.enemy_hp("fodder", 24), 211, "Lv 24 fodder HP")
	eq(Damage.hit(Damage.enemy_atk(24), 1.0, 64.0), 40, "enemy hits Sleve")
	eq(Damage.hit(1.0, 1.0, 500.0), 1, "damage is at least 1")


func test_boss_and_elite_hp() -> void:
	eq(Damage.boss_hp(32), 5340, "HotCoffee")
	eq(Damage.boss_hp(50, true), 11790, "COLD BREW")
	eq(Damage.boss_hp(10), 2260, "KRATE")
	eq(Damage.enemy_hp("fodder", 10, true), Damage.enemy_hp("fodder", 10) * 3, "elites have 3x HP")


func test_sub_weapon_and_elements() -> void:
	eq(Damage.sub_atk(20, 29, 18), 20 + floori(0.75 * 29 + 0.5 * 18))
	near(Damage.element_mult("weak"), 1.5, 0.0001)
	near(Damage.element_mult("resist"), 0.5, 0.0001)
	near(Damage.element_mult("immune"), 0.0, 0.0001)
	near(Damage.element_mult("none"), 1.0, 0.0001)
