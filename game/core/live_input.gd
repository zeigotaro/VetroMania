class_name LiveInput
extends InputSource
## Keyboard and gamepad through Godot's InputMap (actions are named vm_<action>).


func poll() -> void:
	var now := {}
	for action: String in InputSource.ACTIONS:
		now[action] = Input.is_action_pressed("vm_" + action)
	_apply(now)


## Registers the default bindings from docs/design/player-and-combat.md#controls. Safe to call twice.
static func register_defaults() -> void:
	var keys := {
		"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "up": [KEY_UP, KEY_W], "down": [KEY_DOWN, KEY_S],
		"jump": [KEY_Z, KEY_SPACE], "attack": [KEY_X, KEY_J], "sub": [KEY_C, KEY_K], "dash": [KEY_SHIFT],
		"knack": [KEY_V], "shades": [KEY_Q], "map": [KEY_M], "pause": [KEY_ESCAPE],
		"confirm": [KEY_ENTER, KEY_Z, KEY_SPACE], "cancel": [KEY_BACKSPACE, KEY_X], "tab_prev": [KEY_BRACKETLEFT, KEY_PAGEUP],
		"tab_next": [KEY_BRACKETRIGHT, KEY_PAGEDOWN],
	}
	var buttons := {
		"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT], "up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
		"jump": [JOY_BUTTON_A], "attack": [JOY_BUTTON_X], "sub": [JOY_BUTTON_Y], "dash": [JOY_BUTTON_LEFT_SHOULDER],
		"knack": [JOY_BUTTON_RIGHT_SHOULDER], "map": [JOY_BUTTON_BACK], "pause": [JOY_BUTTON_START],
		"confirm": [JOY_BUTTON_A], "cancel": [JOY_BUTTON_B], "tab_prev": [JOY_BUTTON_LEFT_SHOULDER], "tab_next": [JOY_BUTTON_RIGHT_SHOULDER],
	}
	for action: String in InputSource.ACTIONS:
		var name := "vm_" + action
		if not InputMap.has_action(name):
			InputMap.add_action(name, 0.5)
		else:
			continue
		for code: int in keys.get(action, []):
			var event := InputEventKey.new()
			event.physical_keycode = code as Key
			InputMap.action_add_event(name, event)
		for button: int in buttons.get(action, []):
			var pad := InputEventJoypadButton.new()
			pad.button_index = button as JoyButton
			InputMap.action_add_event(name, pad)
	_add_axis("left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("down", JOY_AXIS_LEFT_Y, 1.0)
	_add_axis("shades", JOY_AXIS_TRIGGER_RIGHT, 1.0)


static var _axes_added := {}


static func _add_axis(action: String, axis: int, value: float) -> void:
	var key := "%s:%d" % [action, axis]
	if _axes_added.has(key):
		return
	_axes_added[key] = true
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	InputMap.action_add_event("vm_" + action, event)
