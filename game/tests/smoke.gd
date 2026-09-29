extends SceneTree
## End-to-end smoke test: boots the real game headless, plays the whole slice with a bot and the real menus
## (new game, vending machine, signing table, wall-kick shaft, KRATE and his Autograph Seal) and reaches the
## end card. Exit code 1 with the reason if anything gets stuck.
##   python tools/godot.py smoke

var main: Main
var run: WorldRun


func _initialize() -> void:
	_play()


func fail(reason: String) -> void:
	printerr("SMOKE FAILED: ", reason)
	quit(1)


func expect(condition: bool, reason: String) -> bool:
	if not condition:
		fail(reason)
	return condition


func frames(count: int) -> void:
	for _i in count:
		await process_frame


## Closes dialogue boxes and pod menus (confirm, then cancel) until nothing but a seal overlay or a card is open.
func dismiss_boxes() -> void:
	for _i in 12:
		if main.top() is DialogueBox:
			main.press("confirm")
		elif main.top() is PodMenu:
			main.press("cancel")
		else:
			break
		await process_frame


func go(room_id: String, col: int, row: int, what: String, limit: int = 900) -> bool:
	await run.clear_enemies()
	var goal := run.feet(room_id, col, row)
	var used := 0
	while used < limit:
		if await run.go(goal, mini(150, limit - used)):
			return true
		used += 150
		if main.top() != null:
			await dismiss_boxes()
	return expect(false, "%s (stopped at %s)" % [what, str(run.player.global_position.round())])


func interact() -> void:
	await run.tap(["up"])
	await process_frame
	await dismiss_boxes()
	await frames(4)


func sign_seal(overlay: SealOverlay) -> void:
	for step in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
		for _i in 3:
			overlay.tick(step, false)
	overlay.tick(Vector2i(1, 0), true)
	for _i in SealOverlay.FLOURISH + 2:
		overlay.tick(Vector2i.ZERO, false)


func _play() -> void:
	var seed_value := 4242
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	var temp := "user://smoke"
	if OS.get_cmdline_user_args().has("--isolate"):
		temp += "_%d" % seed_value
	SaveFiles.root = temp + "/saves"
	Settings.path = temp + "/settings.json"
	Settings.reset()
	for slot in range(1, SaveFiles.SLOTS + 1):
		SaveFiles.delete(slot)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await frames(3)
	if not expect(main.top() is TitleScreen, "the game opens on the title screen"):
		return
	for _i in 3:
		main.press("confirm")
	await frames(4)
	if not expect(main.world != null and main.modals.is_empty(), "a new game starts"):
		return
	run = WorldRun.adopt(self, main.world, main.gs)
	seed(seed_value)
	main.gs.rng.seed = seed_value
	await run.step(20)

	if not await go("crash_1", 15, 19, "walk to the vending machine"):
		return
	await interact()
	if not expect(main.gs.has_ability("beam_bat"), "the vending machine gives the beam bat"):
		return
	if not await go("crash_1", 36, 19, "walk to the crate bulkhead"):
		return
	await run.swing()
	if not await go("crash_2", 3, 19, "smash the crates and step through"):
		return

	var zombie := run.spawn_enemy("astro_zombie", run.player.global_position + Vector2(30, 0))
	var xp_before := main.gs.xp
	for _i in 14:
		if not is_instance_valid(zombie) or zombie.dead:
			break
		await run.swing()
	await run.step(30)
	if not expect(main.gs.xp > xp_before, "killing a zombie pays XP"):
		return

	if not await go("crash_2", 28, 19, "cross the wreckage field"):
		return
	if not expect(main.gs.has_ability("mitt_cannon"), "the mitt cannon orb is picked up"):
		return
	if not await go("crash_3", 37, 19, "cross the conduit yard"):
		return
	if not await go("hull_1", 12, 19, "reach the save pod"):
		return
	await run.tap(["up"])
	await frames(3)
	if not expect(main.top() is PodMenu, "the save pod opens its menu"):
		return
	await dismiss_boxes()
	await frames(3)
	if not await go("hull_1", 17, 19, "reach Glenallen"):
		return
	await interact()
	if not await go("hull_nave", 14, 19, "walk to the koozie statue"):
		return
	await interact()
	if not expect(main.gs.has_ability("spaceball"), "the statue gives the spaceball"):
		return
	if not await go("hull_nave", 75, 19, "cross the nave"):
		return
	if not await go("hull_east", 7, 16, "climb the first ledge"):
		return
	if not await go("hull_east", 11, 13, "climb the second"):
		return
	if not await go("hull_east", 20, 13, "cross the hollow room's roof"):
		return
	if not await go("hull_east", 31, 19, "reach the signing table"):
		return
	await run.tap(["up"])
	await process_frame
	await dismiss_boxes()
	await frames(3)
	if not expect(main.top() is SealOverlay, "the signing table opens the seal practice"):
		return
	sign_seal(main.top() as SealOverlay)
	await frames(4)
	if not expect(main.gs.has_seal(1), "practising the motion earns the fastball seal"):
		return
	if not await go("hull_east", 36, 19, "walk to the bulkhead"):
		return
	await run.swing()
	if not await go("outer_1", 13, 19, "step onto the outer hull"):
		return
	if not await go("outer_1", 18, 19, "jump the spike pit"):
		return
	if not await go("outer_1", 24, 19, "meet the space monkeys"):
		return
	if not expect(main.gs.has_ability("wall_kick"), "the wall kick orb is picked up"):
		return
	if not await go("outer_shaft", 17, 42, "enter the shaft", 1200):
		return
	await run.clear_enemies()
	var climbed := await run.climb(run.feet("outer_shaft", 22, 19).y, 1800, 1)
	if not expect(climbed, "wall-kick up the shaft and onto the landing"):
		return
	if not await go("outer_shaft", 36, 19, "walk to the boss door", 900):
		return
	if not await go("outer_arena", 8, 19, "enter the arena", 600):
		return
	var boss := main.world.boss
	if not expect(boss != null, "KRATE is in the arena"):
		return
	boss.intro_frames = 1
	await run.step(3)
	boss.receive_hit({"amount": boss.max_hp * 0.6, "crit": false, "weak": false, "resist": false}, {"kind": "melee", "direction": 1})
	await run.step(BossKrate.SHIFT_FRAMES + 4)
	boss.receive_hit({"amount": boss.max_hp, "crit": false, "weak": false, "resist": false}, {"kind": "melee", "direction": 1})
	await frames(4)
	if not expect(main.top() is SealOverlay, "the finishing blow asks for the autograph seal"):
		return
	sign_seal(main.top() as SealOverlay)
	await run.step(60)
	if not expect(main.gs.boss_state("krate")["defeated"], "KRATE is signed off"):
		return
	var orb: Prop = null
	for node in main.world.actors.get_children():
		if node is Prop and node.kind == "orb" and node.data.get("ability", "") == "jetpack":
			orb = node
	if not expect(orb != null, "the jetpack orb appears"):
		return
	run.player.global_position = orb.global_position + Vector2(0, 6)
	await run.step(20)
	if not expect(main.gs.has_ability("jetpack"), "Sleve takes the jetpack"):
		return
	await run.step(World.END_DELAY_FRAMES + 20)
	if not expect(main.top() is MessageScreen, "the end card appears"):
		return
	print("SMOKE OK (seed %d): level %d, %d kills, %d%% map, %d bucks" % [seed_value, main.gs.level, int(main.gs.data["tallies"]["kills"].get("astro_zombie", 0)), roundi(MapCells.percent(main.gs.visited_count(), main.world.level.total_cells())), main.gs.bucks])
	quit(0)
