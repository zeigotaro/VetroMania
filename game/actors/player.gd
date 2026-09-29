class_name Player
extends CharacterBody2D
## Sleve Bonzalez. Movement follows docs/design/player-and-combat.md#movement at a fixed 60 Hz:
## one physics frame is one step of the numbers in Consts and Motion. Input arrives through an
## InputSource, so tests and bots drive exactly the same code as a keyboard.

signal died
signal damaged(amount: int)
signal knack_used(perk_id: String)
signal interacted(target: Node)

enum Mode { NORMAL, SLIDE, DASH, BALL, HURT, DEAD, FROZEN }

const STAND := Vector2(18, 56)
const CROUCH := Vector2(18, 40)
const BALL := Vector2(24, 24)
const CORNER := 6
const DOUBLE_TAP_FRAMES := 12
const MORPH_FRAMES := 4
const HURT_FRAMES := 14
const TAUNT_FRAMES := 180

var input: InputSource = LiveInput.new()
var mode := Mode.NORMAL
var facing := 1
var sprite: AnimSprite
var shape: CollisionShape2D
var hurtbox: Area2D
var interact_area: Area2D
var attack: PlayerAttack

var coyote := 0
var jump_buffer := 0
var attack_buffer := 0
var dash_buffer := 0
var jump_frames := 0
var jumping := false
var cut_applied := false
var air_jump_used := false
var kick_frames := 0
var wall_slide := false
var wall_grace := 0
var wall_side_last := 0
var slide_frames := 0
var dash_frames := 0
var dash_cooldown := 0
var invuln := 0
var hurt_frames := 0
var dead_frames := 0
var down_tap_timer := 0
var morph_timer := 0
var drop_frames := 0
var battle_cry_frames := 0
var still_frames := 0
var was_on_floor := false
var last_fall_speed := 0.0
var god_mode := false
var autofire := false

var _platform_body: Node


func _init() -> void:
	collision_layer = 1 << 1
	collision_mask = 1
	floor_snap_length = 4.0
	floor_max_angle = deg_to_rad(46.0)
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	safe_margin = 0.1
	add_to_group("player")


func _ready() -> void:
	shape = CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	add_child(shape)
	_set_box(STAND)
	sprite = AnimSprite.new([
		"sleve/idle", "sleve/run", "sleve/swing", "sleve/jump", "sleve/spaceball",
		"sleve/slide", "sleve/backdash", "sleve/hurt", "sleve/wall_slide",
	])
	sprite.play_key("sleve/idle", true)
	add_child(sprite)
	hurtbox = Area2D.new()
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = 1 << 4
	hurtbox.monitorable = false
	var hurt_shape := CollisionShape2D.new()
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = Vector2(14, 48)
	hurt_shape.shape = hurt_rect
	hurt_shape.position = Vector2(0, -26)
	hurtbox.add_child(hurt_shape)
	add_child(hurtbox)
	interact_area = Area2D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 1 << 6
	interact_area.monitorable = false
	var interact_shape := CollisionShape2D.new()
	var interact_rect := RectangleShape2D.new()
	interact_rect.size = Vector2(28, 52)
	interact_shape.shape = interact_rect
	interact_shape.position = Vector2(0, -28)
	interact_area.add_child(interact_shape)
	add_child(interact_area)
	attack = PlayerAttack.new(self)


func _set_box(size: Vector2) -> void:
	(shape.shape as RectangleShape2D).size = size
	shape.position = Vector2(0, -size.y / 2.0)


func state() -> GameState:
	return GameState.current


func is_frozen() -> bool:
	return mode == Mode.FROZEN


func freeze(on: bool) -> void:
	if on and mode != Mode.DEAD:
		mode = Mode.FROZEN
		velocity.x = 0.0
		attack.cancel()
	elif not on and mode == Mode.FROZEN:
		mode = Mode.NORMAL


func is_ball() -> bool:
	return mode == Mode.BALL


func on_floor() -> bool:
	return is_on_floor()


func can_attack() -> bool:
	return mode == Mode.NORMAL and not wall_slide


func can_use_sub() -> bool:
	return mode in [Mode.NORMAL, Mode.DASH]


func battle_cry_mult() -> float:
	return 1.0 + float(state().derived["battle_cry"]) / 100.0 if battle_cry_frames > 0 else 1.0


