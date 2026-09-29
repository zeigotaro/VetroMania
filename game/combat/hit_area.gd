class_name HitArea
extends Area2D
## Something that hurts Sleve: enemy bodies, enemy projectiles, spikes, boss attacks.
## Lives on the enemy_attack physics layer; the Player's hurtbox polls the ones it overlaps.

var source: Node
var mult := 1.0
var element := ""
var level := 1
var active := true
var kind := "contact"


func _init(box: Vector2 = Vector2(16, 16), center: Vector2 = Vector2.ZERO) -> void:
	collision_layer = 1 << 4
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
