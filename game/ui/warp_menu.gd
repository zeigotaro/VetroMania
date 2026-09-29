class_name WarpMenu
extends Modal
## Warp pipes Sleve has already found. Choosing one closes the menu with that pipe as the result.

var world: World
var here: Prop
var pipes: Array[Prop] = []
var index := 0


func _init(world_ref: World = null, current: Prop = null) -> void:
	super._init()
	world = world_ref
	here = current
	if world != null:
		pipes = world.pipe_props()
	for i in pipes.size():
		if pipes[i] == here:
			index = i


func handle(action: String) -> void:
	match action:
		"up":
			if not pipes.is_empty():
				index = wrapi(index - 1, 0, pipes.size())
				AudioService.sfx("menu_move", -8.0)
		"down":
			if not pipes.is_empty():
				index = wrapi(index + 1, 0, pipes.size())
				AudioService.sfx("menu_move", -8.0)
		"confirm":
			if pipes.is_empty() or pipes[index] == here:
				AudioService.sfx("menu_deny", -6.0)
			else:
				close(pipes[index])
		"cancel", "pause":
			AudioService.sfx("menu_back", -6.0)
			close(null)


func label_for(pipe: Prop) -> String:
	var room := world.level.room(pipe.room_id)
	return String(room.get("title", pipe.room_id)).replace("_", " ")


func _draw() -> void:
	UIKit.draw_panel(self, Rect2(120, 60, 400, 240), Color(0.04, 0.03, 0.1, 0.97))
	UIKit.draw_text_center(self, "WELCOME TO WARP ZONE!", 320, 72, UIKit.COLORS["xp"], 2)
	UIKit.draw_text_center(self, "PICK A PIPE. DON'T LOOK AT THE PIRANHA PLANTS.", 320, 94, UIKit.COLORS["dim"])
	for i in pipes.size():
		var y := 116.0 + i * 16.0
		var current := pipes[i] == here
		if i == index:
			draw_rect(Rect2(132, y - 3, 376, 14), UIKit.COLORS["border"].darkened(0.5))
			UIKit.draw_text(self, ">", Vector2(136, y), UIKit.COLORS["select"])
		UIKit.draw_text(self, label_for(pipes[i]) + ("  (YOU ARE HERE)" if current else ""), Vector2(150, y), UIKit.COLORS["dim"] if current else UIKit.COLORS["text"])
	if pipes.size() < 2:
		UIKit.draw_text_center(self, "ONLY ONE PIPE FOUND SO FAR. FIND ANOTHER.", 320, 240, UIKit.COLORS["dim"])
	UIKit.draw_text_center(self, "Z: WARP   X: BACK", 320, 282, UIKit.COLORS["dim"])