func spawn_spark(at: Vector2) -> void:
	var spark := AnimSprite.new(["props/hit_spark"])
	spark.position = at
	spark.z_index = 50
	spark.play_key("props/hit_spark", true)
	spark.offset = SpriteLib.offset_for("props/hit_spark", false)
	spark.animation_finished.connect(spark.queue_free)
	get_parent().add_child(spark)


## Puts Sleve back on his feet at a position with full control (used for spawns and respawns).
func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	mode = Mode.NORMAL
	invuln = 60
	dead_frames = 0
	attack.cancel()
	_set_box(STAND)
	sprite.modulate = Color.WHITE
	sprite.visible = true


func _physics_process(_delta: float) -> void:
	input.poll()
	if Combat.hitstop > 0 or state() == null:
		_buffer_inputs()
		return
	_tick_timers()
	_buffer_inputs()
	match mode:
		Mode.NORMAL:
			_normal()
		Mode.SLIDE:
			_slide()
		Mode.DASH:
			_dash()
		Mode.BALL:
			_ball()
		Mode.HURT:
			_hurt()
		Mode.DEAD:
			_dead()
		Mode.FROZEN:
			_frozen()
	if mode != Mode.DEAD:
		attack.update()
	_corner_correct()
	move_and_slide()
	_after_move()
	_check_damage()
	_animate()


func _buffer_inputs() -> void:
	if input.just_pressed("jump"):
		jump_buffer = Consts.BUFFER_FRAMES
	if input.just_pressed("attack"):
		attack_buffer = 8
	if input.just_pressed("dash"):
		dash_buffer = 6


func _tick_timers() -> void:
	if is_on_floor():
		coyote = Consts.COYOTE_FRAMES
	else:
		coyote = maxi(0, coyote - 1)
	jump_buffer = maxi(0, jump_buffer - 1)
	attack_buffer = maxi(0, attack_buffer - 1)
	dash_buffer = maxi(0, dash_buffer - 1)
	dash_cooldown = maxi(0, dash_cooldown - 1)
	invuln = maxi(0, invuln - 1)
	down_tap_timer = maxi(0, down_tap_timer - 1)
	drop_frames = maxi(0, drop_frames - 1)
	if drop_frames == 0 and _platform_body != null:
		remove_collision_exception_with(_platform_body)
		_platform_body = null
	battle_cry_frames = maxi(0, battle_cry_frames - 1)
	if input.is_held("left") or input.is_held("right") or input.is_held("jump") or input.is_held("attack") or not is_on_floor():
		still_frames = 0
	else:
		still_frames += 1
	if wall_grace > 0:
		wall_grace -= 1
	var gs := state()
	gs.combat_timer = maxf(0.0, gs.combat_timer - Consts.DT)
	gs.restore_ep(Consts.EP_REGEN_PER_SEC * Consts.DT)
	if gs.combat_timer <= 0.0 and float(gs.derived["hp_regen"]) > 0.0 and not gs.is_dead():
		gs.heal(float(gs.derived["hp_regen"]) * Consts.DT)


# --- modes --------------------------------------------------------------------------------------------

func _normal() -> void:
	var gs := state()
	var dir := input.direction()
	var floor_now := is_on_floor()
	if floor_now:
		air_jump_used = false
		wall_slide = false
	var rooted := attack.roots_on_ground() and floor_now
	if dir.x != 0 and not rooted and kick_frames == 0:
		facing = dir.x
	if _try_dash() or _try_slide(dir, floor_now) or _try_morph(dir, floor_now):
		return
	if dir.y < 0 and input.just_pressed("knack"):
		_taunt()
	elif input.just_pressed("knack"):
		_knack()
	elif input.just_pressed("up") and floor_now and not attack.is_attacking():
		_interact()
	var run_input := 0.0 if rooted else float(dir.x)
	if kick_frames > 0:
		kick_frames -= 1
		if kick_frames == 0:
			velocity.x = 0.0
	else:
		velocity.x = Motion.run_step(velocity.x, run_input)
	_wall_logic(dir, floor_now)
	var jump_frame := _try_jump(floor_now, dir)
	if not jump_frame:
		_gravity(floor_now)
	if floor_now and not jumping:
		velocity.y = minf(velocity.y, 12.0)
	if gs.is_dead():
		_die()


