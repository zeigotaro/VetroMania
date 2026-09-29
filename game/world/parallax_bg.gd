class_name ParallaxBg
extends CanvasLayer
## Three background layers per area (far, mid, near), 1280 px wide behind a 640 px view. They scroll by how far
## the camera is through the current area, so the art never has to loop.

const FACTORS := [0.15, 0.35, 0.6]
const SCROLL_RANGE := 640.0

var layers: Array[Sprite2D] = []
var area_id := ""
var area_span := Vector2(0, 640)
var fade := 1.0


func _init() -> void:
	layer = -10
	for _i in 3:
		var sprite := Sprite2D.new()
		sprite.centered = false
		layers.append(sprite)
		add_child(sprite)


## span: the x-range in pixels of the area's rooms.
func set_area(id: String, span: Vector2) -> void:
	if id == area_id:
		area_span = span
		return
	area_id = id
	area_span = span
	var files: Dictionary = Db.manifest()["backgrounds"][Db.areas()["areas"][id]["background"]]
	for i in 3:
		layers[i].texture = SpriteLib.texture(files[["far", "mid", "near"][i]])
	fade = 0.0


func update_scroll(camera_x: float) -> void:
	var range_px := maxf(1.0, area_span.y - area_span.x - 640.0)
	var t := clampf((camera_x - 320.0 - area_span.x) / range_px, 0.0, 1.0)
	for i in 3:
		layers[i].position = Vector2(-roundf(t * SCROLL_RANGE * FACTORS[i]), 0)
	if fade < 1.0:
		fade = minf(1.0, fade + 0.04)
		for sprite in layers:
			sprite.modulate.a = fade
