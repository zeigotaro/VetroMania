class_name PauseMenu
extends Modal
## The pause menu: EQUIP (gear, bag and consumables), TALLIES (Kill Tallies and Knacks), MAP and SYSTEM (options).
## close() returns "title" when the player chose to save and quit.

signal request_montage

const TABS: Array[String] = ["EQUIP", "TALLIES", "MAP", "SYSTEM"]
const ROW := 11
const LIST_TOP := 44
const LIST_ROWS := 24
const LIST_LEFT := 12
const DETAIL_LEFT := 312
const SLOT_LABELS := {
	"helmet": "HELM", "chest": "CHEST", "gauntlets": "GAUNTS", "gloves": "GLOVES", "leggings": "LEGS",
	"boots": "BOOTS", "ring1": "RING 1", "ring2": "RING 2", "weapon": "WEAPON", "sub": "SUB",
}
const SYSTEM_ROWS: Array[String] = ["music", "sfx", "shake", "numbers", "speed", "assist", "fullscreen", "resume", "quit"]

var gs: GameState
var world: World
var tab := 0
var index := 0
var scroll := 0
var message := ""
var message_frames := 0
var entries: Array[Dictionary] = []


func _init(state: GameState = null, world_ref: World = null, start_tab: int = 0) -> void:
	super._init()
	gs = state
	world = world_ref
	tab = start_tab
	_rebuild()


func _rebuild() -> void:
	entries.clear()
	match tab:
		0:
			_build_equip()
		1:
			_build_tallies()
		3:
			for row in SYSTEM_ROWS:
				entries.append({"kind": "system", "row": row})
	if entries.is_empty():
		index = 0
	else:
		index = clampi(index, 0, entries.size() - 1)
		if entries[index].get("kind", "") == "header":
			index = _next_selectable(index, 1)
	_clamp_scroll()


func _build_equip() -> void:
	for slot in Consts.SLOTS:
		entries.append({"kind": "slot", "slot": slot, "item": gs.data["equipped"].get(slot, {}), "locked": not Gear.slot_unlocked(slot, gs.level)})
	var bag: Array[Dictionary] = []
	for item: Dictionary in gs.data["inventory"]:
		if gs.equipped_slot_of(item) == "":
			bag.append(item)
	bag.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["slot"] != b["slot"]:
			return Consts.SLOTS.find(a["slot"] if a["slot"] != "ring" else "ring1") < Consts.SLOTS.find(b["slot"] if b["slot"] != "ring" else "ring1")
		return int(a["ilvl"]) > int(b["ilvl"]))
	if not bag.is_empty():
		entries.append({"kind": "header", "text": "BAG (%d)" % bag.size()})
		for item in bag:
			entries.append({"kind": "bag", "item": item})
	var owned: Array[String] = []
	for id: String in Db.legendary_data()["consumables"]:
		if gs.consumables(id) > 0:
			owned.append(id)
	if not owned.is_empty():
		entries.append({"kind": "header", "text": "ITEMS"})
		for id in owned:
			entries.append({"kind": "consumable", "id": id})


func _build_tallies() -> void:
	for id: String in Db.enemies():
		entries.append({"kind": "enemy", "id": id})


func _next_selectable(from: int, step: int) -> int:
	var next := from
	for _i in entries.size():
		next = wrapi(next + step, 0, entries.size())
		if entries[next].get("kind", "") != "header":
			return next
	return from


func _move(step: int) -> void:
	if entries.is_empty():
		return
	index = _next_selectable(index, step)
	_clamp_scroll()
	AudioService.sfx("menu_move", -8.0)


func _clamp_scroll() -> void:
	if index < scroll:
		scroll = index
	elif index >= scroll + LIST_ROWS:
		scroll = index - LIST_ROWS + 1
	scroll = maxi(0, scroll)


func _say(text: String) -> void:
	message = text
	message_frames = 150


func _switch(step: int) -> void:
	tab = wrapi(tab + step, 0, TABS.size())
	index = 0
	scroll = 0
	_rebuild()
	AudioService.sfx("menu_move", -6.0)


func handle(action: String) -> void:
	match action:
		"pause", "cancel":
			AudioService.sfx("menu_back", -6.0)
			close()
			return
		"map":
			if tab == 2:
				close()
			else:
				tab = 2
				_rebuild()
			return
		"tab_prev":
			_switch(-1)
			return
		"tab_next":
			_switch(1)
			return
	match tab:
		0:
			_handle_equip(action)
		1:
			_handle_tallies(action)
		2:
			if action in ["left", "up"]:
				_switch(-1)
			elif action in ["right", "down"]:
				_switch(1)
		3:
			_handle_system(action)


