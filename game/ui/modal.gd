class_name Modal
extends Control
## A full-screen menu or box that takes over the input while it is open. Main pauses the world, feeds
## handle() one action at a time (up, down, left, right, confirm, cancel, tab_prev, tab_next, pause, map, sub)
## and frees the modal when it calls close().

signal closed(result: Variant)

var frames := 0
var done := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(Consts.VIEW)


func handle(_action: String) -> void:
	pass


func close(result: Variant = null) -> void:
	if done:
		return
	done = true
	closed.emit(result)
	queue_free()


func _process(_delta: float) -> void:
	frames += 1
	queue_redraw()
