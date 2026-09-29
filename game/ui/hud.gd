class_name Hud
extends Control
## Heads-up display, painted in one _draw(): HP, EP and XP, money, the minimap, toasts, the area banner, hints and
## the boss bar. It only reads the GameState and the World; nothing in the game reads it back.

const MAP_COLUMNS := 9
const MAP_ROWS := 6
const CELL := Vector2(8, 5)
const TOAST_LIFE := 170
const MAX_TOASTS := 4

var gs: GameState
var world: World
var boss: BossKrate
var hint := ""
var toasts: Array[Dictionary] = []
var banner := {}
var frames := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Consts.VIEW)
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(state: GameState, world_ref: World) -> void:
	gs = state
	world = world_ref


func toast(text: String, color: Color = UIKit.COLORS["text"]) -> void:
	toasts.append({"text": text, "color": color, "age": 0})
	while toasts.size() > MAX_TOASTS:
		toasts.pop_front()


func item_toast(item: Dictionary, equipped: bool) -> void:
	var suffix := "  EQUIPPED" if equipped else "  IN THE BAG"
	toast(UIKit.item_title(item) + suffix, UIKit.rarity_color(item["rarity"]))


func show_banner(title: String, subtitle: String = "") -> void:
	banner = {"title": title, "subtitle": subtitle, "age": 0}


func set_hint(text: String) -> void:
	hint = text


func set_boss(value: BossKrate) -> void:
	boss = value


func _process(_delta: float) -> void:
	frames += 1
	for entry in toasts:
		entry["age"] = int(entry["age"]) + 1
	toasts = toasts.filter(func(entry: Dictionary) -> bool: return int(entry["age"]) < TOAST_LIFE)
	if not banner.is_empty():
		banner["age"] = int(banner["age"]) + 1
		if int(banner["age"]) > 200:
			banner = {}
	queue_redraw()


func _draw() -> void:
	if gs == null:
		return
	_draw_vitals()
	_draw_purse()
	_draw_minimap()
	_draw_knack()
	_draw_hint()
	_draw_boss()
	_draw_toasts()
	_draw_banner()


func _draw_vitals() -> void:
	var max_hp := float(gs.derived["max_hp"])
	var max_ep := float(gs.derived["max_ep"])
	UIKit.draw_panel(self, Rect2(6, 6, 176, 48))
	UIKit.draw_text(self, "LV %d" % gs.level, Vector2(14, 11), UIKit.COLORS["xp"])
	UIKit.draw_text_right(self, "%d/%d" % [ceili(gs.hp), int(max_hp)], 174, 11, UIKit.COLORS["hp"])
	UIKit.draw_bar(self, Rect2(14, 21, 160, 8), gs.hp / maxf(1.0, max_hp), UIKit.COLORS["hp"])
	UIKit.draw_bar(self, Rect2(14, 31, 120, 6), gs.ep / maxf(1.0, max_ep), UIKit.COLORS["ep"])
	UIKit.draw_text_right(self, "%d/%d" % [floori(gs.ep), int(max_ep)], 174, 30, UIKit.COLORS["ep"])
	var need := gs.xp_needed()
	UIKit.draw_bar(self, Rect2(14, 41, 160, 4), (float(gs.xp) / need) if need > 0 else 1.0, UIKit.COLORS["xp"])


func _draw_purse() -> void:
	UIKit.draw_text_right(self, "$%d" % gs.bucks, 634, 8, UIKit.COLORS["xp"])
	UIKit.draw_text_right(self, "W%d A%d" % [gs.gems("weapon"), gs.gems("armor")], 634, 18, UIKit.COLORS["dim"])


