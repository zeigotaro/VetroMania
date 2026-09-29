extends TestCase
## Kill Tallies: thresholds, milestones, perks and Knack slots (docs/design/bestiary.md#kill-tallies).


func before_each_state() -> Dictionary:
	Tallies.threshold_override = 0
	return Tallies.new_state()


func test_thresholds_by_tier() -> void:
	Tallies.threshold_override = 0
	eq(Tallies.threshold("space_bat"), 200, "fodder")
	eq(Tallies.threshold("space_bat", true), 100, "mirror variants need half")
	eq(Db.perks()["thresholds"]["elite"], 100)
	eq(Db.perks()["thresholds"]["rare"], 25)


func test_milestones_fire_in_order() -> void:
	var state := before_each_state()
	var log: Array = []
	for i in 200:
		for event in Tallies.add_kill(state, "space_bat"):
			log.append([i + 1, event])
	eq(log, [[1, "first_kill"], [50, "revealed"], [100, "rival"], [200, "complete"]], "first kill, 25%, 50%, 100%")
	check(Tallies.has_perk(state, "echolocation_ping"))
	eq(Tallies.kills(state, "space_bat"), 200)
	eq(Tallies.add_kill(state, "space_bat"), [] as Array[String], "the count stops at the threshold")
	eq(Tallies.kills(state, "space_bat"), 200)


func test_first_kill_is_reported_before_it_is_recorded() -> void:
	var state := before_each_state()
	check(Tallies.is_first_kill(state, "astro_zombie"))
	Tallies.add_kill(state, "astro_zombie")
	check(not Tallies.is_first_kill(state, "astro_zombie"))
	check(Tallies.is_first_kill(state, "hunch_bot"), "each enemy type has its own first kill")


func test_progress_flags() -> void:
	var state := before_each_state()
	state["kills"]["space_bat"] = 49
	var p := Tallies.progress(state, "space_bat")
	eq([p["pct"], p["revealed"], p["rival"], p["complete"]], [24, false, false, false])
	state["kills"]["space_bat"] = 50
	eq(Tallies.progress(state, "space_bat")["revealed"], true, "weaknesses revealed at 25%")
	check(not Tallies.rival_active(state, "space_bat"))
	state["kills"]["space_bat"] = 100
	check(Tallies.rival_active(state, "space_bat"), "Rival at 50%")


func test_trait_perks_apply_and_upgrade_to_ex() -> void:
	var state := before_each_state()
	eq(Tallies.trait_stats(state), {})
	state["completed"].append("braaains")
	eq(Tallies.trait_stats(state), {"INT": 2})
	state["mirror_completed"].append("braaains")
	eq(Tallies.trait_stats(state), {"INT": 5}, "the mirror tally upgrades Braaains to +5 INT")
	eq(Tallies.perk_level(state, "braaains"), 2)
	eq(Tallies.perk_level(state, "echolocation_ping"), 1)


func test_knack_slots_open_at_10_and_30_completed_tallies() -> void:
	var state := before_each_state()
	eq(Tallies.knack_slots(state), 1)
	for i in 9:
		state["completed"].append("fake_%d" % i)
	eq(Tallies.knack_slots(state), 1)
	state["completed"].append("fake_9")
	eq(Tallies.knack_slots(state), 2)
	for i in range(10, 29):
		state["completed"].append("fake_%d" % i)
	eq(Tallies.knack_slots(state), 2)
	state["completed"].append("fake_29")
	eq(Tallies.knack_slots(state), 3)


func test_equipping_knacks() -> void:
	var state := before_each_state()
	check(not Tallies.equip_knack(state, "echolocation_ping"), "needs the completed tally")
	state["completed"] = ["echolocation_ping", "satellite_uplink", "braaains"]
	check(Tallies.equip_knack(state, "echolocation_ping"))
	check(not Tallies.equip_knack(state, "satellite_uplink"), "one Knack slot at the start")
	check(not Tallies.equip_knack(state, "braaains"), "traits are always on and never equipped")
	Tallies.unequip_knack(state, "echolocation_ping")
	check(Tallies.equip_knack(state, "satellite_uplink"))
	eq(state["knacks"], ["satellite_uplink"])


func test_hud_label_matches_the_mockup_wording() -> void:
	var state := before_each_state()
	state["kills"]["space_bat"] = 187
	eq(Tallies.label(state, "space_bat"), "SPACE BAT TALLY 187/200 - 13 MORE: ECHOLOCATION PING")


func test_debug_threshold_override() -> void:
	Tallies.threshold_override = 5
	var state := Tallies.new_state()
	for _i in 5:
		Tallies.add_kill(state, "hunch_bot")
	check(Tallies.has_perk(state, "satellite_uplink"))
	Tallies.threshold_override = 0


func test_no_perk_grants_traversal() -> void:
	for id: String in Db.perks()["perks"]:
		var def: Dictionary = Db.perks()["perks"][id]
		check(def["type"] in ["trait", "knack"], "%s has a type" % id)
		var text := (String(def["text"]) + String(def.get("text_ex", ""))).to_lower()
		for banned in ["opens", "unlock", "double jump", "wall kick", "breaks"]:
			check(text.find(banned) == -1 or text.find("not break") != -1 or text.find("does not") != -1, "%s must not grant traversal (%s)" % [id, banned])
		var enemy: Dictionary = Db.enemy(def["enemy"])
		eq(enemy.get("perk", ""), id, "%s belongs to its enemy" % id)
