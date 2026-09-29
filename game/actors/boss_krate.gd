class_name BossKrate
extends Enemy
## KRATE: a cargo crate the size of a room, with teeth. Slam (jump, land, shockwaves), Chomp (lunge), and in phase 2
## Cargo Drop. Every attack telegraphs for at least 12 frames. At 0 HP the fight freezes and asks for the
## Autograph Seal; a failed signing heals him to 20%. See docs/design/bestiary.md#bosses.

signal finish_requested(boss: BossKrate)

const ROAR_FRAMES := 90
const SHIFT_FRAMES := 70

var boss_id := "krate"
var boss_def: Dictionary = {}
var attack := ""
var attack_frames := 0
var idle_frames := 90
var phase2 := false
var intro_frames := ROAR_FRAMES
var finishing := false
var last_attacks: Array[String] = []
var slam_dir := 1.0
var chomp_start_x := 0.0
var jump_air_frames := 0
var invulnerable := true
var arena_left := 0.0
var arena_right := 0.0
var floor_y := 0.0
var starting_hp_frac := 1.0
var attack_serial := 0
var markers: Array[ColorRect] = []


static func make(at: Vector2, hp_frac: float = 1.0) -> BossKrate:
	var boss := BossKrate.new()
	boss.id = "krate"
	boss.boss_def = Db.boss("krate")
	boss.def = {
		"name": boss.boss_def["name"], "tier": "boss", "sprite": boss.boss_def["states"]["idle"], "body": boss.boss_def["body"],
		"sprite_keys": boss.boss_def["states"].values(),
		"sprite_offset": [0, 0], "behavior": "boss", "flying": false, "contact_mult": float(boss.boss_def["params"]["contact_mult"]),
		"element": "", "weak": boss.boss_def["weak"], "resist": boss.boss_def["resist"], "perk": "", "voice": "boss_roar",
	}
	boss.level = int(boss.boss_def["level"])
	boss.home = at
	boss.position = at
	boss.starting_hp_frac = hp_frac
	return boss


func is_boss() -> bool:
	return true


func _setup_stats() -> void:
	var gs := GameState.current
	var mult := float(gs.mode()["enemy_hp"]) if gs != null else 1.0
	max_hp = float(Damage.boss_hp(level)) * mult
	hp = max_hp * starting_hp_frac
	floor_y = global_position.y
	phase2 = starting_hp_frac <= float(boss_def["phase2_at"])


func _sprite_for(state: String) -> void:
	sprite.play_key(boss_def["states"][state], true)


func defense() -> float:
	return Damage.enemy_def(level)


func _behave() -> void:
	velocity.y = Motion.fall_step(velocity.y)
	if finishing:
		velocity.x = 0.0
		return
	if intro_frames > 0:
		intro_frames -= 1
		invulnerable = true
		hit_area.active = false
		velocity.x = 0.0
		if intro_frames == ROAR_FRAMES - 2:
			AudioService.sfx("boss_roar")
			AudioService.music("boss_krate")
		if intro_frames > 20:
			_sprite_for("windup")
			sprite.pause()
			sprite.frame = 1 if intro_frames % 20 < 10 else 0
		else:
			_sprite_for("idle")
		if intro_frames == 0:
			invulnerable = false
			hit_area.active = true
		return
	match attack:
		"":
			_idle()
		"slam":
			_slam()
		"chomp":
			_chomp()
		"cargo_drop":
			_cargo_drop()
		"shift":
			_shift()


func _speed() -> float:
	return float(boss_def["params"]["phase2_speed"]) if phase2 else 1.0


func _idle() -> void:
	velocity.x = 0.0
	_sprite_for("idle")
	idle_frames -= 1
	var target := _target()
	if target != null:
		facing = 1 if target.global_position.x > global_position.x else -1
	if idle_frames <= 0:
		_pick_attack(target)


func _pick_attack(target: Player) -> void:
	var options: Array[String] = ["slam", "chomp"]
	if phase2:
		options.append("cargo_drop")
	var distance := absf(target.global_position.x - global_position.x) if target != null else 100.0
	var weights := {}
	for name in options:
		var w := 1.0
		if name == "chomp" and distance < 150.0:
			w = 2.0
		if name == "slam" and distance > 150.0:
			w = 2.0
		if name == "cargo_drop":
			w = 1.2
		if last_attacks.size() >= 2 and last_attacks[-1] == name and last_attacks[-2] == name:
			w = 0.0
		weights[name] = w
	var pick := Loot.pick_weighted(GameState.current.rng, weights)
	last_attacks.append(pick)
	if last_attacks.size() > 3:
		last_attacks.pop_front()
	_begin(pick)


