class_name Hazard
extends HitArea
## A moving danger spawned by a boss: floor shockwaves and falling mini-crates. Dies on walls, and on the floor
## when break_on_floor is set. Never travels through Sleve's hit-stop.

var velocity := Vector2.ZERO
var life := 120
var falling := false
var break_on_floor := false
var visual: Node2D
var _probe: Area2D


static func spawn(parent: Node, at: Vector2, box: Vector2, speed_vector: Vector2, enemy_level: int, damage_mult: float, frames: int, shooter: Node, options: Dictionary = {}) -> Hazard:
	var hazard := Hazard.new(box, Vector2(0, -box.y / 2.0))
	hazard.position = at
	hazard.velocity = speed_vector
	hazard.level = enemy_level
	hazard.mult = damage_mult
	hazard.life = frames
	hazard.source = shooter
	hazard.kind = String(options.get("kind", "wave"))
	hazard.falling = bool(options.get("falling", false))
	hazard.break_on_floor = bool(options.get("break_on_floor", false))
	parent.add_child(hazard)
	var art := String(options.get("art", "wave"))
	if art == "crate":
		var sprite := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = SpriteLib.texture(Db.manifest()["tiles"]["atlases"]["outer"])
		var cell := WorldBuilder.tile_cell("crate")
		atlas.region = Rect2(cell.x * Consts.TILE, cell.y * Consts.TILE, Consts.TILE, Consts.TILE)
		sprite.texture = atlas
		sprite.position = Vector2(0, -box.y / 2.0)
		hazard.visual = sprite
	else:
		var bolt := AnimSprite.new(["props/enemy_bolt"])
		bolt.play_key("props/enemy_bolt", true)
		bolt.offset = SpriteLib.offset_for("props/enemy_bolt", false) + Vector2(0, -box.y / 2.0)
		bolt.scale = Vector2(2.0, 1.6)
		bolt.modulate = Color(1.0, 0.7, 0.4)
		bolt.set_facing(1 if speed_vector.x >= 0.0 else -1)
		hazard.visual = bolt
	hazard.add_child(hazard.visual)
	return hazard


func _ready() -> void:
	_probe = Area2D.new()
	_probe.collision_layer = 0
	_probe.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4, 4)
	shape.shape = rect
	shape.position = Vector2(0, -2)
	_probe.add_child(shape)
	add_child(_probe)
	_probe.body_entered.connect(_on_world)


func _on_world(_body: Node) -> void:
	if falling and not break_on_floor:
		return
	queue_free()


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0:
		return
	position += velocity * Consts.DT
	life -= 1
	if life <= 0:
		queue_free()
