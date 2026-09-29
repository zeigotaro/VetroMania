extends TestCase
## The three fodder enemies and the elite affixes, running in the real world with real physics.
## crash_1 is the flattest room, so nothing but the enemy under test is in the way.

const FLOOR_Y := 19


func _place(run: WorldRun, room_id: String, col: int) -> Vector2:
	return run.world.level.entity_position(run.world.level.room(room_id), [col, FLOOR_Y])


func test_zombie_shambles_lunges_and_hurts() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [5, FLOOR_Y])
	await run.step(20)
	await run.clear_enemies()
	var start_hp := run.state.hp
	var zombie := run.spawn_enemy("astro_zombie", run.player.global_position + Vector2(120, 0))
	var closest := 9999.0
	var lunged := false
	for _i in 420:
		await run.step(1)
		if not is_instance_valid(zombie):
			break
		closest = minf(closest, absf(zombie.global_position.x - run.player.global_position.x))
		lunged = lunged or zombie.phase == "lunge"
	check(closest < 60.0, "the zombie closes the distance (closest %.0f)" % closest)
	check(lunged, "and lunges once in range")
	check(run.state.hp < start_hp, "the lunge hurts (hp %.0f of %.0f)" % [run.state.hp, start_hp])
	run.dispose()


func test_zombie_never_walks_off_a_ledge() -> void:
	var run := await WorldRun.make(tree, [], "outer_1", [18, FLOOR_Y])
	await run.step(20)
	await run.clear_enemies()
	var floor_y := run.player.global_position.y
	var zombie := run.spawn_enemy("astro_zombie", _place(run, "outer_1", 10), 5)
	var deepest := 0.0
	for _i in 600:
		await run.step(1)
		if is_instance_valid(zombie):
			deepest = maxf(deepest, zombie.global_position.y - floor_y)
	check(deepest < 4.0, "the zombie stops at the edge of the spike pit (dropped %.0f px)" % deepest)
	run.dispose()


func test_bat_dives_and_returns() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [5, FLOOR_Y])
	await run.step(20)
	await run.clear_enemies()
	var bat := run.spawn_enemy("space_bat", run.player.global_position + Vector2(40, -110))
	var dived := false
	var came_back := false
	for _i in 600:
		await run.step(1)
		dived = dived or bat.phase == "dive"
		came_back = came_back or (dived and bat.phase == "idle")
	check(dived, "the bat dives at Sleve")
	check(came_back, "and climbs back to its perch")
	run.dispose()


func test_hunch_bot_hops_and_shoots() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [5, FLOOR_Y])
	await run.step(20)
	await run.clear_enemies()
	var bot := run.spawn_enemy("hunch_bot", run.player.global_position + Vector2(140, 0))
	var start_x := bot.global_position.x
	var bolts := 0
	for _i in 420:
		await run.step(1)
		bolts = maxi(bolts, run.count_nodes("EnemyBolt"))
	check(absf(bot.global_position.x - start_x) > 6.0, "the Hunch-Bot hops around")
	check(bolts > 0, "and fires bolts from its dish")
	run.dispose()


func test_killing_pays_xp_and_counts_the_tally() -> void:
	var run := await WorldRun.make(tree, ["beam_bat"], "crash_1", [5, FLOOR_Y])
	await run.step(20)
	await run.clear_enemies()
	var xp_before := run.state.xp
	var zombie := run.spawn_enemy("astro_zombie", run.player.global_position + Vector2(30, 0))
	var died := [false]
	zombie.died.connect(func(_enemy: Enemy) -> void: died[0] = true)
	for _i in 12:
		if died[0]:
			break
		await run.swing()
	check(died[0], "a level 1 zombie dies to the starter bat")
	await run.step(30)
	check(run.state.xp > xp_before or run.state.level > 1, "and pays XP")
	eq(int(run.state.data["tallies"]["kills"].get("astro_zombie", 0)), 1, "and counts toward its Kill Tally")
	run.dispose()


func test_elite_affixes() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [5, FLOOR_Y])
	await run.step(10)
	await run.clear_enemies()
	var base := run.spawn_enemy("hunch_bot", _place(run, "crash_1", 30), 4)
	var fast := run.spawn_enemy("hunch_bot", _place(run, "crash_1", 32), 6, true, "fast")
	var shielded := run.spawn_enemy("hunch_bot", _place(run, "crash_1", 34), 6, true, "shielded")
	await run.step(2)
	near(fast.speed_mult, float(Db.elite()["fast_mult"]), 0.001, "fast elites move faster")
	check(shielded.shield > 0.0, "shielded elites carry a shield")
	check(fast.max_hp > base.max_hp * 2.0, "elites are tougher than fodder")
	run.dispose()