func _handle_equip(action: String) -> void:
	match action:
		"up":
			_move(-1)
		"down":
			_move(1)
		"left":
			_switch(-1)
		"right":
			_switch(1)
		"sub":
			if gs.montage_points_free() > 0:
				request_montage.emit()
			else:
				AudioService.sfx("menu_deny", -6.0)
		"confirm":
			_confirm_equip()


func _confirm_equip() -> void:
	if entries.is_empty():
		return
	var entry := entries[index]
	match String(entry["kind"]):
		"slot":
			var item: Dictionary = entry["item"]
			if item.is_empty():
				AudioService.sfx("menu_deny", -6.0)
				return
			gs.unequip(String(entry["slot"]))
			AudioService.sfx("equip_item", -4.0)
			_say("REMOVED " + Items.compose_name(item))
		"bag":
			var item: Dictionary = entry["item"]
			var slot := gs.slot_for_item(item)
			var problem := "No free ring slot" if slot == "" else gs.equip(item, slot)
			if problem != "":
				AudioService.sfx("menu_deny", -6.0)
				_say(problem)
			else:
				AudioService.sfx("equip_item", -4.0)
				_say("EQUIPPED " + Items.compose_name(item))
		"consumable":
			var id := String(entry["id"])
			if gs.use_consumable(id):
				AudioService.sfx("pickup_item_common", -4.0)
				_say(String(Db.legendary_data()["consumables"][id]["text"]))
	_rebuild()


func _handle_tallies(action: String) -> void:
	match action:
		"up":
			_move(-1)
		"down":
			_move(1)
		"left":
			_switch(-1)
		"right":
			_switch(1)
		"confirm":
			var perk_id := Tallies.perk_for(String(entries[index]["id"]))
			var def := Tallies.perk_def(perk_id)
			if def.is_empty() or def.get("type", "") != "knack" or not Tallies.has_perk(gs.data["tallies"], perk_id):
				AudioService.sfx("menu_deny", -6.0)
			elif perk_id in gs.data["tallies"]["knacks"]:
				Tallies.unequip_knack(gs.data["tallies"], perk_id)
				_say(String(def["name"]) + " UNEQUIPPED")
			elif Tallies.equip_knack(gs.data["tallies"], perk_id):
				AudioService.sfx("equip_item", -4.0)
				_say(String(def["name"]) + " EQUIPPED ON THE KNACK BUTTON")
			else:
				AudioService.sfx("menu_deny", -6.0)
				_say("NO FREE KNACK SLOT")


func _handle_system(action: String) -> void:
	match action:
		"up":
			_move(-1)
		"down":
			_move(1)
		"left":
			_adjust(-1)
		"right":
			_adjust(1)
		"confirm":
			_adjust(1, true)


func _adjust(step: int, activate: bool = false) -> void:
	var row := String(entries[index]["row"])
	match row:
		"music":
			Settings.music = clampf(snappedf(Settings.music + 0.1 * step, 0.1), 0.0, 1.0)
		"sfx":
			Settings.sfx = clampf(snappedf(Settings.sfx + 0.1 * step, 0.1), 0.0, 1.0)
		"shake":
			Settings.shake = clampf(snappedf(Settings.shake + 0.5 * step, 0.5), 0.0, 1.0)
		"numbers":
			Settings.damage_numbers = not Settings.damage_numbers
		"speed":
			var at := Settings.SPEEDS.find(Settings.speed)
			Settings.speed = Settings.SPEEDS[clampi(at + step, 0, Settings.SPEEDS.size() - 1)]
		"assist":
			Settings.seal_assist = not Settings.seal_assist
		"fullscreen":
			Settings.fullscreen = not Settings.fullscreen
		"resume":
			if activate:
				close()
			return
		"quit":
			if activate:
				gs.save()
				close("title")
			return
	Settings.apply()
	Settings.save_file()
	AudioService.sfx("menu_move", -6.0)


func _process(delta: float) -> void:
	super._process(delta)
	if message_frames > 0:
		message_frames -= 1
		if message_frames == 0:
			message = ""


# --- drawing -----------------------------------------------------------------------------------------

