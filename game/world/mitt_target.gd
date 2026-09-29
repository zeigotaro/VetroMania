class_name MittTarget
extends StaticBody2D
## A glowing catcher's-mitt bullseye. Only a charged Mitt Cannon shot opens the room's conduit shutters.

var tile := Vector2i.ZERO
var key := ""
var room_id := ""
var world: Node
var hurt: HurtArea
var lit := false


func setup(data: Dictionary, world_ref: Node) -> void:
	tile = data["tile"]
	key = data["key"]
	room_id = data["room"]
	world = world_ref
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(Consts.TILE, Consts.TILE)
	shape.shape = box
	shape.position = Vector2(tile * Consts.TILE) + box.size / 2.0
	add_child(shape)
	hurt = HurtArea.new(box.size + Vector2(6, 6), shape.position, HurtArea.LAYER_BREAKABLE)
	hurt.target = self
	add_child(hurt)


func hit_info() -> Dictionary:
	return {"def": 0.0, "weak": "", "resist": ""}


func receive_hit(_result: Dictionary, hit: Dictionary) -> void:
	if lit:
		return
	if bool(hit.get("charged", false)) and String(hit.get("family", "")) == "mitt_cannon":
		lit = true
		GameState.current.mark_opened(key)
		if world != null and world.has_method("open_shutters"):
			world.call("open_shutters", room_id)
	else:
		AudioService.sfx("menu_deny", -8.0, 1.5)
