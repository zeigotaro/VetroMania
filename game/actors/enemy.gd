class_name Enemy
extends CharacterBody2D
## Enemies from data/enemies.json. Each behavior teaches one thing: the bat dives (jump and duck), the
## zombie lunges (backdash), the Hunch-Bot shoots from the ground (approach in arcs). Elites add an affix.
## Stats follow docs/design/player-and-combat.md#enemy-scaling.

signal died(enemy: Enemy)

const WHITE_FLASH := Color(2.6, 2.6, 2.6)
const AFFIX_TINTS := {"fast": Color(1.0, 0.95, 0.5), "shielded": Color(0.6, 0.8, 1.4), "extra_salty": Color(1.4, 0.8, 0.5), "vampiric": Color(1.4, 0.55, 0.65)}

var id := ""
var def: Dictionary = {}
var level := 1
var elite := false
var affix := ""
var hp := 1.0
var max_hp := 1.0
var shield := 0.0
var facing := 1
var sprite: AnimSprite
var hurt_area: HurtArea
var hit_area: HitArea
var home := Vector2.ZERO
var room_id := ""
var params: Dictionary = {}
var phase := "idle"
var frames_left := 0
var cooldown := 0
var stun := 0
var knock_x := 0.0
var flash := 0
var dead := false
var time := 0
var speed_mult := 1.0
var wander_timer := 0
var wander_dir := 1
var hop_timer := 40
var death_timer := 0
var salty_timer := 0
var bounds := Vector2(20, 20)
var player: Player


static func create(enemy_id: String, enemy_level: int, is_elite: bool, elite_affix: String, at: Vector2) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = enemy_id
	enemy.def = Db.enemy(enemy_id)
	enemy.level = enemy_level
	enemy.elite = is_elite
	enemy.affix = elite_affix
	enemy.home = at
	enemy.position = at
	return enemy


func _ready() -> void:
	setup_from_def()


func setup_from_def() -> void:
	params = def.get("params", {})
	collision_layer = 1 << 2
	collision_mask = 1
	add_to_group("enemy")
	var flying: bool = def.get("flying", false)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if flying else CharacterBody2D.MOTION_MODE_GROUNDED
	floor_snap_length = 4.0
	bounds = Vector2(float(def["body"][0]), float(def["body"][1]))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = bounds
	shape.shape = rect
	shape.position = Vector2(0, -bounds.y / 2.0)
	add_child(shape)
	sprite = AnimSprite.new(def.get("sprite_keys", [def["sprite"]]))
	sprite.position = Vector2(float(def["sprite_offset"][0]), float(def["sprite_offset"][1]))
	sprite.play_key(def["sprite"], true)
	add_child(sprite)
	hurt_area = HurtArea.new(bounds, Vector2(0, -bounds.y / 2.0))
	hurt_area.target = self
	add_child(hurt_area)
	hit_area = HitArea.new(bounds * 0.85, Vector2(0, -bounds.y / 2.0))
	hit_area.source = self
	hit_area.level = level
	hit_area.mult = float(def["contact_mult"])
	hit_area.element = String(def["element"])
	add_child(hit_area)
	_setup_stats()
	if elite:
		_apply_affix()
	facing = -1 if randf() < 0.5 else 1
	wander_dir = facing
	hop_timer = randi_range(20, 80)
	time = randi_range(0, 60)


func _setup_stats() -> void:
	var gs := GameState.current
	var mult := float(gs.mode()["enemy_hp"]) if gs != null else 1.0
	max_hp = float(Damage.enemy_hp(def["tier"], level, elite)) * mult
	hp = max_hp


func _apply_affix() -> void:
	sprite.modulate = AFFIX_TINTS.get(affix, Color.WHITE)
	sprite.scale = Vector2.ONE * 1.0
	match affix:
		"fast":
			speed_mult = float(Db.elite()["fast_mult"])
		"shielded":
			shield = max_hp * float(Db.elite()["shield_hp_frac"])


func defense() -> float:
	return Damage.enemy_def(level)


func hit_info() -> Dictionary:
	return {"def": defense(), "weak": def.get("weak", ""), "resist": def.get("resist", "")}


func is_boss() -> bool:
	return false


func _target() -> Player:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.mode == Player.Mode.DEAD:
		return null
	var gs := GameState.current
	if gs != null and "cardboard" in gs.derived["powers"] and def.get("tier", "") == "fodder" and player.still_frames >= Powers.CARDBOARD_STILL_FRAMES:
		return null
	return player