func _draw() -> void:
	UIKit.draw_panel(self, Rect2(4, 4, 632, 352), Color(0.04, 0.03, 0.1, 0.97))
	var x := 14.0
	for i in TABS.size():
		var selected := i == tab
		var width := UIKit.text_width(TABS[i]) + 16
		if selected:
			draw_rect(Rect2(x - 4, 12, width, 16), UIKit.COLORS["border"].darkened(0.4))
			draw_rect(Rect2(x - 4, 12, width, 16), UIKit.COLORS["border"], false, 1.0)
		UIKit.draw_text(self, TABS[i], Vector2(x + 4, 16), UIKit.COLORS["select"] if selected else UIKit.COLORS["dim"])
		x += width + 4
	UIKit.draw_text_right(self, "PGUP/PGDN OR LEFT/RIGHT: TABS   X: BACK", 626, 16, UIKit.COLORS["dim"])
	draw_line(Vector2(8, 32), Vector2(632, 32), UIKit.COLORS["border"].darkened(0.3))
	match tab:
		0:
			_draw_equip()
		1:
			_draw_tallies()
		2:
			_draw_map()
		3:
			_draw_system()
	if message != "":
		UIKit.draw_text(self, message, Vector2(LIST_LEFT, 336), UIKit.COLORS["select"])


func _draw_list(rows: Array[Dictionary], drawer: Callable) -> void:
	for i in LIST_ROWS:
		var at := scroll + i
		if at >= rows.size():
			break
		var y := float(LIST_TOP + i * ROW)
		if at == index:
			draw_rect(Rect2(LIST_LEFT - 3, y - 2, 292, ROW), UIKit.COLORS["border"].darkened(0.5))
			UIKit.draw_text(self, ">", Vector2(LIST_LEFT - 2, y), UIKit.COLORS["select"])
		drawer.call(rows[at], y)
	if scroll > 0:
		UIKit.draw_text_right(self, "^", 296, 36, UIKit.COLORS["dim"])
	if scroll + LIST_ROWS < rows.size():
		UIKit.draw_text_right(self, "MORE", 296, LIST_TOP + LIST_ROWS * ROW, UIKit.COLORS["dim"])


func _draw_equip() -> void:
	_draw_list(entries, _draw_equip_row)
	if entries.is_empty():
		return
	var entry := entries[index]
	var item: Dictionary = entry.get("item", {})
	var y := 40.0
	if not item.is_empty():
		y = ItemCard.draw(self, item, gs.level, Vector2(DETAIL_LEFT, 40), 52, gs.data["equipped"])
	elif entry["kind"] == "consumable":
		var def: Dictionary = Db.legendary_data()["consumables"][entry["id"]]
		draw_texture(Icons.texture(String(def["icon"])), Vector2(DETAIL_LEFT, 40))
		UIKit.draw_text(self, "%s  X%d" % [String(def["name"]), gs.consumables(String(entry["id"]))], Vector2(DETAIL_LEFT + 30, 44), UIKit.COLORS["good"])
		UIKit.draw_text(self, String(def["text"]), Vector2(DETAIL_LEFT + 30, 56), UIKit.COLORS["dim"])
	elif entry["kind"] == "slot":
		var locked: bool = entry["locked"]
		UIKit.draw_text(self, "%s SLOT" % String(SLOT_LABELS[entry["slot"]]), Vector2(DETAIL_LEFT, 44), UIKit.COLORS["dim"])
		if locked:
			UIKit.draw_text(self, "OPENS AT LV %d" % Consts.RING_SLOT_LEVELS[0 if entry["slot"] == "ring1" else 1], Vector2(DETAIL_LEFT, 56), UIKit.COLORS["bad"])
		else:
			UIKit.draw_text(self, "NOTHING WORN. THE BAG MIGHT HELP.", Vector2(DETAIL_LEFT, 56), UIKit.COLORS["dim"])
	_draw_stats(maxf(y + 6.0, 200.0))
	if message == "":
		UIKit.draw_text(self, "Z: EQUIP OR REMOVE   C: TRAIN", Vector2(DETAIL_LEFT, 336), UIKit.COLORS["dim"])


