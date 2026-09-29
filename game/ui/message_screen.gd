class_name MessageScreen
extends Modal
## A centred message with a few choices: the death screen and the end-of-slice card.
## close() returns the id of the chosen option.

var title := ""
var title_color: Color = UIKit.COLORS["bad"]
var lines: Array[String] = []
var options: Array[Dictionary] = []
var index := 0
var heading_scale := 2


func _init(heading: String = "", body: Array[String] = [], choices: Array[Dictionary] = [], color: Color = UIKit.COLORS["bad"], title_scale: int = 2) -> void:
	super._init()
	title = heading
	lines = body
	options = choices
	title_color = color
	heading_scale = title_scale


func handle(action: String) -> void:
	match action:
		"up":
			index = wrapi(index - 1, 0, options.size())
			AudioService.sfx("menu_move", -8.0)
		"down":
			index = wrapi(index + 1, 0, options.size())
			AudioService.sfx("menu_move", -8.0)
		"confirm":
			if frames > 30:
				AudioService.sfx("menu_select", -6.0)
				close(options[index]["id"])


func _draw() -> void:
	var fade := clampf(frames / 40.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 640, 360), Color(0, 0, 0, 0.72 * fade))
	var panel_height := 90.0 + lines.size() * 12.0 + options.size() * 18.0
	var top := 180.0 - panel_height / 2.0
	UIKit.draw_panel(self, Rect2(120, top, 400, panel_height), Color(0.04, 0.03, 0.1, 0.96 * fade), title_color)
	var wrapped := UIKit.wrap(title, int(380 / (6 * heading_scale)))
	var y := top + 14.0
	for line in wrapped:
		UIKit.draw_text_center(self, line, 320, y, title_color, heading_scale)
		y += 9.0 * heading_scale + 4.0
	y += 4.0
	for line in lines:
		UIKit.draw_text_center(self, line, 320, y, UIKit.COLORS["text"])
		y += 12.0
	y += 10.0
	for i in options.size():
		if i == index:
			draw_rect(Rect2(150, y - 4, 340, 16), UIKit.COLORS["border"].darkened(0.5))
			UIKit.draw_text(self, ">", Vector2(156, y), UIKit.COLORS["select"])
		UIKit.draw_text_center(self, String(options[i]["text"]), 320, y, UIKit.COLORS["text"])
		y += 18.0
