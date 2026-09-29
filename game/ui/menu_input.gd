class_name MenuInput
extends RefCounted
## Polls the keyboard and pad for menu actions, with key repeat on the directions. Main feeds the result to
## the top modal. prime() swallows whatever is already held so the press that opened a menu cannot also
## pick its first entry.

const ACTIONS: Array[String] = ["up", "down", "left", "right", "confirm", "cancel", "tab_prev", "tab_next", "pause", "map", "sub"]
const REPEATING: Array[String] = ["up", "down", "left", "right"]
const FIRST_DELAY := 18
const REPEAT_EVERY := 5

var _held := {}
var _timers := {}


func prime() -> void:
	for action: String in ACTIONS:
		_held[action] = Input.is_action_pressed("vm_" + action)
		_timers[action] = 0


func poll() -> Array[String]:
	var out: Array[String] = []
	for action: String in ACTIONS:
		var down := Input.is_action_pressed("vm_" + action)
		var was := bool(_held.get(action, false))
		if down and not was:
			out.append(action)
			_timers[action] = 0
		elif down and action in REPEATING:
			_timers[action] = int(_timers.get(action, 0)) + 1
			var held_for := int(_timers[action]) - FIRST_DELAY
			if held_for >= 0 and held_for % REPEAT_EVERY == 0:
				out.append(action)
		_held[action] = down
	return out
