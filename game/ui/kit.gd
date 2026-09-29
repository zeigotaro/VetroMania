class_name UIKit
extends RefCounted
## Small helpers for building pixel-crisp UI in code. The font is a 5x7 bitmap: sizes must be multiples of 7.

const NATIVE := 7
const COLORS := {
	"text": Color("e8e8f0"), "dim": Color("8a8aa8"), "hp": Color("ff4a5a"), "ep": Color("4fb3ff"),
	"xp": Color("ffd23a"), "panel": Color(0.05, 0.04, 0.12, 0.94), "border": Color("8a6cff"),
	"select": Color("ffd23a"), "good": Color("6fe07a"), "bad": Color("ff6a6a"), "shadow": Color(0, 0, 0, 0.9),
}

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/ui/font/vetro5x7.fnt")
	return _font


static func text_width(text: String, scale: int = 1) -> int:
	return text.length() * 6 * scale


static func style(label: Label, color: Color, scale: int) -> void:
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", NATIVE * scale)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", COLORS["shadow"])
	label.add_theme_constant_override("shadow_offset_x", scale)
	label.add_theme_constant_override("shadow_offset_y", scale)
	label.add_theme_constant_override("line_spacing", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func label(text: String, color: Color = COLORS["text"], scale: int = 1, at: Vector2 = Vector2.ZERO) -> Label:
	var node := Label.new()
	node.text = text.to_upper()
	node.position = at
	style(node, color, scale)
	return node


static func rich(text: String, color: Color = COLORS["text"], scale: int = 1, width: int = 200) -> Label:
	var node := label(text, color, scale)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(width, 0)
	node.size = Vector2(width, 0)
	return node


## A bordered panel drawn with plain rects so it stays crisp at any window size.
class PanelBox extends Control:
	var fill: Color = UIKit.COLORS["panel"]
	var border: Color = UIKit.COLORS["border"]

	func _init(rect: Rect2 = Rect2()) -> void:
		position = rect.position
		size = rect.size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.0)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), border.darkened(0.5), false, 1.0)


## A horizontal bar (HP, EP, XP, boss HP).
class BarMeter extends Control:
	var value := 1.0
	var color: Color = UIKit.COLORS["hp"]
	var back := Color(0.1, 0.08, 0.16, 0.9)
	var lag := 1.0

	func _init(bar_size: Vector2 = Vector2(80, 6), bar_color: Color = UIKit.COLORS["hp"]) -> void:
		size = bar_size
		color = bar_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(fraction: float) -> void:
		value = clampf(fraction, 0.0, 1.0)
		queue_redraw()

	func _process(_delta: float) -> void:
		if not is_equal_approx(lag, value):
			lag = move_toward(lag, value, 0.01) if lag > value else value
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), back)
		if lag > value:
			draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * lag, size.y - 2)), Color(1, 1, 1, 0.5))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * value, size.y - 2)), color)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, 1.0)
