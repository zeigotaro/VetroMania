extends TestCase
## The real level, built by the real World: layout, gates, props and the rules that hang off them.


func test_real_level_is_valid() -> void:
	var level := Level.load_all()
	eq(level.validate(), [] as Array[String], "schema problems")
	eq(level.rooms.size(), 11, "rooms")
	eq(level.total_cells(), 13, "cells")
	var starts := 0
	var bosses := 0
	for id: String in level.order:
		for entity: Dictionary in level.rooms[id]["entities"]:
			starts += int(entity["type"] == "spawn" and entity["id"] == "start")
			bosses += int(entity["type"] == "boss")
	eq(starts, 1, "start spawns")
	eq(bosses, 1, "bosses")
	eq(level.room_at_cell(Vector2i(0, 1))["id"], "crash_1", "first cell")
	eq(level.room_at_cell(Vector2i(5, 1))["id"], "hull_nave", "nave covers two cells")
	eq(level.room_at_cell(Vector2i(8, 0))["id"], "outer_shaft", "shaft covers two cells")


func test_world_boots_at_the_crash() -> void:
	var run := await WorldRun.make(tree)
	eq(run.world.problems, [] as Array[String], "level problems")
	eq(run.world.current_room["id"], "crash_1", "start room")
	await run.step(30)
	check(run.player.is_on_floor(), "Sleve lands")
	near(run.player.global_position.x, 88.0, 1.0, "spawn x")
	var kinds := {}
	for gate in run.world.gates:
		kinds[gate.kind] = int(kinds.get(gate.kind, 0)) + 1
	eq(kinds, {"X": 2, "%": 1, "C": 1}, "gates")
	eq(run.world.targets.size(), 1, "mitt targets")
	run.dispose()


func test_crate_bulkhead_needs_the_beam_bat() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [34, 19], 7, true)
	await run.step(20)
	await run.clear_enemies()
	var crate: Gate = null
	for gate in run.world.gates:
		if gate.kind == "X" and gate.room_id == "crash_1":
			crate = gate
	check(crate != null, "crash_1 has a crate bulkhead")
	if crate == null:
		run.dispose()
		return
	await run.walk_to(crate.bounds.position.x - 12.0)
	var crate_key := crate.key
	for _i in 4:
		await run.swing()
	check(is_instance_valid(crate) and not crate.is_queued_for_deletion(), "fists and a plain bat do nothing")
	run.state.grant_ability("beam_bat")
	await run.swing()
	check(not is_instance_valid(crate) or crate.is_queued_for_deletion(), "the beam bat smashes it in one hit")
	check(run.state.is_opened(crate_key), "the bulkhead stays open")
	run.dispose()


func test_vending_machine_gives_the_bat() -> void:
	var run := await WorldRun.make(tree, [], "crash_1", [15, 19])
	await run.step(20)
	check(not run.state.has_ability("beam_bat"), "no bat yet")
	await run.tap(["up"])
	await run.step(4)
	check(run.state.has_ability("beam_bat"), "the machine dispenses the beam bat")
	check(not run.state.data["equipped"].get("weapon", {}).is_empty(), "and a bat to hold")
	await run.tap(["up"])
	await run.step(4)
	var bats: Array = run.state.data["inventory"].filter(func(item: Dictionary) -> bool: return item["slot"] == "weapon")
	eq(bats.size(), 1, "only one bat, no matter how often you press up")
	run.dispose()


func test_hollow_wall_breaks_on_the_third_hit() -> void:
	var run := await WorldRun.make(tree, ["beam_bat"], "hull_east", [12, 19])
	await run.step(20)
	await run.clear_enemies()
	var wall: Gate = null
	var chest: Prop = null
	for gate in run.world.gates:
		if gate.kind == "%":
			wall = gate
	for prop in run.world.props:
		if prop.kind == "chest" and prop.room_id == "hull_east":
			chest = prop
	check(wall != null and chest != null, "hull_east has a hollow wall and a chest")
	if wall == null or chest == null:
		run.dispose()
		return
	await run.step(2)
	check(not chest.visible, "the chest hides while the wall stands")
	await run.swing()
	check(is_instance_valid(wall) and wall.hits == 1, "first hit tonks")
	await run.swing()
	check(is_instance_valid(wall) and wall.hits == 2, "second hit tonks")
	await run.swing()
	await run.step(4)
	check(not is_instance_valid(wall) or wall.is_queued_for_deletion(), "third hit breaks it")
	await run.step(4)
	check(chest.visible, "the chest shows once the wall is gone")
	run.dispose()


func test_echolocation_ping_reveals_but_never_breaks() -> void:
	var run := await WorldRun.make(tree, ["beam_bat"], "hull_east", [12, 19])
	await run.step(20)
	var wall: Gate = null
	for gate in run.world.gates:
		if gate.kind == "%":
			wall = gate
	run.world.ping()
	await run.step(10)
	check(wall.reveal_frames > 0, "the ping makes the hollow wall glint")
	check(is_instance_valid(wall) and wall.hits == 0, "and never touches it")
	run.dispose()


func test_charged_mitt_shot_opens_the_conduit() -> void:
	var run := await WorldRun.make(tree, ["mitt_cannon"], "crash_3", [23, 16])
	await run.step(20)
	await run.clear_enemies()
	check(run.player.is_on_floor(), "Sleve stands on the yard platform")
	var target: MittTarget = run.world.targets[0]
	var shutter: Gate = null
	for gate in run.world.gates:
		if gate.kind == "C":
			shutter = gate
	await run.hold(["left"], 3)
	await run.hold(["sub"], 4)
	await run.tap([])
	await run.step(60)
	check(not target.lit, "an uncharged shot does nothing")
	await run.hold(["sub"], 60)
	await run.tap([])
	await run.step(90)
	check(target.lit, "a charged shot lights the bullseye")
	check(not is_instance_valid(shutter) or shutter.is_queued_for_deletion(), "and the shutter opens")
	run.dispose()
