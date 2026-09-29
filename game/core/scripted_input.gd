class_name ScriptedInput
extends InputSource
## Replays a script of [frames, [actions]] segments, then holds nothing. Used by tests and bots.
##   ScriptedInput.new([[30, ["right"]], [1, ["right", "jump"]], [20, ["right", "jump"]]])
## A Callable(frame: int) -> Array can also drive it for reactive bots.

var _segments: Array = []
var _segment := 0
var _left := 0
var _callback := Callable()


func _init(segments: Array = [], callback: Callable = Callable()) -> void:
	_segments = segments
	_callback = callback
	if not _segments.is_empty():
		_left = int(_segments[0][0])


func done() -> bool:
	return _callback.is_null() and _segment >= _segments.size()


func poll() -> void:
	var now := {}
	var actions: Array = []
	if not _callback.is_null():
		actions = _callback.call(frame)
	elif _segment < _segments.size():
		actions = _segments[_segment][1]
		_left -= 1
		if _left <= 0:
			_segment += 1
			if _segment < _segments.size():
				_left = int(_segments[_segment][0])
	for action: String in actions:
		now[action] = true
	_apply(now)
