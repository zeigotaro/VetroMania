extends TestCase
## Plays the real level with real physics: every jump, gap and climb the critical path asks for.
## Enemies are cleared so this is about the geometry, not the fights.

const ALL := ["beam_bat", "mitt_cannon", "wall_kick", "spaceball"]


func _run(abilities: Array, room_id: String, col: int, row: int) -> WorldRun:
	var run := await WorldRun.make(tree, abilities, room_id, [col, row], 7, true)
	await run.step(20)
	await run.clear_enemies()
	return run


func _reach(run: WorldRun, room_id: String, col: int, row: int, what: String, frames: int = 900) -> void:
	await run.clear_enemies()
	var ok := await run.go(run.feet(room_id, col, row), frames)
	check(ok, "%s (stopped at %s, wanted %s)" % [what, str(run.player.global_position.round()), str(run.feet(room_id, col, row))])


func test_shaft_is_a_wall_kick_climb() -> void:
	var run := await _run(["wall_kick"], "outer_shaft", 17, 42)
	var top := run.feet("outer_shaft", 22, 19).y
	var got_up := await run.climb(top, 1500)
	check(got_up, "Sleve wall-kicks from the corridor to the landing (y %.0f, needs %.0f)" % [run.player.global_position.y, top])
	run.dispose()


func test_shaft_is_a_wall_for_anyone_without_the_kick() -> void:
	var run := await _run([], "outer_shaft", 17, 42)
	var top := run.feet("outer_shaft", 22, 19).y
	var got_up := await run.climb(top, 900)
	check(not got_up, "without wall kick the shaft cannot be climbed (reached y %.0f)" % run.player.global_position.y)
	run.dispose()


func test_crash_site_to_the_hull() -> void:
	var run := await WorldRun.make(tree)
	await run.step(20)
	await run.clear_enemies()
	await _reach(run, "crash_1", 15, 19, "walk to the vending machine")
	await run.tap(["up"])
	await run.step(4)
	check(run.state.has_ability("beam_bat"), "the vending machine gives the beam bat")
	await _reach(run, "crash_1", 36, 19, "walk to the crate bulkhead")
	await run.swing()
	await run.step(6)
	await _reach(run, "crash_2", 3, 19, "the bulkhead is gone and Sleve walks into the wreckage field")
	await _reach(run, "crash_2", 28, 19, "cross the wreckage, over two blocks and past the mitt cannon")
	check(run.state.has_ability("mitt_cannon"), "the mitt cannon orb is on the way")
	await _reach(run, "crash_3", 37, 19, "cross the conduit yard")
	await _reach(run, "hull_1", 37, 19, "walk into the hull cathedral")
	eq(run.world.current_room["id"], "hull_1", "arrived in the hull")
	run.dispose()


func test_hull_to_the_outer_hull() -> void:
	var run := await _run(["beam_bat", "mitt_cannon"], "hull_1", 37, 19)
	await _reach(run, "hull_nave", 14, 19, "walk to the koozie statue")
	await run.tap(["up"])
	await run.step(4)
	check(run.state.has_ability("spaceball"), "the statue gives the spaceball")
	await _reach(run, "hull_nave", 75, 19, "cross the nave")
	await _reach(run, "hull_east", 5, 19, "enter the cloister")
	await _reach(run, "hull_east", 7, 16, "climb onto the first ledge")
	await _reach(run, "hull_east", 11, 13, "and the second")
	await _reach(run, "hull_east", 20, 13, "cross the roof of the hollow room")
	await _reach(run, "hull_east", 31, 19, "drop down to the signing table")
	await run.tap(["up"])
	await run.step(4)
	check(run.state.has_seal(1), "the signing table teaches the fastball seal")
	await _reach(run, "hull_east", 36, 19, "walk to the crate bulkhead")
	await run.swing()
	await run.step(6)
	await _reach(run, "outer_1", 4, 19, "the bulkhead is gone and Sleve steps onto the outer hull")
	run.dispose()


func test_outer_hull_to_the_boss_door() -> void:
	var run := await _run(["beam_bat", "mitt_cannon", "spaceball"], "outer_1", 4, 19)
	await _reach(run, "outer_1", 13, 19, "walk to the spike pit")
	await _reach(run, "outer_1", 18, 19, "jump the spike pit")
	await _reach(run, "outer_1", 24, 19, "walk under the ledge to the space monkeys")
	check(run.state.has_ability("wall_kick"), "the monkeys teach the wall kick")
	await _reach(run, "outer_1", 35, 19, "hop the cargo block")
	await _reach(run, "outer_shaft", 17, 42, "cross into the shaft")
	var top := run.feet("outer_shaft", 22, 19).y
	var got_up := await run.climb(top, 1500)
	check(got_up, "climb the shaft")
	await _reach(run, "outer_shaft", 36, 19, "walk to the boss door", 600)
	await _reach(run, "outer_arena", 6, 19, "step into the arena")
	check(run.world.boss != null, "KRATE is waiting")
	run.dispose()