func _try_dash() -> bool:
	if dash_buffer > 0 and dash_cooldown == 0:
		dash_buffer = 0
		mode = Mode.DASH
		dash_frames = Consts.BACKDASH_FRAMES
		dash_cooldown = Consts.BACKDASH_COOLDOWN_FRAMES
		invuln = maxi(invuln, Consts.BACKDASH_INVULN_FRAMES)
		attack.cancel()
		velocity.x = -facing * (Consts.BACKDASH_DISTANCE * (1.0 + float(state().derived["slide_pct"]) / 100.0) / Consts.BACKDASH_FRAMES) * Consts.FPS
		AudioService.sfx("backdash")
		return true
	return false


func _try_slide(dir: Vector2i, floor_now: bool) -> bool:
	if floor_now and dir.y > 0 and jump_buffer > 0 and not attack.is_attacking():
		if _standing_on_platform() and not _blocked_below_solid():
			_drop_through()
			jump_buffer = 0
			return false
		jump_buffer = 0
		mode = Mode.SLIDE
		slide_frames = Consts.SLIDE_FRAMES
		_set_box(CROUCH)
		AudioService.sfx("slide")
		return true
	return false


func _try_morph(dir: Vector2i, floor_now: bool) -> bool:
	if not state().has_ability("spaceball"):
		return false
	if input.just_pressed("down") and floor_now:
		if down_tap_timer > 0:
			down_tap_timer = 0
			mode = Mode.BALL
			morph_timer = MORPH_FRAMES
			_set_box(BALL)
			attack.cancel()
			velocity.x = 0.0
			AudioService.sfx("spaceball_morph")
			return true
		down_tap_timer = DOUBLE_TAP_FRAMES
	return false


func _wall_logic(dir: Vector2i, floor_now: bool) -> void:
	wall_slide = false
	if floor_now or not state().has_ability("wall_kick"):
		return
	var side := _wall_side()
	if side != 0:
		wall_grace = Consts.COYOTE_FRAMES
		wall_side_last = side
		if dir.x == side and velocity.y > 0.0 and kick_frames == 0:
			wall_slide = true


func _try_jump(floor_now: bool, dir: Vector2i) -> bool:
	if jump_buffer <= 0:
		return false
	var gs := state()
	if floor_now or coyote > 0:
		jump_buffer = 0
		coyote = 0
		_launch(Motion.jump_v0(), false)
		AudioService.sfx("jump")
		return true
	if gs.has_ability("wall_kick") and wall_grace > 0 and wall_side_last != 0:
		jump_buffer = 0
		wall_grace = 0
		_launch(Motion.wall_kick_v0(), true)
		kick_frames = Consts.WALL_KICK_PUSH_FRAMES
		velocity.x = -wall_side_last * Consts.WALL_KICK_PUSH_SPEED
		facing = -wall_side_last
		wall_slide = false
		AudioService.sfx("wall_kick")
		return true
	if gs.has_ability("jetpack") and not air_jump_used:
		jump_buffer = 0
		air_jump_used = true
		_launch(Motion.double_jump_v0(), true)
		AudioService.sfx("double_jump")
		return true
	return false


## Sets the launch speed. fixed = no variable-height cut (double jump, wall kick).
func _launch(v0: float, fixed: bool) -> void:
	velocity.y = -v0
	jumping = true
	jump_frames = 0
	cut_applied = fixed


func _gravity(_floor_now: bool) -> void:
	velocity.y = Motion.fall_step(velocity.y)
	if wall_slide:
		velocity.y = minf(velocity.y, Consts.WALL_SLIDE_SPEED)
	jump_frames += 1
	if jumping and not cut_applied and velocity.y < 0.0 and not input.is_held("jump") and jump_frames >= Consts.JUMP_CUT_MIN_FRAMES:
		velocity.y *= Consts.JUMP_CUT
		cut_applied = true


func _slide() -> void:
	velocity.y = Motion.fall_step(velocity.y)
	if slide_frames > 0:
		slide_frames -= 1
		velocity.x = facing * (Consts.SLIDE_DISTANCE * (1.0 + float(state().derived["slide_pct"]) / 100.0) / Consts.SLIDE_FRAMES) * Consts.FPS
		return
	if _can_stand():
		mode = Mode.NORMAL
		velocity.x = 0.0
		_set_box(STAND)
		return
	var dir := input.direction()
	if dir.x != 0:
		facing = dir.x
	velocity.x = dir.x * Consts.RUN_SPEED * 0.4


