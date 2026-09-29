class_name Main
extends Node
## The whole game: the title screen, the World with its HUD and menus, death and the end of the slice.
## While any modal is open the scene tree is paused; modals run with PROCESS_MODE_ALWAYS.

var world: World
var hud: Hud
var gs: GameState
var slot := 1
var hud_layer: CanvasLayer
var ui_layer: CanvasLayer
var modals: Array[Modal] = []
var menu_input := MenuInput.new()
var live_input: LiveInput
var ended := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LiveInput.register_defaults()
	Settings.load_file()
	if AudioService.instance == null:
		add_child(AudioService.new())
	Settings.apply()
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	show_title()


func _process(_delta: float) -> void:
	for action in menu_input.poll():
		press(action)


## One menu action, from the keyboard or from a test.
func press(action: String) -> void:
	if not modals.is_empty():
		modals.back().handle(action)
	elif world != null and world.player != null and not world.player.is_frozen() and world.player.mode != Player.Mode.DEAD:
		if action == "pause":
			open_pause(0)
		elif action == "map":
			open_pause(2)


func top() -> Modal:
	return modals.back() if not modals.is_empty() else null


func push(modal: Modal) -> Modal:
	modals.append(modal)
	ui_layer.add_child(modal)
	get_tree().paused = true
	menu_input.prime()
	modal.closed.connect(func(_result: Variant) -> void: _on_closed(modal))
	return modal


func _on_closed(modal: Modal) -> void:
	modals.erase(modal)
	menu_input.prime()
	if modals.is_empty():
		get_tree().paused = false
		if live_input != null:
			live_input.suppress_until_release()


# --- the game -----------------------------------------------------------------------------------------

func show_title() -> void:
	_clear_game()
	AudioService.music("hull_cathedral")
	var title := push(TitleScreen.new())
	title.closed.connect(_on_title)


func _on_title(result: Dictionary) -> void:
	slot = int(result["slot"])
	match String(result["action"]):
		"quit":
			get_tree().quit()
		"new":
			var fresh := GameState.begin(slot, String(result["difficulty"]))
			fresh.save()
			start(fresh)
		"continue":
			var saved := SaveFiles.read(slot)
			if bool(saved["ok"]):
				start(GameState.from_save(slot, saved["state"]))
			else:
				show_title()


func start(state: GameState) -> void:
	_clear_game()
	gs = state
	ended = false
	live_input = LiveInput.new()
	world = World.new()
	add_child(world)
	world.has_ui = true
	hud = Hud.new()
	hud.setup(gs, world)
	hud_layer.add_child(hud)
	world.dialogue_requested.connect(_on_dialogue)
	world.pod_requested.connect(_on_pod)
	world.warp_requested.connect(_on_warp)
	world.seal_requested.connect(_on_seal)
	world.toast_requested.connect(func(text: String, color: Color) -> void: hud.toast(text, color))
	world.item_toast_requested.connect(func(item: Dictionary, equipped: bool) -> void: hud.item_toast(item, equipped))
	world.hint_changed.connect(func(text: String) -> void: hud.set_hint(text))
	world.boss_changed.connect(func(boss: BossKrate) -> void: hud.set_boss(boss))
	world.montage_requested.connect(func() -> void: push(MontageMenu.new(gs)))
	world.area_entered.connect(_on_area)
	world.player_died.connect(_on_death)
	world.slice_completed.connect(_on_end)
	world.build(gs, live_input)


func _clear_game() -> void:
	for modal in modals.duplicate():
		modal.queue_free()
	modals.clear()
	if world != null:
		world.queue_free()
		world = null
	if hud != null:
		hud.queue_free()
		hud = null
	get_tree().paused = false
	Combat.hitstop = 0


func open_pause(start_tab: int) -> void:
	var menu := PauseMenu.new(gs, world, start_tab)
	menu.request_montage.connect(func() -> void: push(MontageMenu.new(gs)))
	menu.closed.connect(func(result: Variant) -> void:
		if result == "title":
			show_title())
	push(menu)
	AudioService.sfx("menu_select", -6.0)


func _on_dialogue(speaker: String, lines: Array, done: Callable) -> void:
	var box := push(DialogueBox.new(speaker, lines))
	box.closed.connect(func(_result: Variant) -> void: done.call())


func _on_pod(_prop: Prop) -> void:
	hud.toast("GAME SAVED. HP AND EP RESTORED.", UIKit.COLORS["good"])
	var menu := push(PodMenu.new(gs))
	menu.closed.connect(func(_result: Variant) -> void: world.player.freeze(false))


func _on_warp(prop: Prop) -> void:
	var menu := push(WarpMenu.new(world, prop))
	menu.closed.connect(func(result: Variant) -> void:
		world.player.freeze(false)
		if result is Prop:
			world.teleport_to((result as Prop).global_position))


func _on_seal(seal_id: int, practice: bool, done: Callable) -> void:
	var overlay := push(SealOverlay.new(seal_id, practice, world.player.facing, gs.mode()))
	overlay.closed.connect(func(result: Variant) -> void: done.call(bool(result)))


func _on_area(area_id: String, first_time: bool) -> void:
	if not first_time:
		return
	var area: Dictionary = Db.areas()["areas"][area_id]
	var levels: Array = area["levels"]
	var subtitle := "HUB. ENEMIES SCALE WITH YOUR PROGRESS" if area.get("hub", false) else "ENEMY LEVELS %d-%d" % [levels[0], levels[1]]
	hud.show_banner(String(area["name"]), subtitle)


func _on_death() -> void:
	var messages: Array = Db.difficulty()["death_messages"]
	var lines: Array[String] = ["YOU KEEP EVERYTHING YOU HAD AT THE LAST SAVE POD."]
	var options: Array[Dictionary] = [{"id": "continue", "text": "CONTINUE FROM THE LAST SAVE"}, {"id": "title", "text": "QUIT TO TITLE"}]
	var screen := push(MessageScreen.new(String(messages[randi() % messages.size()]), lines, options))
	var deaths := int(gs.data["deaths"]) + 1
	screen.closed.connect(func(choice: Variant) -> void:
		if choice == "continue":
			var saved := SaveFiles.read(slot)
			if bool(saved["ok"]):
				var reloaded := GameState.from_save(slot, saved["state"])
				reloaded.data["deaths"] = deaths
				start(reloaded)
				return
		show_title())


func _on_end() -> void:
	if ended:
		return
	ended = true
	gs.save()
	var kills := 0
	for id: String in gs.data["tallies"]["kills"]:
		kills += int(gs.data["tallies"]["kills"][id])
	var percent := MapCells.percent(gs.visited_count(), world.level.total_cells())
	var lines: Array[String] = [
		"LEVEL %d   KILLS %d   MAP %d%%   TIME %s" % [gs.level, kills, roundi(percent), UIKit.format_time(float(gs.data["playtime"]))],
		"THE NAG-9000 REMAINS UNIMPRESSED.",
		"HOTCOFFEE STILL HAS THE SPACEBALL CARD.",
		"THE PLANET FLIPS NEXT. THE MIRROR PLANET AWAITS.",
	]
	var options: Array[Dictionary] = [{"id": "stay", "text": "KEEP EXPLORING"}, {"id": "title", "text": "BACK TO TITLE"}]
	var screen := push(MessageScreen.new("END OF THE VERTICAL SLICE", lines, options, UIKit.COLORS["select"]))
	screen.closed.connect(func(choice: Variant) -> void:
		if choice == "title":
			show_title())
