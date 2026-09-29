extends SceneTree
## A windowed screenshot tour of the real game (needs a display and a GPU; CI does not run it).
##   python tools/godot.py shots [output_dir]
## Saves and settings go to a temp folder, so the tour never touches the player's own files.

var out_dir := ""
var main: Main


func _initialize() -> void:
	_run()


func frames(count: int) -> void:
	for _i in count:
		await process_frame


func shot(name: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", image.get_size())


func close_modals() -> void:
	while main.top() != null:
		main.top().close()
		await frames(2)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_environment("TEMP") + "/vm-shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveFiles.root = out_dir + "/saves"
	Settings.path = out_dir + "/settings.json"
	for slot in range(1, SaveFiles.SLOTS + 1):
		SaveFiles.delete(slot)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await frames(4)
	await shot("01_title")
	main.press("confirm")
	await shot("02_slots")
	main.press("confirm")
	await shot("03_difficulty")
	main.press("confirm")
	await frames(90)
	await shot("04_crash_start")
	var gs := main.gs
	for ability in ["beam_bat", "mitt_cannon", "spaceball", "wall_kick"]:
		gs.grant_ability(ability)
	gs.grant_seal(1)
	gs.add_xp(Stats.total_xp_to_reach(12))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for rarity in ["rare", "magic", "rare", "rare", "legendary", "magic", "common", "rare"]:
		var item := Loot.roll_gear(rng, 12, rarity, gs.level)
		if not item.is_empty():
			gs.add_item(item)
	gs.add_bucks(4200)
	gs.add_gems("armor", 9)
	gs.add_gems("weapon", 7)
	gs.add_consumable("space_burrito", 2)
	gs.full_restore()
	await close_modals()
	await frames(200)
	for stop in [
		["crash_1", [15, 19], "05_vending"], ["crash_2", [24, 19], "06_wreckage"], ["crash_3", [23, 16], "07_conduit_yard"],
		["hull_1", [14, 19], "08_narthex"], ["hull_nave", [16, 19], "09_nave"], ["hull_gallery", [20, 19], "10_gallery"],
		["hull_east", [12, 19], "11_cloister"], ["outer_1", [10, 19], "12_outer_deck"], ["outer_shaft", [17, 42], "13_shaft_bottom"],
		["outer_shaft", [26, 19], "14_boss_door"],
	]:
		main.world.teleport_to_room(stop[0], stop[1])
		await frames(50)
		await close_modals()
		await shot(stop[2])
	main.world.say("ONSON SWEEMEY", ["ROOKIE! I'M ONSON SWEEMEY. COACH. HOLOGRAM. LONG STORY.", "PRESS ATTACK TO SWING THE BAT."])
	await frames(90)
	await shot("15_dialogue")
	await close_modals()
	for tab in 4:
		main.open_pause(tab) if tab == 0 else main.press("tab_next")
		await frames(4)
		await shot("16_pause_%d" % tab)
	main.press("cancel")
	await frames(3)
	main.push(PodMenu.new(gs))
	await shot("17_pod")
	main.press("confirm")
	await shot("18_pod_upgrade")
	main.press("cancel")
	main.press("cancel")
	await frames(3)
	main.push(MontageMenu.new(gs))
	await shot("19_montage")
	main.press("cancel")
	await frames(3)
	main.world.start_seal(1, false, func(_ok: bool) -> void: pass)
	await frames(20)
	await shot("20_seal")
	main.top().close(false)
	await frames(3)
	main.world.teleport_to_room("outer_arena", [4, 19])
	await frames(200)
	for _i in 4:
		await frames(60)
	var boss := main.world.boss
	if boss != null:
		boss.hp = boss.max_hp * 0.4
		boss.phase2 = true
	await frames(150)
	await shot("21_krate")
	await frames(70)
	await shot("22_krate_attack")
	main._on_death()
	await frames(50)
	await shot("23_death")
	main.top().close("title")
	await frames(4)
	quit(0)