func _dash() -> void:
	dash_frames -= 1
	velocity.x = -facing * (Consts.BACKDASH_DISTANCE * (1.0 + float(state().derived["slide_pct"]) / 100.0) / Consts.BACKDASH_FRAMES) * Consts.FPS
	velocity.y = Motion.fall_step(velocity.y)
	if dash_frames <= 0:
		mode = Mode.NORMAL
		velocity.x = 0.0


func _ball() -> void:
	var dir := input.direction()
	if morph_timer > 0:
		morph_timer -= 1
		velocity.x = 0.0
	else:
		if dir.x != 0:
			facing = dir.x
		velocity.x = dir.x * Consts.BALL_SPEED
		if (input.just_pressed("up") or input.just_pressed("jump")) and _can_stand():
			mode = Mode.NORMAL
			_set_box(STAND)
			jump_buffer = 0
			AudioService.sfx("spaceball_morph", 0.0, 0.8)
	velocity.y = Motion.fall_step(velocity.y)
	if state().is_dead():
		_die()


func _hurt() -> void:
	hurt_frames -= 1
	velocity.x = move_toward(velocity.x, 0.0, 6.0)
	velocity.y = Motion.fall_step(velocity.y)
	if hurt_frames <= 0:
		mode = Mode.NORMAL if not state().is_dead() else Mode.DEAD


func _dead() -> void:
	dead_frames += 1
	velocity.x = move_toward(velocity.x, 0.0, 6.0)
	velocity.y = Motion.fall_step(velocity.y)
	if dead_frames == 70:
		died.emit()


func _frozen() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 12.0)
	velocity.y = Motion.fall_step(velocity.y)


func _die() -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.DEAD
	dead_frames = 0
	attack.cancel()
	velocity = Vector2(-facing * 60.0, -160.0)
	_set_box(CROUCH)
	AudioService.sfx("death")
	AudioService.stop_music()


# --- geometry probes --------------------------------------------------------------------------------

func _wall_side() -> int:
	for side in [-1, 1]:
		if test_move(global_transform, Vector2(side, 0)):
			return side
	return 0


func _can_stand() -> bool:
	return not test_move(global_transform, Vector2(0, -(STAND.y - (BALL.y if mode == Mode.BALL else CROUCH.y)) - 1.0))


func _standing_on_platform() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Node and (collider as Node).is_in_group("platform"):
			return true
	return false


func _blocked_below_solid() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Node and not (collider as Node).is_in_group("platform") and get_slide_collision(i).get_normal().y < -0.5:
			return true
	return false


func _drop_through() -> void:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Node and (collider as Node).is_in_group("platform"):
			_platform_body = collider
			add_collision_exception_with(_platform_body)
			drop_frames = 9
			position.y += 1.0
			return


## Nudges Sleve around ceiling corners so a jump that clips a ledge by a few pixels still succeeds.
func _corner_correct() -> void:
	if velocity.y >= 0.0 or mode == Mode.BALL:
		return
	var step := Vector2(0, velocity.y * Consts.DT)
	if not test_move(global_transform, step):
		return
	for offset in range(1, CORNER + 1):
		for side in [-1, 1]:
			var shifted := global_transform.translated(Vector2(side * offset, 0))
			if not test_move(shifted, step) and not test_move(global_transform, Vector2(side * offset, 0)):
				global_position.x += side * offset
				return


func _after_move() -> void:
	var floor_now := is_on_floor()
	if floor_now:
		if not was_on_floor and last_fall_speed > 200.0:
			AudioService.sfx("land", -6.0)
		jumping = false
		last_fall_speed = 0.0
	else:
		last_fall_speed = maxf(last_fall_speed, velocity.y)
	was_on_floor = floor_now


# --- damage, knacks, interaction ---------------------------------------------------------------------

func _check_damage() -> void:
	if invuln > 0 or mode == Mode.DEAD:
		return
	for area in hurtbox.get_overlapping_areas():
		if area is HitArea and (area as HitArea).active:
			take_hit(area as HitArea)
			return


