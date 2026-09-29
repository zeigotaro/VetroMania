class_name AnimSprite
extends AnimatedSprite2D
## AnimatedSprite2D that plays manifest sprites by key and keeps the pivot at the node origin.
## Sprites face right; set_facing(-1) flips around the pivot.

var facing := 1
var key := ""


func _init(keys: Array = []) -> void:
	centered = false
	if not keys.is_empty():
		sprite_frames = SpriteLib.frames_for(keys)
		key = keys[0]


func play_key(sprite_key: String, restart: bool = false) -> void:
	if sprite_key == key and not restart and is_playing():
		return
	key = sprite_key
	play(SpriteLib.anim_name(sprite_key))
	if restart:
		frame = 0
	_place()


func set_facing(direction: int) -> void:
	if direction != 0 and direction != facing:
		facing = direction
		_place()


func _place() -> void:
	flip_h = facing < 0
	offset = SpriteLib.offset_for(key, flip_h)


## Stretches or squeezes the animation so it lasts `frames` physics frames.
func fit_to_frames(frames: int) -> void:
	var entry := SpriteLib.info(key)
	if entry.is_empty() or frames <= 0:
		return
	var natural := float(entry["frames"]) / float(entry["fps"])
	speed_scale = natural / (frames / float(Consts.FPS))
