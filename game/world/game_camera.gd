class_name GameCamera
extends Camera2D
## Follows Sleve, clamped to the current room (one cell is 640 x 368, so single-cell rooms scroll only 8 px
## vertically). Positions are snapped to whole pixels so the art never shimmers. Moving into a new room
## glides the camera across instead of cutting.

const VIEW := Vector2(640, 360)
const LEAD := 20.0
const GLIDE := 0.2

var room_rect := Rect2(0, 0, 640, 368)
var target := Vector2.ZERO
var shake_strength := 0.0
var shake_frames := 0
var _lead := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	make_current()
	position_smoothing_enabled = false
	ignore_rotation = true


func set_room(rect: Rect2, instant: bool = false) -> void:
	room_rect = rect
	if instant:
		global_position = _clamped(target)


func follow(focus: Vector2, facing: int) -> void:
	_lead = lerpf(_lead, facing * LEAD, 0.08)
	target = focus + Vector2(_lead, -24)
	var goal := _clamped(target)
	var next := global_position.lerp(goal, GLIDE)
	if next.distance_to(goal) < 0.4:
		next = goal
	var jitter := Vector2.ZERO
	if shake_frames > 0:
		shake_frames -= 1
		jitter = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake_strength
	global_position = (next + jitter).round()


func _clamped(point: Vector2) -> Vector2:
	var half := VIEW / 2.0
	var lo := room_rect.position + half
	var hi := room_rect.end - half
	return Vector2(clampf(point.x, lo.x, maxf(lo.x, hi.x)), clampf(point.y, lo.y, maxf(lo.y, hi.y)))


func shake(strength: float, frames: int) -> void:
	shake_strength = strength
	shake_frames = frames
