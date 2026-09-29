class_name EnemyBolt
extends HitArea
## A bolt fired by an enemy (the Hunch-Bot's satellite dish). Hurts Sleve on touch and dies on walls.

var velocity := Vector2.ZERO
var life := 200
var sprite: AnimSprite
var _probe: Area2D


static func spawn(parent: Node, at: Vector2, direction: Vector2, speed: float, enemy_level: int, damage_mult: float, damage_element: String, shooter: Node) -> EnemyBolt:
	var bolt := EnemyBolt.new(Vector2(8, 8), Vector2.ZERO)
	bolt.position = at
	bolt.velocity = direction.normalized() * speed
	bolt.level = enemy_level
	bolt.mult = damage_mult
	bolt.element = damage_element
	bolt.source = shooter
	bolt.kind = "projectile"
	parent.add_child(bolt)
	return bolt


func _ready() -> void:
	sprite = AnimSprite.new(["props/enemy_bolt"])
	sprite.play_key("props/enemy_bolt", true)
	sprite.offset = SpriteLib.offset_for("props/enemy_bolt", false)
	sprite.set_facing(1 if velocity.x >= 0.0 else -1)
	add_child(sprite)
	_probe = Area2D.new()
	_probe.collision_layer = 0
	_probe.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, 6)
	shape.shape = rect
	_probe.add_child(shape)
	add_child(_probe)
	_probe.body_entered.connect(func(_body: Node) -> void: queue_free())


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0:
		return
	position += velocity * Consts.DT
	life -= 1
	if life <= 0:
		queue_free()