func _draw_minimap() -> void:
	if world == null or world.player == null:
		return
	var here := MapCells.cell_of(world.player.global_position + World.PLAYER_CENTER)
	var origin := Vector2(634 - MAP_COLUMNS * CELL.x, 30)
	UIKit.draw_panel(self, Rect2(origin - Vector2(3, 3), Vector2(MAP_COLUMNS * CELL.x + 5, MAP_ROWS * CELL.y + 5)), Color(0.03, 0.02, 0.08, 0.8))
	for dy in MAP_ROWS:
		for dx in MAP_COLUMNS:
			var cell := here + Vector2i(dx - MAP_COLUMNS / 2, dy - MAP_ROWS / 2)
			var room := world.level.room_at_cell(cell)
			if room.is_empty() or not gs.has_visited(cell):
				continue
			var color := Color(String(Db.areas()["areas"][room["area"]]["color"]))
			var rect := Rect2(origin + Vector2(dx * CELL.x, dy * CELL.y), CELL - Vector2.ONE)
			draw_rect(rect, color.darkened(0.25))
			if cell == here:
				draw_rect(rect, Color.WHITE if frames % 40 < 26 else color)
	if bool(gs.runtime_flags.get("uplink", false)):
		for marker in world.item_markers():
			var cell := MapCells.cell_of(marker + Vector2(0, -8))
			var offset := cell - here + Vector2i(MAP_COLUMNS / 2, MAP_ROWS / 2)
			if offset.x >= 0 and offset.x < MAP_COLUMNS and offset.y >= 0 and offset.y < MAP_ROWS:
				var local := (marker - Vector2(cell * Consts.CELL_PX)) / Vector2(Consts.CELL_PX)
				draw_rect(Rect2(origin + Vector2(offset) * CELL + local * CELL, Vector2(2, 2)), UIKit.COLORS["select"])


func _draw_knack() -> void:
	var knacks: Array = gs.data["tallies"]["knacks"]
	if knacks.is_empty():
		return
	var def := Tallies.perk_def(String(knacks[0]))
	var cost := float(def.get("ep", 0.0))
	var text := "V: %s" % String(def.get("name", "?"))
	if cost > 0.0:
		text += " (%d EP)" % int(cost)
	UIKit.draw_text(self, text, Vector2(8, 346), UIKit.COLORS["ep"] if gs.ep >= cost else UIKit.COLORS["dim"])


func _draw_hint() -> void:
	if hint == "":
		return
	var width := UIKit.text_width(hint) + 16
	var rect := Rect2(320 - width / 2.0, 316, width, 16)
	draw_rect(rect, Color(0.04, 0.03, 0.1, 0.8))
	UIKit.draw_text_center(self, hint, 320, 320, UIKit.COLORS["text"])


func _draw_boss() -> void:
	if boss == null or not is_instance_valid(boss) or boss.dead:
		return
	var bar := Rect2(170, 338, 300, 10)
	UIKit.draw_text_center(self, String(boss.def["name"]), 320, 326, UIKit.COLORS["bad"])
	UIKit.draw_bar(self, bar, boss.hp / maxf(1.0, boss.max_hp), UIKit.COLORS["hp"])
	if boss.phase2:
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.5, 0), Vector2(1, bar.size.y)), Color(1, 1, 1, 0.6))


func _draw_toasts() -> void:
	var y := 8.0
	for entry in toasts:
		var text := String(entry["text"])
		var age := int(entry["age"])
		var width := UIKit.text_width(text) + 14
		var slide := clampf(1.0 - age / 10.0, 0.0, 1.0) * -22.0
		var fade := clampf((TOAST_LIFE - age) / 20.0, 0.0, 1.0)
		var rect := Rect2(320 - width / 2.0, y + slide, width, 15)
		draw_rect(rect, Color(0.05, 0.04, 0.12, 0.88 * fade))
		draw_rect(rect, Color(entry["color"], 0.9 * fade), false, 1.0)
		UIKit.draw_text_center(self, text, 320, y + slide + 4, Color(entry["color"], fade))
		y += 17.0


func _draw_banner() -> void:
	if banner.is_empty():
		return
	var age := int(banner["age"])
	var alpha := clampf(minf(age / 24.0, (200 - age) / 30.0), 0.0, 1.0)
	UIKit.draw_text_center(self, String(banner["title"]), 320, 96, Color(UIKit.COLORS["text"], alpha), 2)
	if String(banner["subtitle"]) != "":
		UIKit.draw_text_center(self, String(banner["subtitle"]), 320, 118, Color(UIKit.COLORS["dim"], alpha))