func _draw_equip_row(entry: Dictionary, y: float) -> void:
	match String(entry["kind"]):
		"header":
			UIKit.draw_text(self, entry["text"], Vector2(LIST_LEFT + 4, y), UIKit.COLORS["dim"])
		"slot":
			var label := String(SLOT_LABELS[entry["slot"]])
			var item: Dictionary = entry["item"]
			UIKit.draw_text(self, label, Vector2(LIST_LEFT + 6, y), UIKit.COLORS["dim"])
			if bool(entry["locked"]):
				UIKit.draw_text(self, "LOCKED", Vector2(LIST_LEFT + 62, y), UIKit.COLORS["bad"])
			elif item.is_empty():
				UIKit.draw_text(self, "-", Vector2(LIST_LEFT + 62, y), UIKit.COLORS["dim"])
			else:
				draw_texture_rect(Icons.item_texture(item), Rect2(LIST_LEFT + 60, y - 2, 12, 12), false)
				UIKit.draw_text(self, UIKit.item_title(item).left(36), Vector2(LIST_LEFT + 76, y), UIKit.rarity_color(item["rarity"]))
		"bag":
			var item: Dictionary = entry["item"]
			draw_texture_rect(Icons.item_texture(item), Rect2(LIST_LEFT + 6, y - 2, 12, 12), false)
			var too_low := gs.level < Items.required_level(item)
			var color: Color = UIKit.COLORS["dim"] if too_low else UIKit.rarity_color(item["rarity"])
			UIKit.draw_text(self, UIKit.item_title(item).left(40), Vector2(LIST_LEFT + 22, y), color)
		"consumable":
			var def: Dictionary = Db.legendary_data()["consumables"][entry["id"]]
			draw_texture_rect(Icons.texture(String(def["icon"])), Rect2(LIST_LEFT + 6, y - 2, 12, 12), false)
			UIKit.draw_text(self, "%s X%d" % [String(def["name"]), gs.consumables(String(entry["id"]))], Vector2(LIST_LEFT + 22, y), UIKit.COLORS["good"])


func _draw_stats(y: float) -> void:
	var d := gs.derived
	var stats: Dictionary = d["stats"]
	draw_line(Vector2(DETAIL_LEFT, y - 4), Vector2(626, y - 4), UIKit.COLORS["border"].darkened(0.3))
	UIKit.draw_text(self, "LV %d   XP %d/%d" % [gs.level, gs.xp, gs.xp_needed()], Vector2(DETAIL_LEFT, y), UIKit.COLORS["xp"])
	UIKit.draw_text(self, "HP %d   EP %d" % [int(d["max_hp"]), int(d["max_ep"])], Vector2(DETAIL_LEFT, y + 11), UIKit.COLORS["text"])
	UIKit.draw_text(self, "ATK %d   DEF %d   ARMOR %d" % [int(d["atk"]), int(d["def"]), int(d["armor"])], Vector2(DETAIL_LEFT, y + 22), UIKit.COLORS["text"])
	var line := ""
	for stat in Stats.NAMES:
		line += "%s %d  " % [stat, int(stats[stat])]
	UIKit.draw_text(self, line, Vector2(DETAIL_LEFT, y + 33), UIKit.COLORS["text"])
	UIKit.draw_text(self, "CRIT %d%%   LUCK %d" % [roundi(float(d["crit_chance"])), roundi(float(d["loot_luck"]))], Vector2(DETAIL_LEFT, y + 44), UIKit.COLORS["dim"])
	if gs.montage_points_free() > 0:
		UIKit.draw_text(self, "%d FREE STAT POINTS: PRESS C TO TRAIN" % gs.montage_points_free(), Vector2(DETAIL_LEFT, y + 58), UIKit.COLORS["good"])