func _begin(name: String) -> void:
	attack = name
	attack_serial += 1
	var params: Dictionary = boss_def["params"][name]
	attack_frames = maxi(12, roundi(float(params["windup"]) / _speed()))
	phase = "windup"
	_sprite_for("windup")
	AudioService.sfx("boss_telegraph")
	if name == "cargo_drop":
		_place_markers()


func _end_attack() -> void:
	attack = ""
	phase = "idle"
	var params: Dictionary = boss_def["params"]
	idle_frames = roundi(randf_range(float(params["idle_min"]), float(params["idle_max"])) / _speed())
	hit_area.mult = float(def["contact_mult"])
	hit_area.resize(bounds * 0.85, Vector2(0, -bounds.y / 2.0))
	_sprite_for("idle")


func _slam() -> void:
	var params: Dictionary = boss_def["params"]["slam"]
	var target := _target()
	match phase:
		"windup":
			velocity.x = 0.0
			sprite.position.x = (1.0 if time % 4 < 2 else -1.0)
			attack_frames -= 1
			if attack_frames <= 0:
				sprite.position.x = 0.0
				var v0 := Motion.velocity_for_height(float(params["hop_height"]))
				velocity.y = -v0
				jump_air_frames = Motion.airtime_frames(v0)
				var dx := (target.global_position.x - global_position.x) if target != null else 0.0
				velocity.x = clampf(dx / (jump_air_frames / float(Consts.FPS)), -float(params["travel_speed"]), float(params["travel_speed"]))
				phase = "hop"
				attack_frames = 6
				hit_area.mult = float(def["contact_mult"]) * 1.2
		"hop":
			attack_frames -= 1
			if is_on_floor() and attack_frames <= 0:
				_land()
				phase = "recover"
				attack_frames = maxi(1, roundi(float(params["recover"]) / _speed()))
		"recover":
			velocity.x = 0.0
			_sprite_for("slam")
			attack_frames -= 1
			if attack_frames <= 0:
				_end_attack()


func _land() -> void:
	var params: Dictionary = boss_def["params"]["slam"]
	velocity.x = 0.0
	_sprite_for("slam")
	AudioService.sfx("boss_slam")
	Combat.freeze(2)
	var cam := get_viewport().get_camera_2d()
	if cam is GameCamera:
		(cam as GameCamera).shake(2.0, 12)
	hit_area.mult = float(def["contact_mult"])
	for side in [-1, 1]:
		Hazard.spawn(get_parent(), global_position + Vector2(side * (bounds.x / 2.0), 0), Vector2(16, 14), Vector2(side * float(params["wave_speed"]) * _speed(), 0), level, float(params["wave_mult"]), int(params["wave_frames"]), self, {"kind": "wave", "art": "wave"})


func _chomp() -> void:
	var params: Dictionary = boss_def["params"]["chomp"]
	match phase:
		"windup":
			velocity.x = 0.0
			sprite.position.x = (1.0 if time % 4 < 2 else -1.0)
			attack_frames -= 1
			if attack_frames <= 0:
				sprite.position.x = 0.0
				phase = "lunge"
				attack_frames = maxi(4, roundi(float(params["lunge_frames"]) / _speed()))
				chomp_start_x = global_position.x
				_sprite_for("chomp")
				AudioService.sfx("boss_hit", 0.0, 0.8)
				hit_area.mult = float(params["mult"])
				hit_area.resize(Vector2(bounds.x + 30.0, bounds.y * 0.85), Vector2(facing * 15.0, -bounds.y / 2.0))
		"lunge":
			var total := maxi(4, roundi(float(params["lunge_frames"]) / _speed()))
			velocity.x = facing * float(params["lunge_dist"]) / (total / float(Consts.FPS))
			attack_frames -= 1
			if attack_frames <= 0 or test_move(global_transform, Vector2(facing * 3.0, 0)):
				velocity.x = 0.0
				phase = "recover"
				attack_frames = maxi(1, roundi(float(params["recover"]) / _speed()))
				hit_area.mult = float(def["contact_mult"])
				hit_area.resize(bounds * 0.85, Vector2(0, -bounds.y / 2.0))
		"recover":
			velocity.x = 0.0
			attack_frames -= 1
			if attack_frames <= 0:
				_end_attack()


