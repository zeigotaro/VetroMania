class_name Gate
extends StaticBody2D
## Breakable tile groups. A crate bulkhead (X) breaks on any melee hit once Sleve owns the Beam Bat. A hollow
## wall (%) tonks on the first two hits and breaks on the third. A conduit shutter (C) opens when its room's
## mitt target is hit by a charged Mitt Cannon shot. Perks like Echolocation Ping only reveal hollow walls.

signal opened(gate: Gate)

const HITS_TO_BREAK := 3
const HOLLOW_TONKS := 2

var kind := "%"
var tiles: Array[Vector2i] = []
var key := ""
var room_id := ""
var hits := 0
var world: Node
var hurt: HurtArea
var glint: AnimSprite
var reveal_frames := 0
var shake := 0
var bounds := Rect2()


func setup(data: Dictionary, world_ref: Node) -> void:
	kind = data["kind"]
	key = data["key"]
	room_id = data["room"]
	tiles.assign(data["tiles"])
	world = world_ref
	collision_layer = 1
	collision_mask = 0
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for tile in tiles:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(Consts.TILE, Consts.TILE)
		shape.shape = box
		shape.position = Vector2(tile * Consts.TILE) + box.size / 2.0
		add_child(shape)
		lo = lo.min(Vector2(tile * Consts.TILE))
		hi = hi.max(Vector2(tile * Consts.TILE) + box.size)
	bounds = Rect2(lo, hi - lo)
	if kind != "C":
		hurt = HurtArea.new(bounds.size + Vector2(6, 6), bounds.get_center(), HurtArea.LAYER_BREAKABLE)
		hurt.target = self
		add_child(hurt)
	if kind == "%":
		glint = AnimSprite.new(["props/pickup_glint"])
		glint.position = bounds.get_center()
		glint.z_index = 20
		glint.visible = false
		glint.play_key("props/pickup_glint", true)
		glint.scale = Vector2(2, 2)
		add_child(glint)


func _physics_process(_delta: float) -> void:
	if reveal_frames > 0:
		reveal_frames -= 1
		glint.visible = reveal_frames % 40 < 30
		if not glint.is_playing():
			glint.play_key("props/pickup_glint", true)
	elif glint != null and glint.visible:
		glint.visible = false
	if shake > 0:
		shake -= 1
		position.x = 1.0 if shake % 2 == 0 else -1.0
		if shake == 0:
			position.x = 0.0


func hit_info() -> Dictionary:
	return {"def": 0.0, "weak": "", "resist": ""}


## Ping reveals where hollow walls are; it never breaks them.
func reveal_for(frames: int) -> void:
	if kind == "%":
		reveal_frames = maxi(reveal_frames, frames)


func receive_hit(_result: Dictionary, hit: Dictionary) -> void:
	var gs := GameState.current
	if kind == "C" or gs == null:
		return
	if String(hit.get("kind", "")) != "melee" or not gs.has_ability("beam_bat"):
		AudioService.sfx("door_locked", -4.0)
		return
	if kind == "X":
		open()
		return
	hits += 1
	if hits >= HITS_TO_BREAK:
		open()
	else:
		AudioService.sfx("hollow_tonk")
		shake = 6


func open() -> void:
	var gs := GameState.current
	if gs != null:
		gs.mark_opened(key)
	AudioService.sfx("wall_break" if kind != "C" else "door_open")
	if world != null and world.has_method("erase_tiles"):
		world.call("erase_tiles", tiles)
	_debris()
	opened.emit(self)
	queue_free()


func _debris() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for _i in 10:
		var chip := ColorRect.new()
		chip.size = Vector2(3, 3)
		chip.color = Color("8a6a5a") if kind == "%" else Color("b08a4a")
		chip.position = bounds.get_center() + Vector2(rng.randf_range(-bounds.size.x / 2.0, bounds.size.x / 2.0), rng.randf_range(-bounds.size.y / 2.0, bounds.size.y / 2.0))
		chip.z_index = 30
		parent.add_child(chip)
		var tween := chip.create_tween().set_parallel(true)
		tween.tween_property(chip, "position", chip.position + Vector2(rng.randf_range(-30, 30), rng.randf_range(10, 40)), 0.5)
		tween.tween_property(chip, "modulate:a", 0.0, 0.5)
		tween.chain().tween_callback(chip.queue_free)
