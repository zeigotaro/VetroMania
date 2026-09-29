class_name Projectile
extends Area2D
## Sleve's shots: Mitt Cannon bolts, Spread Gun pellets, Throwables and The Bobson's ricochet spaceball.
## Runs on the player_attack layer and hits HurtAreas (enemies, mitt targets) or dies on walls.

var velocity := Vector2.ZERO
var mult := 1.0
var kind := "sub"
var family := "mitt_cannon"
var charged := false
var life := 90
var pierce := false
var boomerang_after := 0
var homing := false
var extra_mult := 1.0
var owner_player: Node2D
var sprite: AnimSprite
var spin := 0.0
var _hits := {}
var _age := 0
var _returning := false
var _speed := 0.0


static func spawn(parent: Node, at: Vector2, direction: Vector2, speed: float, sprite_key: String, options: Dictionary = {}) -> Projectile:
	var shot := Projectile.new()
	shot.velocity = direction.normalized() * speed
	shot._speed = speed
	shot.position = at
	for key: String in options:
		if key != "sprite_scale":
			shot.set(key, options[key])
	var size := Vector2(10, 8) if not options.get("charged", false) else Vector2(24, 14)
	shot.collision_layer = 1 << 3
	shot.collision_mask = HurtArea.LAYER_ENEMY | HurtArea.LAYER_BREAKABLE | 1
	shot.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shot.add_child(shape)
	shot.sprite = AnimSprite.new([sprite_key])
	shot.sprite.offset = SpriteLib.offset_for(sprite_key, false)
	shot.sprite.play_key(sprite_key)
	shot.sprite.set_facing(1 if direction.x >= 0.0 else -1)
	shot.add_child(shot.sprite)
	if options.get("sprite_scale", 1.0) != 1.0:
		shot.sprite.scale = Vector2.ONE * float(options["sprite_scale"])
	parent.add_child(shot)
	shot.area_entered.connect(shot._on_area)
	shot.body_entered.connect(shot._on_body)
	return shot


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0:
		return
	_age += 1
	if homing:
		var target := _nearest_enemy()
		if target != null:
			velocity = velocity.lerp((target.global_position + Vector2(0, -24) - global_position).normalized() * _speed, 0.25)
	if boomerang_after > 0 and _age == boomerang_after:
		_returning = true
		_hits.clear()
	if _returning and owner_player != null:
		velocity = (owner_player.global_position + Vector2(0, -28) - global_position).normalized() * _speed
		if global_position.distance_to(owner_player.global_position + Vector2(0, -28)) < 14.0:
			queue_free()
			return
	position += velocity * Consts.DT
	if spin != 0.0:
		sprite.rotation += spin
	if _age >= life:
		queue_free()


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance := 240.0
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node2D and not _hits.has(enemy.get_instance_id()):
			var distance := global_position.distance_to((enemy as Node2D).global_position)
			if distance < best_distance:
				best_distance = distance
				best = enemy
	return best


func _on_body(_body: Node) -> void:
	if not pierce and not _returning:
		_burst()


func _on_area(area: Area2D) -> void:
	if not (area is HurtArea):
		return
	var target: Node = (area as HurtArea).target
	if target == null or _hits.has(target.get_instance_id()):
		return
	_hits[target.get_instance_id()] = true
	var state := GameState.current
	if state == null:
		return
	var info: Dictionary = target.hit_info()
	var result := Combat.player_hit(state, float(info.get("def", 0.0)), mult, info, {"kind": kind, "extra_mult": extra_mult})
	var hit := {
		"kind": "projectile", "family": family, "charged": charged, "heavy": charged,
		"direction": signi(int(velocity.x)) if velocity.x != 0.0 else 1, "source": owner_player, "position": global_position,
	}
	target.receive_hit(result, hit)
	if not pierce and boomerang_after == 0 and not homing:
		_burst()
	elif homing:
		queue_free()


func _burst() -> void:
	AudioService.sfx("enemy_hit", -6.0)
	queue_free()