func _place_markers() -> void:
	_clear_markers()
	var params: Dictionary = boss_def["params"]["cargo_drop"]
	var target := _target()
	var center := target.global_position.x if target != null else global_position.x
	var count := int(params["crates"])
	for i in count:
		var x := clampf(center + (i - (count - 1) / 2.0) * 56.0, arena_left + 24.0, arena_right - 24.0)
		var marker := ColorRect.new()
		marker.size = Vector2(20, 3)
		marker.color = Color(1.0, 0.3, 0.3, 0.85)
		marker.position = Vector2(x - 10.0, floor_y - 3.0)
		marker.z_index = 5
		get_parent().add_child(marker)
		markers.append(marker)


func _clear_markers() -> void:
	for marker in markers:
		if is_instance_valid(marker):
			marker.queue_free()
	markers.clear()


func _cargo_drop() -> void:
	var params: Dictionary = boss_def["params"]["cargo_drop"]
	match phase:
		"windup":
			velocity.x = 0.0
			attack_frames -= 1
			for marker in markers:
				if is_instance_valid(marker):
					marker.visible = attack_frames % 6 < 4
			if attack_frames <= 0:
				for marker in markers:
					if is_instance_valid(marker):
						var x := marker.position.x + 10.0
						Hazard.spawn(get_parent(), Vector2(x, floor_y - 250.0), Vector2(14, 14), Vector2(0, float(params["fall_speed"])), level, float(params["mult"]), 90, self, {"kind": "crate", "art": "crate", "falling": true, "break_on_floor": true})
				_clear_markers()
				AudioService.sfx("boss_hit", -3.0)
				phase = "recover"
				attack_frames = maxi(1, roundi(float(params["recover"]) / _speed()))
		"recover":
			velocity.x = 0.0
			attack_frames -= 1
			if attack_frames <= 0:
				_end_attack()


func _shift() -> void:
	velocity.x = 0.0
	attack_frames -= 1
	invulnerable = true
	sprite.modulate = Color(2.2, 1.4, 1.4) if attack_frames % 8 < 4 else Color.WHITE
	_sprite_for("windup")
	if attack_frames <= 0:
		invulnerable = false
		sprite.modulate = Color.WHITE
		_end_attack()


func _on_damaged(_result: Dictionary, _hit: Dictionary) -> void:
	if not phase2 and hp > 0.0 and hp / max_hp <= float(boss_def["phase2_at"]):
		phase2 = true
		_clear_markers()
		attack = "shift"
		attack_frames = SHIFT_FRAMES
		invulnerable = true
		AudioService.sfx("boss_roar", 0.0, 0.85)
		AudioService.music_pitch(1.06)
		hit_area.mult = float(def["contact_mult"])
		var cam := get_viewport().get_camera_2d()
		if cam is GameCamera:
			(cam as GameCamera).shake(2.5, 30)


func receive_hit(result: Dictionary, hit: Dictionary) -> void:
	if dead or invulnerable or finishing:
		if not dead and (invulnerable or finishing):
			AudioService.sfx("door_locked", -8.0, 1.6)
		return
	super.receive_hit(result, hit)


## At 0 HP the fight freezes for the Autograph Seal instead of ending.
func _die() -> void:
	if dead or finishing:
		return
	hp = 1.0
	finishing = true
	_clear_markers()
	AudioService.sfx("boss_hit")
	finish_requested.emit(self)


func resolve_finish(success: bool) -> void:
	finishing = false
	if success:
		hp = 0.0
		dead = true
		death_timer = 60
		hit_area.active = false
		hurt_area.monitorable = false
		AudioService.sfx("boss_die")
		died.emit(self)
	else:
		hp = max_hp * float(boss_def["fail_recover"])
		AudioService.sfx("seal_fail")
		FloatText.spawn(get_parent(), global_position + Vector2(0, -bounds.y - 10), "HE RECOVERS!", UIKit.COLORS["bad"], 1, 60)


func _physics_process(delta: float) -> void:
	if dead:
		death_timer -= 1
		sprite.modulate = Color(2.0, 2.0, 2.0, clampf(death_timer / 30.0, 0.0, 1.0)) if death_timer % 6 < 3 else Color(1, 1, 1, clampf(death_timer / 30.0, 0.0, 1.0))
		if death_timer <= 0:
			queue_free()
		return
	super._physics_process(delta)
