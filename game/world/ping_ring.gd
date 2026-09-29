class_name PingRing
extends Node2D
## The visible pulse of Echolocation Ping: an expanding cyan ring that fades out.

var max_radius := 640.0
var age := 0
var life := 36


func _init(radius: float = 640.0) -> void:
	max_radius = radius
	z_index = 60


func _physics_process(_delta: float) -> void:
	age += 1
	queue_redraw()
	if age >= life:
		queue_free()


func _draw() -> void:
	var t := float(age) / life
	var radius := max_radius * (1.0 - pow(1.0 - t, 3.0))
	var color := Color(0.4, 0.95, 1.0, 1.0 - t)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, color, 2.0)
	draw_arc(Vector2.ZERO, maxf(0.0, radius - 6.0), 0.0, TAU, 96, Color(color.r, color.g, color.b, color.a * 0.4), 1.0)
