class_name TitleScreen
extends Modal
## The title screen: CONTINUE, NEW GAME (slot, then difficulty) and QUIT.
## close() returns {"action": "continue" | "new" | "quit", "slot": int, "difficulty": String}.

enum Page { MAIN, SLOTS, OVERWRITE, DIFFICULTY }

const MAIN_ROWS: Array[String] = ["CONTINUE", "NEW GAME", "QUIT"]

var page := Page.MAIN
var index := 0
var new_game := false
var slot := 1
var summaries: Dictionary = {}
var background: Texture2D
var modes: Array[String] = []


func _init() -> void:
	super._init()
	refresh()
	background = SpriteLib.texture(String(Db.manifest()["ui"]["title_bg"]))
	for id: String in Db.difficulty()["modes"]:
		modes.append(id)
	if not _any_saves():
		index = 1


func refresh() -> void:
	summaries.clear()
	for number in range(1, SaveFiles.SLOTS + 1):
		summaries[number] = SaveFiles.summary(number)


func _any_saves() -> bool:
	for number: int in summaries:
		if not (summaries[number] as Dictionary).is_empty():
			return true
	return false


func _rows() -> int:
	match page:
		Page.MAIN:
			return MAIN_ROWS.size()
		Page.SLOTS:
			return SaveFiles.SLOTS
		Page.OVERWRITE:
			return 2
		Page.DIFFICULTY:
			return modes.size()
	return 0


func _go(to: Page, start: int = 0) -> void:
	page = to
	index = start


func handle(action: String) -> void:
	match action:
		"up":
			index = wrapi(index - 1, 0, _rows())
			AudioService.sfx("menu_move", -8.0)
		"down":
			index = wrapi(index + 1, 0, _rows())
			AudioService.sfx("menu_move", -8.0)
		"cancel", "pause":
			if page != Page.MAIN:
				AudioService.sfx("menu_back", -6.0)
				_go(Page.MAIN, 1 if new_game else 0)
		"confirm":
			_confirm()


func _confirm() -> void:
	match page:
		Page.MAIN:
			match index:
				0:
					if _any_saves():
						new_game = false
						_go(Page.SLOTS, _first_save())
						AudioService.sfx("menu_select", -6.0)
					else:
						AudioService.sfx("menu_deny", -6.0)
				1:
					new_game = true
					_go(Page.SLOTS)
					AudioService.sfx("menu_select", -6.0)
				2:
					close({"action": "quit", "slot": 0, "difficulty": ""})
		Page.SLOTS:
			slot = index + 1
			var exists := not (summaries[slot] as Dictionary).is_empty()
			if not new_game:
				if exists:
					AudioService.sfx("title_start")
					close({"action": "continue", "slot": slot, "difficulty": ""})
				else:
					AudioService.sfx("menu_deny", -6.0)
			elif exists:
				_go(Page.OVERWRITE, 1)
			else:
				_go(Page.DIFFICULTY, modes.find(String(Db.difficulty()["default"])))
		Page.OVERWRITE:
			if index == 0:
				_go(Page.DIFFICULTY, modes.find(String(Db.difficulty()["default"])))
			else:
				_go(Page.SLOTS, slot - 1)
		Page.DIFFICULTY:
			var id := modes[index]
			if String(Db.difficulty()["modes"][id]["unlock"]) != "":
				AudioService.sfx("menu_deny", -6.0)
				return
			AudioService.sfx("title_start")
			close({"action": "new", "slot": slot, "difficulty": id})


func _first_save() -> int:
	for number in range(1, SaveFiles.SLOTS + 1):
		if not (summaries[number] as Dictionary).is_empty():
			return number - 1
	return 0


func slot_line(number: int) -> String:
	var summary: Dictionary = summaries[number]
	if summary.is_empty():
		return "SLOT %d   EMPTY" % number
	var area_id := String(summary["room"]).split("_")[0]
	var area := String(Db.areas()["areas"].get(area_id, {}).get("name", "SOMEWHERE"))
	return "SLOT %d   LV %d   %s   %s" % [number, int(summary["level"]), area, UIKit.format_time(float(summary["playtime"]))]


# --- drawing -----------------------------------------------------------------------------------------

func _draw() -> void:
	if background != null:
		draw_texture_rect(background, Rect2(0, 0, 640, 360), false)
	UIKit.draw_panel(self, Rect2(150, 176, 340, 136), Color(0.03, 0.02, 0.09, 0.88))
	match page:
		Page.MAIN:
			_draw_rows(MAIN_ROWS, [not _any_saves(), false, false], 196.0, 24.0)
		Page.SLOTS:
			UIKit.draw_text_center(self, "CONTINUE FROM WHICH SLOT?" if not new_game else "SAVE TO WHICH SLOT?", 320, 184, UIKit.COLORS["dim"])
			var lines: Array[String] = []
			var greyed: Array[bool] = []
			for number in range(1, SaveFiles.SLOTS + 1):
				lines.append(slot_line(number))
				greyed.append(not new_game and (summaries[number] as Dictionary).is_empty())
			_draw_rows(lines, greyed, 204.0, 20.0)
		Page.OVERWRITE:
			UIKit.draw_text_center(self, "THIS SLOT HAS A GAME IN IT.", 320, 186, UIKit.COLORS["bad"])
			UIKit.draw_text_center(self, slot_line(slot), 320, 200, UIKit.COLORS["text"])
			_draw_rows(["OVERWRITE IT", "NEVER MIND"], [false, false], 228.0, 22.0)
		Page.DIFFICULTY:
			UIKit.draw_text_center(self, "HOW MUCH DO YOU LIKE PAIN?", 320, 184, UIKit.COLORS["dim"])
			var lines: Array[String] = []
			var greyed: Array[bool] = []
			for id in modes:
				var mode: Dictionary = Db.difficulty()["modes"][id]
				var locked := String(mode["unlock"]) != ""
				lines.append(String(mode["name"]) + ("   LOCKED: FINISH THE GAME" if locked else ""))
				greyed.append(locked)
			_draw_rows(lines, greyed, 204.0, 18.0)


func _draw_rows(rows: Array, greyed: Array, top: float, step: float) -> void:
	for i in rows.size():
		var y := top + i * step
		if i == index:
			draw_rect(Rect2(160, y - 4, 320, step - 2), UIKit.COLORS["border"].darkened(0.5))
			UIKit.draw_text(self, ">", Vector2(166, y), UIKit.COLORS["select"])
		UIKit.draw_text(self, String(rows[i]), Vector2(182, y), UIKit.COLORS["dim"] if greyed[i] else UIKit.COLORS["text"])
