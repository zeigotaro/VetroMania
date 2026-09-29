extends TestCase
## Menus, boxes and the Main flow. Modals are added to the tree so their _draw() runs too.

var _root: String = "user://test_ui"


func _isolate() -> void:
	SaveFiles.root = _root + "/saves"
	Settings.path = _root + "/settings.json"
	Settings.reset()
	for slot in range(1, SaveFiles.SLOTS + 1):
		SaveFiles.delete(slot)
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(Settings.path)
	LiveInput.register_defaults()


func _open(modal: Modal) -> Array:
	var result := [null, false]
	modal.closed.connect(func(value: Variant) -> void:
		result[0] = value
		result[1] = true)
	tree.root.add_child(modal)
	await tree.process_frame
	await tree.process_frame
	return result


func _state(level_xp: int = 0) -> GameState:
	var state := GameState.begin(1, "normal", 7)
	GameState.current = state
	if level_xp > 0:
		state.add_xp(level_xp)
	return state


func test_settings_round_trip() -> void:
	_isolate()
	Settings.music = 0.3
	Settings.speed = 0.8
	Settings.seal_assist = true
	Settings.damage_numbers = false
	eq(Settings.save_file(), OK, "writes")
	Settings.reset()
	eq(Settings.speed, 1.0, "reset restores speed")
	Settings.load_file()
	near(Settings.music, 0.3, 0.001, "music survives")
	eq(Settings.speed, 0.8, "speed survives")
	check(Settings.seal_assist and not Settings.damage_numbers, "toggles survive")
	Settings.from_dict({"speed": 0.83, "music": 7.0})
	eq(Settings.speed, 0.8, "speed snaps to a supported step")
	near(Settings.music, 1.0, 0.001, "volumes are clamped")
	Settings.reset()


func test_text_helpers() -> void:
	eq(UIKit.wrap("ONE TWO THREE FOUR", 9), ["ONE TWO", "THREE", "FOUR"] as Array[String], "wraps on words")
	eq(UIKit.wrap("", 10), [] as Array[String], "nothing to wrap")
	eq(UIKit.format_time(3725.0), "1:02:05", "hours, minutes, seconds")
	var item := Items.make("helmet", "helmet", 0, 0, 1, "rare")
	check(UIKit.item_title(item).begins_with("* "), "rarity is never colour alone: rares get a mark")
	check(not UIKit.item_title(Items.make("helmet", "helmet", 0, 0, 1, "common")).begins_with(" "), "commons stay plain")


func test_dialogue_types_out_and_advances() -> void:
	_isolate()
	var box := DialogueBox.new("KEVIN", ["FIRST LINE.", "SECOND LINE."])
	var result := await _open(box)
	check(box.shown < box.total_chars(), "text is typed out")
	box.handle("confirm")
	eq(int(box.shown), box.total_chars(), "confirm finishes the line")
	box.handle("confirm")
	eq(box.index, 1, "then advances")
	box.handle("confirm")
	box.handle("confirm")
	check(result[1], "the last confirm closes it")


func test_pause_menu_equips_removes_and_uses_items() -> void:
	_isolate()
	var state := _state()
	state.add_item(Items.make("helmet", "helmet", 0, 0, 1, "common"))
	var spare := Items.make("helmet", "helmet", Items.base_tier(1), 0, 1, "magic")
	state.add_item(spare)
	state.add_item(Items.make("helmet", "helmet", Items.base_tier(30), 0, 30, "rare"))
	state.add_consumable("space_burrito")
	var menu := PauseMenu.new(state, null, 0)
	var result := await _open(menu)
	var bag_index := -1
	var too_high := -1
	var burrito := -1
	for i in menu.entries.size():
		var entry: Dictionary = menu.entries[i]
		if entry["kind"] == "bag" and int(entry["item"]["uid"]) == int(spare["uid"]):
			bag_index = i
		elif entry["kind"] == "bag" and int(entry["item"]["ilvl"]) == 30:
			too_high = i
		elif entry["kind"] == "consumable":
			burrito = i
	menu.index = bag_index
	menu.handle("confirm")
	eq(state.equipped_slot_of(spare), "helmet", "a bag item is worn on confirm")
	menu.index = too_high if too_high >= 0 else 0
	for i in menu.entries.size():
		if menu.entries[i]["kind"] == "bag" and int(menu.entries[i]["item"]["ilvl"]) == 30:
			menu.index = i
	menu.handle("confirm")
	check(menu.message.begins_with("Requires"), "an item above Sleve's level is refused (%s)" % menu.message)
	menu.index = 0
	menu.handle("confirm")
	check(not state.data["equipped"].has("helmet"), "confirming a worn slot removes it")
	state.hp = 10.0
	for i in menu.entries.size():
		if menu.entries[i]["kind"] == "consumable":
			burrito = i
	menu.index = burrito
	menu.handle("confirm")
	check(state.hp > 10.0, "a space burrito heals")
	eq(state.consumables("space_burrito"), 0, "and is used up")
	menu.handle("tab_next")
	eq(menu.tab, 1, "tabs switch")
	menu.handle("tab_prev")
	menu.handle("tab_prev")
	eq(menu.tab, 3, "and wrap around")
	menu.handle("cancel")
	check(result[1], "cancel closes the menu")