func _draw_tallies() -> void:
	var state: Dictionary = gs.data["tallies"]
	_draw_list(entries, func(entry: Dictionary, y: float) -> void:
		var id := String(entry["id"])
		var p := Tallies.progress(state, id)
		var label := String(Db.enemy(id)["name"]) if p["seen"] else "???"
		UIKit.draw_text(self, label, Vector2(LIST_LEFT + 8, y), UIKit.COLORS["text"] if p["seen"] else UIKit.COLORS["dim"])
		UIKit.draw_text_right(self, "%d/%d" % [p["kills"], p["threshold"]], 280, y, UIKit.COLORS["good"] if p["complete"] else UIKit.COLORS["dim"]))
	if entries.is_empty():
		return
	var id := String(entries[index]["id"])
	var def := Db.enemy(id)
	var p := Tallies.progress(state, id)
	var x := float(DETAIL_LEFT)
	UIKit.draw_text(self, String(def["name"]) if p["seen"] else "???", Vector2(x, 44), UIKit.COLORS["select"], 2)
	if not p["seen"]:
		UIKit.draw_text(self, "NOT SEEN YET. GO KILL ONE. FOR SCIENCE.", Vector2(x, 66), UIKit.COLORS["dim"])
		return
	UIKit.draw_text(self, "KILLS %d OF %d" % [p["kills"], p["threshold"]], Vector2(x, 66), UIKit.COLORS["text"])
	UIKit.draw_bar(self, Rect2(x, 78, 300, 8), p["pct"] / 100.0, UIKit.COLORS["good"] if p["complete"] else UIKit.COLORS["xp"])
	for pct in [25, 50]:
		draw_rect(Rect2(x + 300.0 * pct / 100.0, 76, 1, 12), Color(1, 1, 1, 0.7))
	var perk_id := Tallies.perk_for(id)
	var perk := Tallies.perk_def(perk_id)
	var y := 96.0
	var rows := [
		[true, "FIRST KILL: 5X XP"],
		[p["revealed"], "25%%: WEAKNESS REVEALED (%s)" % _weakness(def)],
		[p["rival"], "50%: RIVAL. IT DROPS LOOT 25% MORE OFTEN"],
		[p["complete"], "100%: " + String(perk.get("name", "?")).to_upper()],
	]
	for row: Array in rows:
		UIKit.draw_text(self, ("+ " if row[0] else "- ") + String(row[1]), Vector2(x, y), UIKit.COLORS["good"] if row[0] else UIKit.COLORS["dim"])
		y += 11.0
	y += 6.0
	for line in UIKit.wrap(String(perk.get("text", "")), 52):
		UIKit.draw_text(self, line, Vector2(x, y), UIKit.COLORS["text"] if p["complete"] else UIKit.COLORS["dim"])
		y += 11.0
	if perk.get("type", "") == "knack" and p["complete"]:
		var on: bool = perk_id in state["knacks"]
		UIKit.draw_text(self, "Z: %s   SLOTS %d/%d" % ["UNEQUIP" if on else "EQUIP ON THE KNACK BUTTON (V)", state["knacks"].size(), Tallies.knack_slots(state)], Vector2(x, y + 6), UIKit.COLORS["ep"])


func _weakness(def: Dictionary) -> String:
	var weak := String(def.get("weak", ""))
	var resist := String(def.get("resist", ""))
	var text := "WEAK TO " + weak if weak != "" else "NO WEAKNESS"
	if resist != "":
		text += ", RESISTS " + resist
	return text


