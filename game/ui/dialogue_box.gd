class_name DialogueBox
extends Modal
## A speaker and a few lines, typed out one character at a time. Confirm finishes the line, then moves on.

const CHARS_PER_FRAME := 1.3
const WRAP := 92

var speaker := ""
var lines: Array = []
var index := 0
var shown := 0.0
var wrapped: Array[String] = []


func _init(who: String = "", dialogue_lines: Array = []) -> void:
	super._init()
	speaker = who
	lines = dialogue_lines
	_load_line()


func _load_line() -> void:
	wrapped = UIKit.wrap(String(lines[index]) if index < lines.size() else "", WRAP)
	shown = 0.0


func total_chars() -> int:
	var total := 0
	for line in wrapped:
		total += line.length()
	return total


func handle(action: String) -> void:
	if action != "confirm" and action != "cancel":
		return
	if shown < total_chars():
		shown = total_chars()
		return
	AudioService.sfx("menu_select", -6.0)
	index += 1
	if index >= lines.size():
		close()
	else:
		_load_line()


func _process(delta: float) -> void:
	super._process(delta)
	var before := int(shown)
	shown = minf(float(total_chars()), shown + CHARS_PER_FRAME)
	if int(shown) != before and int(shown) % 3 == 0:
		AudioService.sfx("dialogue_blip", -12.0, 1.0 + 0.05 * float(hash(speaker) % 7))


func _draw() -> void:
	var panel := Rect2(20, 262, 600, 88)
	UIKit.draw_panel(self, panel)
	if speaker != "":
		var tab := Rect2(30, 252, UIKit.text_width(speaker) + 16, 16)
		UIKit.draw_panel(self, tab)
		UIKit.draw_text(self, speaker, Vector2(38, 256), UIKit.COLORS["select"])
	var budget := int(shown)
	var y := 276.0
	for line in wrapped:
		var part := line.substr(0, maxi(0, budget))
		UIKit.draw_text(self, part, Vector2(32, y))
		budget -= line.length()
		y += 11.0
	if shown >= total_chars() and frames % 40 < 26:
		UIKit.draw_text_right(self, ">" if index < lines.size() - 1 else "OK", 608, 336, UIKit.COLORS["select"])
