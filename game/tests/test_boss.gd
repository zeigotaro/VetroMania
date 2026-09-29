extends TestCase
## KRATE in the real arena: entrance, phases, the Autograph Seal finish and its failure modes.

const ALL := ["beam_bat", "mitt_cannon", "wall_kick", "spaceball"]


func _arena(abilities: Array = ALL, seal: bool = true) -> WorldRun:
	var run := await WorldRun.make(tree, abilities, "outer_arena", [4, 19], 7, true)
	if seal:
		run.state.grant_seal(1)
	await run.step(30)
	return run


func _hit(boss: BossKrate, amount: float) -> void:
	boss.receive_hit({"amount": amount, "crit": false, "weak": false, "resist": false}, {"kind": "melee", "heavy": false, "direction": 1})


func _skip_intro(boss: BossKrate) -> void:
	boss.intro_frames = 1


func test_entering_the_arena_starts_the_fight() -> void:
	var run := await _arena()
	check(run.world.boss != null, "KRATE is waiting")
	if run.world.boss == null:
		run.dispose()
		return
	eq(run.world.boss.max_hp, float(Damage.boss_hp(10)), "HP is 20x fodder at level 10")
	check(run.world.arena_door.open, "the door is still open behind Sleve")
	await run.walk_to(run.world.arena_door.global_position.x + 60.0)
	await run.step(4)
	check(not run.world.arena_door.open, "the door slams shut once Sleve is inside")
	run.dispose()


func test_intro_roar_is_harmless() -> void:
	var run := await _arena()
	var boss := run.world.boss
	var start_hp := run.state.hp
	check(boss.intro_frames > 0, "KRATE roars first")
	_hit(boss, 500.0)
	eq(boss.hp, boss.max_hp, "and cannot be hurt yet")
	await run.step(60)
	check(run.state.hp >= start_hp, "the roar itself does no damage")
	run.dispose()


func test_phase_two_starts_with_an_invulnerable_shift() -> void:
	var run := await _arena()
	var boss := run.world.boss
	_skip_intro(boss)
	await run.step(3)
	check(not boss.phase2, "phase one first")
	_hit(boss, boss.max_hp * 0.51)
	check(boss.phase2, "below 50% HP KRATE shifts")
	eq(boss.attack, "shift", "into the shift")
	var hp_during := boss.hp
	_hit(boss, 100.0)
	eq(boss.hp, hp_during, "and cannot be hurt during it")
	await run.step(BossKrate.SHIFT_FRAMES + 4)
	check(not boss.invulnerable and boss.attack != "shift", "then fights on")
	_hit(boss, 10.0)
	check(boss.hp < hp_during, "and can be hurt again")
	run.dispose()


func test_every_attack_telegraphs_and_the_arena_stays_survivable() -> void:
	var run := await _arena()
	var boss := run.world.boss
	_skip_intro(boss)
	run.state.hp = 100000.0
	run.state.data["player"]["hp"] = 100000
	var seen := {}
	var hazards := 0
	for _i in 2400:
		await run.step(1)
		if boss.attack != "":
			seen[boss.attack] = true
		hazards = maxi(hazards, run.count_nodes("Hazard"))
		if _i == 900:
			_hit(boss, boss.max_hp * 0.55)
	check(seen.has("slam") and seen.has("chomp"), "slam and chomp both happen (%s)" % str(seen.keys()))
	check(seen.has("cargo_drop"), "and cargo drop once he is in phase two")
	check(hazards > 0, "shockwaves and crates appear")
	check(is_instance_valid(boss), "the fight does not crash the boss")
	run.dispose()


func test_seal_finish_ends_the_fight_and_gives_the_jetpack() -> void:
	var run := await _arena()
	var boss := run.world.boss
	_skip_intro(boss)
	await run.step(3)
	var completed := [false]
	run.world.slice_completed.connect(func() -> void: completed[0] = true)
	_hit(boss, boss.max_hp * 0.6)
	await run.step(BossKrate.SHIFT_FRAMES + 4)
	_hit(boss, boss.max_hp)
	await run.step(90)
	check(run.state.boss_state("krate")["defeated"], "KRATE is signed off")
	check(run.world.boss == null, "the boss slot is empty")
	check(run.world.arena_door.open, "the arena door opens")
	var orb: Prop = null
	for prop in run.world.props + run.world.actors.get_children():
		if prop is Prop and prop.kind == "orb" and prop.data.get("ability", "") == "jetpack":
			orb = prop
	check(orb != null, "the jetpack orb appears")
	if orb != null:
		run.player.global_position = orb.global_position + Vector2(0, 6)
		await run.step(10)
		check(run.state.has_ability("jetpack"), "Sleve takes it")
		await run.step(World.END_DELAY_FRAMES + 10)
		check(completed[0], "and the slice ends")
	run.dispose()


func test_without_the_seal_krate_retreats_at_twenty_percent() -> void:
	var run := await _arena(ALL, false)
	var boss := run.world.boss
	_skip_intro(boss)
	await run.step(3)
	_hit(boss, boss.max_hp * 0.6)
	await run.step(BossKrate.SHIFT_FRAMES + 4)
	_hit(boss, boss.max_hp)
	await run.step(10)
	check(run.world.boss == null, "he leaves the arena")
	check(run.world.arena_door.open, "the doors open so Sleve can go and learn the seal")
	var state: Dictionary = run.state.boss_state("krate")
	check(not state["defeated"], "he is not defeated")
	near(float(state["hp_frac"]), 0.2, 0.001, "and waits at 20% HP")
	run.world.teleport_to_room("outer_shaft", [30, 19])
	await run.step(10)
	run.world.teleport_to_room("outer_arena", [4, 19])
	await run.step(10)
	check(run.world.boss != null, "he is back when Sleve returns")
	near(run.world.boss.hp / run.world.boss.max_hp, 0.2, 0.01, "still at 20% HP")
	run.dispose()


func test_a_failed_signing_heals_krate_a_little() -> void:
	var run := await _arena()
	run.world.auto_seal = false
	var boss := run.world.boss
	_skip_intro(boss)
	await run.step(3)
	_hit(boss, boss.max_hp * 0.6)
	await run.step(BossKrate.SHIFT_FRAMES + 4)
	_hit(boss, boss.max_hp)
	await run.step(6)
	check(is_instance_valid(boss) and not boss.dead, "the fight goes on")
	near(boss.hp / boss.max_hp, 0.2, 0.001, "at 20% HP")
	check(not boss.finishing, "and is no longer frozen")
	check(run.world.boss == boss, "still in the arena")
	run.dispose()