func _draw_map() -> void:
	if world == null:
		return
	var level := world.level
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell: Vector2i in level.cell_room:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var span := hi - lo + Vector2i.ONE
	var cell_size := Vector2(minf(58.0, 600.0 / span.x), 0.0)
	cell_size.y = cell_size.x * 0.6
	var origin := Vector2(320.0 - span.x * cell_size.x / 2.0, 170.0 - span.y * cell_size.y / 2.0)
	for cell: Vector2i in level.cell_room:
		var room: Dictionary = level.room_at_cell(cell)
		var rect := Rect2(origin + Vector2(cell - lo) * cell_size, cell_size)
		if gs.has_visited(cell):
			var color := Color(String(Db.areas()["areas"][room["area"]]["color"]))
			draw_rect(rect.grow(-1), color.darkened(0.35))
			draw_rect(rect.grow(-1), color, false, 1.0)
		elif _next_to_visited(cell):
			draw_rect(rect.grow(-1), Color(1, 1, 1, 0.07), false, 1.0)
	for prop: Prop in world.props:
		if not is_instance_valid(prop) or not (prop.kind in ["save_pod", "warp"]):
			continue
		var cell := MapCells.cell_of(prop.global_position + Vector2(0, -8))
		if not gs.has_visited(cell):
			continue
		var local := (prop.global_position - Vector2(cell * Consts.CELL_PX)) / Vector2(Consts.CELL_PX)
		var at := origin + (Vector2(cell - lo) + local) * cell_size
		draw_rect(Rect2(at - Vector2(2, 4), Vector2(4, 4)), UIKit.COLORS["hp"] if prop.kind == "save_pod" else UIKit.COLORS["xp"])
	if world.player != null and frames % 40 < 26:
		var here := (world.player.global_position + World.PLAYER_CENTER) / Vector2(Consts.CELL_PX) - Vector2(lo)
		draw_rect(Rect2(origin + here * cell_size - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
	var percent := MapCells.percent(gs.visited_count(), level.total_cells())
	UIKit.draw_text_center(self, "MAP %d%%   %d/%d CELLS" % [roundi(percent), gs.visited_count(), level.total_cells()], 320, 250, UIKit.COLORS["xp"])
	UIKit.draw_text_center(self, "RED: SAVE POD   YELLOW: WARP PIPE   WHITE: YOU", 320, 268, UIKit.COLORS["dim"])
	var x := 130.0
	for id: String in Db.areas()["order"]:
		var area: Dictionary = Db.areas()["areas"][id]
		draw_rect(Rect2(x, 292, 8, 8), Color(String(area["color"])))
		UIKit.draw_text(self, String(area["name"]), Vector2(x + 12, 292), UIKit.COLORS["text"])
		x += UIKit.text_width(String(area["name"])) + 30.0
	UIKit.draw_text_center(self, "THE MIRROR PLANET IS NOT ON THIS MAP. YET.", 320, 316, UIKit.COLORS["dim"])


func _next_to_visited(cell: Vector2i) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if gs.has_visited(cell + step):
			return true
	return false


func _draw_system() -> void:
	var labels := {
		"music": "MUSIC VOLUME", "sfx": "EFFECTS VOLUME", "shake": "SCREEN SHAKE", "numbers": "DAMAGE NUMBERS",
		"speed": "GAME SPEED", "assist": "SEAL ASSIST", "fullscreen": "FULLSCREEN", "resume": "RESUME", "quit": "SAVE AND QUIT TO TITLE",
	}
	_draw_list(entries, func(entry: Dictionary, y: float) -> void:
		var row := String(entry["row"])
		UIKit.draw_text(self, String(labels[row]), Vector2(LIST_LEFT + 8, y), UIKit.COLORS["text"])
		var value := ""
		match row:
			"music":
				value = "%d%%" % roundi(Settings.music * 100.0)
			"sfx":
				value = "%d%%" % roundi(Settings.sfx * 100.0)
			"shake":
				value = "%d%%" % roundi(Settings.shake * 100.0)
			"numbers":
				value = "ON" if Settings.damage_numbers else "OFF"
			"speed":
				value = "%d%%" % roundi(Settings.speed * 100.0)
			"assist":
				value = "ON" if Settings.seal_assist else "OFF"
			"fullscreen":
				value = "ON" if Settings.fullscreen else "OFF"
		UIKit.draw_text_right(self, value, 280, y, UIKit.COLORS["select"]))
	var mode: Dictionary = gs.mode()
	var x := float(DETAIL_LEFT)
	UIKit.draw_text(self, "THIS RUN", Vector2(x, 44), UIKit.COLORS["select"])
	UIKit.draw_text(self, "MODE: %s" % String(mode["name"]), Vector2(x, 60), UIKit.COLORS["text"])
	UIKit.draw_text(self, "PLAYTIME: %s" % UIKit.format_time(float(gs.data["playtime"])), Vector2(x, 71), UIKit.COLORS["text"])
	UIKit.draw_text(self, "DEATHS: %d" % int(gs.data["deaths"]), Vector2(x, 82), UIKit.COLORS["text"])
	UIKit.draw_text(self, "KILLS: %d" % _total_kills(), Vector2(x, 93), UIKit.COLORS["text"])
	UIKit.draw_text(self, "SEAL WINDOW: %d SECONDS" % int(mode["seal_window"]), Vector2(x, 104), UIKit.COLORS["dim"])
	var assist := UIKit.wrap("SEAL ASSIST: ANY ATTACK PRESS SIGNS THE AUTOGRAPH. NO MOTION REQUIRED. NO JUDGMENT.", 50)
	for i in assist.size():
		UIKit.draw_text(self, assist[i], Vector2(x, 130.0 + i * 11.0), UIKit.COLORS["dim"])
	UIKit.draw_text(self, "LEFT/RIGHT: CHANGE   Z: SELECT", Vector2(x, 336), UIKit.COLORS["dim"])


func _total_kills() -> int:
	var total := 0
	for id: String in gs.data["tallies"]["kills"]:
		total += int(gs.data["tallies"]["kills"][id])
	return total