func test_pause_menu_system_tab_changes_options() -> void:
	_isolate()
	var state := _state()
	var menu := PauseMenu.new(state, null, 3)
	var result := await _open(menu)
	eq(String(menu.entries[0]["row"]), "music", "music is the first option")
	Settings.music = 0.5
	menu.handle("right")
	near(Settings.music, 0.6, 0.001, "right raises the volume")
	menu.index = _row("speed")
	menu.handle("left")
	eq(Settings.speed, 0.9, "speed steps down")
	menu.index = _row("assist")
	menu.handle("confirm")
	check(Settings.seal_assist, "seal assist toggles")
	check(FileAccess.file_exists(Settings.path), "options are saved as they change")
	menu.index = _row("quit")
	menu.handle("confirm")
	eq(result[0], "title", "save and quit asks for the title screen")
	check(SaveFiles.exists(1), "and saved the game")
	Settings.reset()
	Engine.time_scale = 1.0


func _row(row: String) -> int:
	return PauseMenu.SYSTEM_ROWS.find(row)


func test_tallies_tab_equips_a_finished_knack() -> void:
	_isolate()
	var state := _state()
	var tallies: Dictionary = state.data["tallies"]
	tallies["seen"].append("space_bat")
	tallies["kills"]["space_bat"] = 200
	tallies["completed"].append("echolocation_ping")
	var menu := PauseMenu.new(state, null, 1)
	await _open(menu)
	menu.index = 0
	menu.handle("confirm")
	eq(tallies["knacks"], ["echolocation_ping"], "confirm puts the knack on the button")
	menu.handle("confirm")
	eq(tallies["knacks"], [], "and confirm again takes it off")
	menu.index = 1
	menu.handle("confirm")
	eq(tallies["knacks"], [], "a tally that is not finished gives nothing")
	menu.close()


