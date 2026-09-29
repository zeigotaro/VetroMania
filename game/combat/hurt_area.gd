class_name HurtArea
extends Area2D
## Something Sleve can hit: enemies (layer 3) and breakable gates (layer 8). `target` receives
## receive_hit(hit: Dictionary) where hit = {amount, crit, weak, resist, kind, family, heavy, direction, charged, source}.

const LAYER_ENEMY := 1 << 2
const LAYER_BREAKABLE := 1 << 7

var target: Node


func _init(box: Vector2 = Vector2(16, 16), center: Vector2 = Vector2.ZERO, layer: int = LAYER_ENEMY) -> void:
	collision_layer = layer
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = box
	shape.shape = rect
	shape.position = center
	add_child(shape)


func resize(box: Vector2, center: Vector2 = Vector2.ZERO) -> void:
	var shape := get_child(0) as CollisionShape2D
	(shape.shape as RectangleShape2D).size = box
	shape.position = center
