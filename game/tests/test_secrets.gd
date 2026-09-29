extends TestCase
## The optional rooms: each secret is reachable with the right ability, and only then.

const ALL := ["beam_bat", "mitt_cannon", "wall_kick", "spaceball"]


func _run(abilities: Array, room_id: String, col: int, row: int) -> WorldRun:
	var run := await WorldRun.make(tree, abilities, room_id, [col, row], 7, true)
	await run.step(20)
	await run.clear_enemies()
	return run


func _try(run: WorldRun, room_id: String, col: int, row: int, frames: int = 600) -> bool:
	await run.clear_enemies()
	return await run.go(run.feet(room_id, col, row), frames)


func test_the_staircase_climbs_to_both_upper_rooms() -> void:
	var run := await _run(ALL, "hull_nave", 33, 19)
	for spot: Array in [[37, 16], [41, 13], [37, 10], [41, 7], [37, 4], [41, 1]]:
		check(await _try(run, "hull_nave", spot[0], spot[1]), "climb the nave staircase to %s" % str(spot))
	check(await _try(run, "hull_ledge", 1, 21), "reach the top platform")
	check(await _try(run, "hull_ledge", 12, 19), "step onto the ledge floor")
	eq(run.world.current_room["id"], "hull_ledge", "in the ledge room")
	check(await _try(run, "hull_gallery", 30, 19), "and walk on into the gallery")
	eq(run.world.current_room["id"], "hull_gallery", "in the gallery")
	run.dispose()


func test_the_vent_needs_the_spaceball() -> void:
	var run := await _run([], "hull_gallery", 20, 19)
	check(not await _try(run, "hull_gallery", 5, 19, 240), "a grown Sleve cannot squeeze into the vent")
	run.dispose()
	run = await _run(["spaceball"], "hull_gallery", 20, 19)
	await run.tap(["down"])
	await run.step(3)
	await run.tap(["down"])
	await run.step(8)
	eq(run.player.mode, Player.Mode.BALL, "double-tap down curls Sleve into a ball")
	await run.hold(["left"], 170)
	check(run.player.global_position.x < run.feet("hull_gallery", 10, 19).x, "the ball rolls through the vent")
	await run.tap(["up"])
	await run.step(6)
	eq(run.player.mode, Player.Mode.NORMAL, "and stands up in the closet")
	await run.go(run.feet("hull_gallery", 5, 19), 300)
	var chest: Prop = null
	for prop in run.world.props:
		if prop.kind == "chest" and prop.room_id == "hull_gallery":
			chest = prop
	await run.tap(["up"])
	await run.step(4)
	check(chest != null and chest.open, "the chest in the closet opens")
	run.dispose()


func test_the_floating_chest_needs_the_jetpack() -> void:
	var run := await _run(ALL, "hull_ledge", 20, 19)
	check(not await _try(run, "hull_ledge", 26, 14, 480), "wall kick and spaceball are not enough")
	run.dispose()
	run = await _run(ALL + ["jetpack"], "hull_ledge", 20, 19)
	check(await _try(run, "hull_ledge", 26, 14, 480), "with the jetpack the chest is in reach")
	run.dispose()


func test_the_conduit_closet_opens_only_after_the_bullseye() -> void:
	var run := await _run(ALL, "crash_3", 18, 19)
	check(await _try(run, "crash_3", 23, 16), "hop onto the yard platform")
	check(await _try(run, "crash_3", 28, 13), "and up to the closet ledge")
	check(not await _try(run, "crash_3", 34, 13, 240), "the shutter keeps Sleve out")
	run.world.open_shutters("crash_3")
	await run.step(30)
	check(await _try(run, "crash_3", 34, 13), "once it opens Sleve walks in to the chest")
	run.dispose()


func test_the_hollow_room_is_walkable_once_the_wall_is_gone() -> void:
	var run := await _run(ALL, "hull_east", 12, 19)
	check(not await _try(run, "hull_east", 19, 19, 240), "the hollow wall keeps Sleve out")
	for _i in 3:
		await run.swing()
	await run.step(8)
	check(await _try(run, "hull_east", 19, 19), "then the chamber opens up to the chest")
	run.dispose()