func _t(frames: int) -> int:
	return maxi(1, roundi(frames / speed_mult))


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0:
		return
	if dead:
		death_timer -= 1
		sprite.modulate.a = clampf(death_timer / 12.0, 0.0, 1.0)
		if death_timer <= 0:
			queue_free()
		return
	time += 1
	if flash > 0:
		flash -= 1
		sprite.modulate = WHITE_FLASH if flash > 0 else AFFIX_TINTS.get(affix, Color.WHITE)
	if affix == "extra_salty":
		salty_timer -= 1
		if salty_timer <= 0:
			salty_timer = 240
			FloatText.spawn(get_parent(), global_position + Vector2(0, -bounds.y - 8), "SALTY", Color("ffb04a"), 1, 50)
	if stun > 0:
		stun -= 1
		velocity.x = knock_x
		knock_x = move_toward(knock_x, 0.0, 10.0)
		if not (def.get("flying", false)):
			velocity.y = Motion.fall_step(velocity.y)
		else:
			velocity.y = 0.0
		move_and_slide()
		_animate()
		return
	_behave()
	move_and_slide()
	_after_move()
	_animate()


func _behave() -> void:
	match String(def["behavior"]):
		"sine_dive":
			_bat()
		"shamble_lunge":
			_zombie()
		"hop_arc":
			_hunch()


func _after_move() -> void:
	pass


func _animate() -> void:
	sprite.set_facing(facing)
	if phase in ["windup", "aim"] and sprite.modulate.r < 2.0:
		sprite.position.x = float(def["sprite_offset"][0]) + (1.0 if time % 4 < 2 else -1.0)
	else:
		sprite.position.x = float(def["sprite_offset"][0])


# --- behaviors -----------------------------------------------------------------------------------------

func _bat() -> void:
	var target := _target()
	var to_player := (target.global_position + Vector2(0, -24) - global_position) if target != null else Vector2.ZERO
	match phase:
		"idle":
			var goal_x := home.x
			if target != null and absf(to_player.x) < float(params["sight"]):
				goal_x = target.global_position.x
			var dx := goal_x - global_position.x
			var vx := clampf(dx, -1.0, 1.0) * float(params["speed"]) * speed_mult if absf(dx) > 6.0 else 0.0
			var wave_y := home.y + float(params["amplitude"]) * sin(TAU * time / float(params["period"]))
			velocity = Vector2(vx, (wave_y - global_position.y) * 6.0)
			if vx != 0.0:
				facing = 1 if vx > 0.0 else -1
			if cooldown > 0:
				cooldown -= 1
			elif target != null and absf(to_player.x) <= float(params["dive_range_x"]) and to_player.y >= float(params["dive_min_drop"]):
				phase = "windup"
				frames_left = _t(int(params["windup"]))
				AudioService.sfx(String(def["voice"]), -6.0)
		"windup":
			velocity = Vector2.ZERO
			frames_left -= 1
			if frames_left <= 0:
				var aim := to_player.normalized() if target != null else Vector2.DOWN
				velocity = aim * float(params["dive_speed"]) * speed_mult
				phase = "dive"
				frames_left = _t(int(params["dive_frames"]))
				if velocity.x != 0.0:
					facing = 1 if velocity.x > 0.0 else -1
		"dive":
			frames_left -= 1
			if frames_left <= 0 or get_slide_collision_count() > 0:
				phase = "return"
		"return":
			var dy := home.y - global_position.y
			velocity = Vector2((home.x - global_position.x) * 2.0, signf(dy) * float(params["return_speed"]) * speed_mult)
			if absf(dy) < 6.0:
				phase = "idle"
				cooldown = _t(int(params["cooldown"]))


func _ledge_ahead() -> bool:
	var probe := global_transform.translated(Vector2(facing * (bounds.x / 2.0 + 3.0), 0))
	return not test_move(probe, Vector2(0, 10))


func _wall_ahead() -> bool:
	return test_move(global_transform, Vector2(facing * 3.0, 0))


func _zombie() -> void:
	var target := _target()
	velocity.y = Motion.fall_step(velocity.y)
	match phase:
		"idle":
			var dx := (target.global_position.x - global_position.x) if target != null else 0.0
			var dy := (target.global_position.y - global_position.y) if target != null else 0.0
			var speed := float(params["speed"]) * speed_mult
			if target != null and absf(dx) < float(params["sight"]) and absf(dy) < 80.0:
				facing = 1 if dx > 0.0 else -1
				velocity.x = 0.0 if (_ledge_ahead() or _wall_ahead()) else facing * speed
			else:
				wander_timer -= 1
				if wander_timer <= 0:
					wander_timer = randi_range(70, 150)
					wander_dir = -wander_dir if randf() < 0.5 else wander_dir
				if absf(global_position.x - home.x) > 48.0:
					wander_dir = 1 if home.x > global_position.x else -1
				facing = wander_dir
				velocity.x = 0.0 if (_ledge_ahead() or _wall_ahead()) else facing * speed * 0.5
			if cooldown > 0:
				cooldown -= 1
			elif target != null and absf(dx) <= float(params["lunge_range"]) and absf(dy) < 40.0:
				phase = "windup"
				frames_left = _t(int(params["windup"]))
				velocity.x = 0.0
				AudioService.sfx(String(def["voice"]), -3.0)
				FloatText.spawn(get_parent(), global_position + Vector2(0, -bounds.y - 10), String(def["bark"]), UIKit.COLORS["good"], 1, 44)
		"windup":
			velocity.x = 0.0
			frames_left -= 1
			if frames_left <= 0:
				phase = "lunge"
				frames_left = _t(int(params["lunge_frames"]))
				hit_area.mult = float(def["contact_mult"]) * 1.3
		"lunge":
			velocity.x = facing * float(params["lunge_speed"]) * speed_mult
			frames_left -= 1
			if frames_left <= 0 or _wall_ahead():
				phase = "recover"
				frames_left = _t(int(params["recover"]))
				velocity.x = 0.0
				hit_area.mult = float(def["contact_mult"])
		"recover":
			velocity.x = 0.0
			frames_left -= 1
			if frames_left <= 0:
				phase = "idle"
				cooldown = _t(int(params["cooldown"]))