func test_pod_upgrades_and_salvages_gear() -> void:
	_isolate()
	var state := _state()
	var bat := Items.make("weapon", "bat", 0, 0, 5, "common")
	state.add_item(bat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rare := Loot.roll_gear(rng, 5, "rare", 5, {}, "armor")
	state.add_item(rare)
	state.add_gems("weapon", 4)
	state.add_bucks(2000)
	var menu := PodMenu.new(state)
	var result := await _open(menu)
	menu.handle("confirm")
	eq(menu.mode, PodMenu.Mode.UPGRADE, "upgrade gear opens the bench")
	var bat_at := -1
	for i in menu.items.size():
		if int(menu.items[i]["uid"]) == int(bat["uid"]):
			bat_at = i
	menu.index = bat_at
	var gems_before := state.gems("weapon")
	menu.handle("confirm")
	eq(int(bat["upgrades"]), 1, "an upgrade is applied")
	check(state.gems("weapon") < gems_before, "and costs gems")
	menu.handle("confirm")
	check(menu.message != "", "the cap for Sleve's level stops a second upgrade (%s)" % menu.message)
	menu.handle("cancel")
	eq(menu.mode, PodMenu.Mode.MAIN, "cancel steps back")
	menu.handle("down")
	menu.handle("confirm")
	eq(menu.mode, PodMenu.Mode.SALVAGE, "salvage opens")
	var count_before: int = state.data["inventory"].size()
	menu.handle("confirm")
	eq(state.data["inventory"].size(), count_before, "the first confirm only arms it")
	menu.handle("confirm")
	eq(state.data["inventory"].size(), count_before - 1, "the second one salvages")
	menu.handle("cancel")
	menu.handle("down")
	menu.handle("down")
	menu.handle("confirm")
	eq(menu.mode, PodMenu.Mode.KNACKS, "the knack loadout opens")
	menu.handle("cancel")
	for _i in 3:
		menu.handle("down")
	menu.handle("confirm")
	check(result[1], "close leaves the pod")


func test_montage_spends_points_and_marks_itself_seen() -> void:
	_isolate()
	var state := _state(Stats.total_xp_to_reach(5))
	eq(state.montage_points_free(), 2, "level 5 earns two points")
	check(state.montage_pending(), "a montage is waiting")
	var menu := MontageMenu.new(state)
	var result := await _open(menu)
	menu.handle("confirm")
	eq(int(state.data["player"]["allocated"]["STR"]), 1, "confirm adds a point to the selected stat")
	menu.handle("down")
	menu.handle("confirm")
	check(result[1], "spending the last point ends the montage")
	check(not state.montage_pending(), "and it is not shown again")
	eq(result[0], 2, "it reports how many points were spent")


func test_seal_overlay_success_failure_practice_and_assist() -> void:
	_isolate()
	var win := SealOverlay.new(1, false, 1, {"seal_window": 3.0})
	var win_result := await _open(win)
	win.tick(Vector2i(0, 1), false)
	win.tick(Vector2i(1, 1), false)
	win.tick(Vector2i(1, 0), false)
	win.tick(Vector2i(1, 0), true)
	eq(win.state, "success", "down, down-forward, forward, attack signs it")
	for _i in SealOverlay.FLOURISH + 1:
		win.tick(Vector2i.ZERO, false)
	eq(win_result[0], true, "and closes with true")

	var lose := SealOverlay.new(1, false, 1, {"seal_window": 3.0})
	var lose_result := await _open(lose)
	for _i in 200:
		lose.tick(Vector2i.ZERO, false)
	eq(lose.state, "fail", "three idle seconds smudge it")
	for _i in SealOverlay.FLOURISH + 1:
		lose.tick(Vector2i.ZERO, false)
	eq(lose_result[0], false, "and closes with false")

	var wrong := SealOverlay.new(1, false, 1, {"seal_window": 3.0})
	await _open(wrong)
	wrong.tick(Vector2i(1, 0), false)
	wrong.tick(Vector2i(0, 1), true)
	eq(wrong.state, "input", "the wrong motion does nothing")
	wrong.close(false)

	var practice := SealOverlay.new(1, true, 1, {"seal_window": 3.0})
	var practice_result := await _open(practice)
	for _i in 2000:
		practice.tick(Vector2i.ZERO, false)
	eq(practice.state, "input", "practice never times out")
	practice.handle("cancel")
	eq(practice_result[0], false, "cancel gives up")

	Settings.seal_assist = true
	var assist := SealOverlay.new(1, false, 1, {"seal_window": 3.0})
	await _open(assist)
	assist.tick(Vector2i.ZERO, true)
	eq(assist.state, "success", "seal assist needs only the attack button")
	assist.close(true)
	Settings.reset()

	var babby := SealOverlay.new(1, false, 1, {"seal_window": 6.0})
	eq(babby.window, 360, "Babby's First Planet doubles the window")
	babby.free()


func test_title_screen_paths() -> void:
	_isolate()
	var title := TitleScreen.new()
	var result := await _open(title)
	eq(title.index, 1, "with no saves the cursor starts on NEW GAME")
	title.handle("up")
	title.handle("confirm")
	eq(title.page, TitleScreen.Page.MAIN, "CONTINUE does nothing without a save")
	title.handle("down")
	title.handle("confirm")
	eq(title.page, TitleScreen.Page.SLOTS, "NEW GAME asks for a slot")
	title.handle("confirm")
	eq(title.page, TitleScreen.Page.DIFFICULTY, "an empty slot goes straight to difficulty")
	eq(title.modes[title.index], "normal", "normal is the default")
	title.index = title.modes.find("git_gud")
	title.handle("confirm")
	check(not result[1], "locked modes cannot be picked")
	title.index = title.modes.find("babby")
	title.handle("confirm")
	eq(result[0], {"action": "new", "slot": 1, "difficulty": "babby"}, "the result names the slot and the difficulty")

	GameState.begin(1, "normal", 3).save()
	var again := TitleScreen.new()
	var again_result := await _open(again)
	eq(again.index, 0, "with a save the cursor starts on CONTINUE")
	again.handle("confirm")
	eq(again.page, TitleScreen.Page.SLOTS, "continue lists the slots")
	again.handle("confirm")
	eq(again_result[0], {"action": "continue", "slot": 1, "difficulty": ""}, "and loads the highlighted one")

	var over := TitleScreen.new()
	await _open(over)
	over.handle("down")
	over.handle("confirm")
	over.handle("confirm")
	eq(over.page, TitleScreen.Page.OVERWRITE, "a used slot asks before it is overwritten")
	over.handle("confirm")
	eq(over.page, TitleScreen.Page.SLOTS, "never mind goes back")
	over.close()


func test_message_screen_waits_before_accepting() -> void:
	_isolate()
	var screen := MessageScreen.new("YOU DIED", ["A LINE"], [{"id": "a", "text": "A"}, {"id": "b", "text": "B"}])
	var result := await _open(screen)
	screen.handle("confirm")
	check(not result[1], "a button-mashing player cannot skip the death screen instantly")
	screen.frames = 40
	screen.handle("down")
	screen.handle("confirm")
	eq(result[0], "b", "then the highlighted option is returned")


func test_hud_draws_every_element() -> void:
	_isolate()
	var state := _state()
	var hud := Hud.new()
	hud.setup(state, null)
	tree.root.add_child(hud)
	hud.toast("HELLO", Color.WHITE)
	hud.item_toast(Items.make("helmet", "helmet", 0, 0, 1, "rare"), true)
	hud.show_banner("AREA", "SUBTITLE")
	hud.set_hint("A HINT")
	state.data["tallies"]["knacks"].append("echolocation_ping")
	await tree.process_frame
	await tree.process_frame
	eq(hud.toasts.size(), 2, "toasts stack")
	for _i in Hud.TOAST_LIFE + 2:
		await tree.process_frame
	eq(hud.toasts.size(), 0, "and expire")
	hud.queue_free()


func test_main_plays_a_session_of_menus() -> void:
	_isolate()
	var main: Main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	check(main.top() is TitleScreen, "the game opens on the title screen")
	check(tree.paused, "the tree is paused behind a modal")
	main.press("confirm")
	main.press("confirm")
	main.press("confirm")
	await tree.process_frame
	await tree.process_frame
	check(main.world != null and main.hud != null, "a new game builds the world and the HUD")
	check(main.modals.is_empty() and not tree.paused, "and the game is running")
	check(SaveFiles.exists(1), "a new game is saved at once, so CONTINUE always has something")
	await tree.create_timer(0.2).timeout
	main.press("pause")
	check(main.top() is PauseMenu and tree.paused, "pause opens the menu and stops the world")
	main.press("cancel")
	check(main.modals.is_empty() and not tree.paused, "closing it resumes")
	main.press("map")
	check(main.top() is PauseMenu and (main.top() as PauseMenu).tab == 2, "map opens the map tab")
	main.press("map")
	var talked := [false]
	main.world.say("KEVIN", ["THE CRATER IS NOT MY FAULT."], func() -> void: talked[0] = true)
	await tree.process_frame
	check(main.top() is DialogueBox, "a hologram's line opens the dialogue box")
	main.press("confirm")
	main.press("confirm")
	check(talked[0] and main.modals.is_empty(), "finishing it hands control back")
	main.world.player_died.emit()
	await tree.process_frame
	check(main.top() is MessageScreen, "dying shows the death screen")
	for _i in 40:
		await tree.process_frame
	main.press("confirm")
	await tree.process_frame
	await tree.process_frame
	eq(int(main.gs.data["deaths"]), 1, "continuing reloads the save and remembers the death")
	main.world.slice_completed.emit()
	await tree.process_frame
	check(main.top() is MessageScreen, "the end of the slice shows its card")
	for _i in 40:
		await tree.process_frame
	main.press("down")
	main.press("confirm")
	await tree.process_frame
	await tree.process_frame
	check(main.top() is TitleScreen, "back to title returns to the title screen")
	main.queue_free()
	tree.paused = false
