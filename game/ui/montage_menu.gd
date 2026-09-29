class_name MontageMenu
extends Modal
## The Training Montage: every fifth level, two free stat points. Unspent points wait in the pause menu.

const HINTS := {
	"STR": "MELEE DAMAGE", "CON": "MAX HP AND DEFENSE", "INT": "MAX EP AND SUB-WEAPON DAMAGE",
	"DEX": "CRIT CHANCE AND SUB-WEAPON DAMAGE", "LCK": "LOOT LUCK",
}

var gs: GameState
var index := 0
var spent_here := 0


func _init(state: GameState = null) -> void:
	super._init()
	gs = state


func handle(action: String) -> void:
	var rows := Stats.NAMES.size() + 1
	match action:
		"up":
			index = wrapi(index - 1, 0, rows)
			AudioService.sfx("menu_move", -8.0)
		"down":
			index = wrapi(index + 1, 0, rows)
			AudioService.sfx("menu_move", -8.0)
		"confirm":
			if index == Stats.NAMES.size():
				_finish()
			elif gs.allocate(Stats.NAMES[index]):
				spent_here += 1
				AudioService.sfx("level_up", -6.0)
				if gs.montage_points_free() == 0:
					_finish()
			else:
				AudioService.sfx("menu_deny", -6.0)
		"cancel", "pause":
			_finish()


func _finish() -> void:
	gs.montage_seen()
	close(spent_here)


func _draw() -> void:
	UIKit.draw_panel(self, Rect2(150, 50, 340, 260), Color(0.04, 0.03, 0.1, 0.97))
	UIKit.draw_text_center(self, "TRAINING MONTAGE!", 320, 62, UIKit.COLORS["xp"], 2)
	UIKit.draw_text_center(self, "(A GUITAR RIFF PLAYS. SLEVE DOES PUSH-UPS ON A HULL.)", 320, 84, UIKit.COLORS["dim"])
	var free := gs.montage_points_free()
	UIKit.draw_text_center(self, "%d FREE POINT%s" % [free, "" if free == 1 else "S"], 320, 100, UIKit.COLORS["good"] if free > 0 else UIKit.COLORS["dim"])
	var stats: Dictionary = gs.derived["stats"]
	for i in Stats.NAMES.size():
		var stat: String = Stats.NAMES[i]
		var y := 124.0 + i * 20.0
		if i == index:
			draw_rect(Rect2(160, y - 4, 320, 17), UIKit.COLORS["border"].darkened(0.5))
			UIKit.draw_text(self, ">", Vector2(164, y), UIKit.COLORS["select"])
		UIKit.draw_text(self, stat, Vector2(180, y), UIKit.COLORS["text"])
		UIKit.draw_text(self, str(int(stats[stat])), Vector2(224, y), UIKit.COLORS["xp"])
		UIKit.draw_text(self, "(+%d TRAINED)" % int(gs.data["player"]["allocated"].get(stat, 0)), Vector2(256, y), UIKit.COLORS["dim"])
	var done_y := 124.0 + Stats.NAMES.size() * 20.0
	if index == Stats.NAMES.size():
		draw_rect(Rect2(160, done_y - 4, 320, 17), UIKit.COLORS["border"].darkened(0.5))
		UIKit.draw_text(self, ">", Vector2(164, done_y), UIKit.COLORS["select"])
	UIKit.draw_text(self, "DONE", Vector2(180, done_y), UIKit.COLORS["text"])
	if index < Stats.NAMES.size():
		UIKit.draw_text_center(self, String(HINTS[Stats.NAMES[index]]), 320, 268, UIKit.COLORS["dim"])
	UIKit.draw_text_center(self, "Z: ADD A POINT   X: SAVE THE REST FOR LATER", 320, 288, UIKit.COLORS["dim"])