func _hunch() -> void:
	var target := _target()
	velocity.y = Motion.fall_step(velocity.y)
	var grounded := is_on_floor()
	var dx := (target.global_position.x - global_position.x) if target != null else 0.0
	var dist := absf(dx) if target != null else 9999.0
	match phase:
		"idle":
			if grounded:
				velocity.x = 0.0
				hop_timer -= 1
				if target != null and dist < float(params["sight"]):
					facing = 1 if dx > 0.0 else -1
				if cooldown > 0:
					cooldown -= 1
				elif target != null and dist < float(params["shoot_range"]) and hop_timer > 24:
					phase = "aim"
					frames_left = _t(int(params["shoot_windup"]))
				if hop_timer <= 0 and phase == "idle":
					hop_timer = _t(int(params["hop_interval"]))
					var toward := facing if (target != null and dist < float(params["sight"])) else wander_dir
					if _wall_ahead():
						toward = -toward
						wander_dir = toward
					facing = toward
					velocity = Vector2(toward * float(params["hop_vx"]) * speed_mult, -float(params["hop_vy"]))
					AudioService.sfx(String(def["voice"]), -8.0)
		"aim":
			velocity.x = 0.0
			frames_left -= 1
			sprite.modulate = Color(0.7, 1.3, 1.5) if time % 6 < 3 else Color.WHITE
			if frames_left <= 0:
				sprite.modulate = AFFIX_TINTS.get(affix, Color.WHITE)
				var aim := (target.global_position + Vector2(0, -24) - (global_position + Vector2(facing * 12, -bounds.y))).normalized() if target != null else Vector2(facing, 0)
				EnemyBolt.spawn(get_parent(), global_position + Vector2(facing * 12, -bounds.y), aim, float(params["bolt_speed"]) * speed_mult, level, float(params["bolt_mult"]), String(params["bolt_element"]), self)
				AudioService.sfx("mitt_shot", -8.0, 0.7)
				cooldown = _t(int(params["shoot_cooldown"]))
				phase = "idle"


# --- being hit -----------------------------------------------------------------------------------------

func receive_hit(result: Dictionary, hit: Dictionary) -> void:
	if dead:
		return
	var amount := float(result["amount"])
	var shown := int(result["amount"])
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	hp -= amount
	flash = 4
	sprite.modulate = WHITE_FLASH
	var color := Color.WHITE
	var text := str(shown)
	if result["crit"]:
		color = UIKit.COLORS["xp"]
		text = "CRIT! " + text
	elif result["weak"]:
		color = Color("4fe0ff")
	elif result["resist"]:
		color = Color("a0a0b0")
	FloatText.spawn(get_parent(), global_position + Vector2(0, -bounds.y - 4), text, color)
	if not is_boss():
		var heavy: bool = hit.get("heavy", false)
		knock_x = float(hit.get("direction", 1)) * (260.0 if heavy else 90.0)
		stun = 16 if heavy else 8
		if phase in ["windup", "aim", "dive"]:
			phase = "idle" if def["behavior"] != "sine_dive" else "return"
			cooldown = _t(30)
	_on_damaged(result, hit)
	if hp <= 0.0:
		_die()


func _on_damaged(_result: Dictionary, _hit: Dictionary) -> void:
	pass


func take_reflect(amount: int) -> void:
	if dead:
		return
	hp -= amount
	FloatText.spawn(get_parent(), global_position + Vector2(0, -bounds.y - 4), str(amount), Color("a0ffa0"))
	if hp <= 0.0:
		_die()


func on_dealt_damage(amount: int) -> void:
	if affix == "vampiric" and not dead:
		hp = minf(max_hp, hp + amount * float(Db.elite()["vampiric_heal_frac"]))


func _die() -> void:
	if dead:
		return
	dead = true
	death_timer = 12
	hit_area.active = false
	hurt_area.monitorable = false
	AudioService.sfx("enemy_die")
	died.emit(self)