func take_hit(hit: HitArea) -> void:
	var from_x := hit.global_position.x
	if is_instance_valid(hit.source) and hit.source is Node2D:
		from_x = (hit.source as Node2D).global_position.x
	var amount := Combat.enemy_hit(state(), hit.level, hit.mult, hit.element)
	if invuln > 0 or mode == Mode.DEAD or god_mode:
		return
	hurt_by(amount, signf(global_position.x - from_x))
	var thorns := float(state().derived["thorns_pct"])
	if hit.kind == "contact" and thorns > 0.0 and is_instance_valid(hit.source) and hit.source.has_method("take_reflect"):
		hit.source.call("take_reflect", maxi(1, roundi(amount * thorns / 100.0)))


func hurt_by(amount: int, away: float) -> void:
	if invuln > 0 or mode == Mode.DEAD or god_mode:
		return
	var gs := state()
	gs.take_damage(float(amount))
	invuln = Consts.HURT_INVULN_FRAMES
	attack.cancel()
	damaged.emit(amount)
	Combat.freeze(4)
	AudioService.sfx("hurt")
	if Settings.damage_numbers:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -64), str(amount), UIKit.COLORS["bad"])
	if gs.is_dead():
		_die()
		return
	if bool(gs.mode()["knockback"]) and mode != Mode.SLIDE:
		mode = Mode.HURT
		hurt_frames = HURT_FRAMES
		velocity = Vector2(away * 120.0, -150.0)
		_set_box(STAND)


func _knack() -> void:
	var gs := state()
	var knacks: Array = gs.data["tallies"]["knacks"]
	if knacks.is_empty():
		AudioService.sfx("menu_deny", -6.0)
		return
	var perk_id: String = knacks[0]
	var def := Tallies.perk_def(perk_id)
	var cost := float(def.get("ep", 0.0))
	if gs.ep < cost:
		AudioService.sfx("menu_deny", -6.0)
		return
	gs.ep -= cost
	knack_used.emit(perk_id)


func _taunt() -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, -68), "SLEEEVE!", UIKit.COLORS["xp"], 1, 50)
	AudioService.sfx("hey_listen", -3.0, 0.8)
	if float(state().derived["battle_cry"]) > 0.0:
		battle_cry_frames = 180


func _interact() -> void:
	var best: Node = null
	var best_distance := 1.0e9
	for area in interact_area.get_overlapping_areas():
		var target: Variant = area.get_meta("interactable", null)
		if target is Node and (target as Node).has_method("interact"):
			var distance := absf((target as Node2D).global_position.x - global_position.x)
			if distance < best_distance:
				best_distance = distance
				best = target
	if best != null:
		interacted.emit(best)
		best.call("interact", self)


# --- animation ----------------------------------------------------------------------------------------

func _animate() -> void:
	sprite.set_facing(facing)
	sprite.speed_scale = 1.0
	var floor_now := is_on_floor()
	match mode:
		Mode.DEAD, Mode.HURT:
			sprite.play_key("sleve/hurt")
		Mode.SLIDE:
			sprite.play_key("sleve/slide")
		Mode.DASH:
			sprite.play_key("sleve/backdash")
		Mode.BALL:
			sprite.play_key("sleve/spaceball")
			if absf(velocity.x) < 1.0 or morph_timer > 0:
				sprite.pause()
			else:
				sprite.play()
		_:
			if attack.is_attacking():
				if sprite.key != "sleve/swing":
					sprite.play_key("sleve/swing", true)
					sprite.fit_to_frames(attack.total)
			elif wall_slide:
				sprite.play_key("sleve/wall_slide")
			elif not floor_now:
				sprite.play_key("sleve/jump")
				sprite.pause()
				sprite.frame = 0 if velocity.y < 0.0 else 1
			elif absf(velocity.x) > 10.0:
				sprite.play_key("sleve/run")
				sprite.speed_scale = clampf(absf(velocity.x) / Consts.RUN_SPEED, 0.5, 1.2)
			else:
				sprite.play_key("sleve/idle")
	if invuln > 0 and mode != Mode.DEAD:
		sprite.modulate.a = 0.45 if invuln % 6 < 3 else 1.0
	elif not attack.charging:
		sprite.modulate = Color.WHITE
