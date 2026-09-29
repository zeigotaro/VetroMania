class_name InputSource
extends RefCounted
## One frame of player intent. Subclasses fill `now` in poll(); edges are derived here, so a scripted
## bot and a keyboard take exactly the same code path through the Player.

const ACTIONS: Array[String] = [
	"left", "right", "up", "down", "jump", "attack", "sub", "dash", "knack", "shades",
	"map", "pause", "confirm", "cancel", "tab_prev", "tab_next",
]

var held := {}
var pressed := {}
var released := {}
var frame := 0


func poll() -> void:
	_apply({})


func _apply(now: Dictionary) -> void:
	pressed = {}
	released = {}
	for action: String in ACTIONS:
		var down := bool(now.get(action, false))
		var was := bool(held.get(action, false))
		if down and not was:
			pressed[action] = true
		elif was and not down:
			released[action] = true
		held[action] = down
	frame += 1


func is_held(action: String) -> bool:
	return bool(held.get(action, false))


func just_pressed(action: String) -> bool:
	return bool(pressed.get(action, false))


func just_released(action: String) -> bool:
	return bool(released.get(action, false))


## Horizontal and vertical direction, y positive down.
func direction() -> Vector2i:
	return Vector2i(int(is_held("right")) - int(is_held("left")), int(is_held("down")) - int(is_held("up")))


func clear() -> void:
	held = {}
	pressed = {}
	released = {}
