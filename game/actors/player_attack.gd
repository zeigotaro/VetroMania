class_name PlayerAttack
extends RefCounted
## Sleve's weapons: the main-weapon swing and chain, and the sub-weapon (Mitt Cannon, Spread Gun, Throwable).
## Melee timing follows the weapon class: startup ~22% of the swing, active until ~50%, then recovery.

const NO_WEAPON := {"frames": 16, "reach": 24, "chain": 1, "crit_bonus": 0, "family": "fist"}
const CHAIN_WINDOW := 18
const BOX_HEIGHT := 40.0

var player: Player
var box: Area2D
var box_shape: CollisionShape2D

var frame := -1
var total := 0
var chain := 0
var chain_timer := 0
var weapon: Dictionary = NO_WEAPON
var hit_ids := {}

var charge := 0
var charging := false
var sub_cd := 0
var queued_shot := 0
var thrown: Node = null


func _init(owner_player: Player) -> void:
	player = owner_player
	box = Area2D.new()
	box.collision_layer = 1 << 3
	box.collision_mask = HurtArea.LAYER_ENEMY | HurtArea.LAYER_BREAKABLE
	box.monitorable = false
	box.monitoring = false
	box_shape = CollisionShape2D.new()
	box_shape.shape = RectangleShape2D.new()
	box.add_child(box_shape)
	player.add_child(box)


func is_attacking() -> bool:
	return frame >= 0


func roots_on_ground() -> bool:
	return frame >= 0


func cancel() -> void:
	frame = -1
	box.monitoring = false
	charging = false
	charge = 0
	player.sprite.modulate = Color.WHITE


func _state() -> GameState:
	return GameState.current


func _main_weapon() -> Dictionary:
	var item: Dictionary = _state().data["equipped"].get("weapon", {})
	if item.is_empty():
		return NO_WEAPON
	var data: Dictionary = Items.family_data(item).duplicate()
	data["family"] = item["family"]
	return data


func update() -> void:
	_melee()
	_sub()


# --- main weapon -----------------------------------------------------------------------------------

func _melee() -> void:
	if frame >= 0:
		frame += 1
		var start_frame := roundi(total * 0.22)
		var end_frame := roundi(total * 0.5)
		var active := frame >= start_frame and frame <= end_frame
		box.monitoring = active
		if active:
			_position_box()
			_apply_hits()
		if frame >= total:
			frame = -1
			box.monitoring = false
			chain_timer = CHAIN_WINDOW
	elif chain_timer > 0:
		chain_timer -= 1
		if chain_timer == 0:
			chain = 0
	if player.attack_buffer > 0 and frame < 0 and player.can_attack():
		player.attack_buffer = 0
		_start()


func _start() -> void:
	weapon = _main_weapon()
	var chain_length := maxi(1, int(weapon["chain"]))
	if chain_timer > 0:
		chain = (chain + 1) % chain_length
	else:
		chain = 0
	var speed := 1.0 + float(_state().derived["attack_speed"]) / 100.0
	total = maxi(6, roundi(float(weapon["frames"]) / speed))
	frame = 0
	hit_ids = {}
	charging = false
	charge = 0
	player.sprite.play_key("sleve/swing", true)
	player.sprite.fit_to_frames(total)
	AudioService.sfx("swing_%d" % (mini(chain, 2) + 1))


func _position_box() -> void:
	var reach := float(weapon["reach"])
	var height := BOX_HEIGHT
	var center_y := -32.0
	match String(weapon["family"]):
		"whip":
			height = 18.0
		"mallet":
			height = 58.0
			center_y = -38.0
	(box_shape.shape as RectangleShape2D).size = Vector2(reach, height)
	box_shape.position = Vector2(player.facing * (9.0 + reach / 2.0), center_y)


func _apply_hits() -> void:
	var state := _state()
	for area in box.get_overlapping_areas():
		if not (area is HurtArea) or (area as HurtArea).target == null:
			continue
		var target: Node = (area as HurtArea).target
		var id := target.get_instance_id()
		if hit_ids.has(id):
			continue
		hit_ids[id] = true
		var family := String(weapon["family"])
		var chain_length := int(weapon["chain"])
		var home_run := family == "bat" and chain_length > 1 and chain == chain_length - 1
		var mult := 1.4 if home_run else 1.0
		var target_pos: Vector2 = (target as Node2D).global_position
		if family == "whip" and absf(target_pos.x - player.global_position.x) > float(weapon["reach"]) * 0.7:
			mult *= 1.25
		var info: Dictionary = target.hit_info()
		var options := {
			"kind": "melee", "crit_bonus": float(weapon["crit_bonus"]),
			"extra_mult": player.battle_cry_mult(),
			"force_crit": home_run and state.derived["set_flags"].has("home_runs_crit"),
		}
		var result := Combat.player_hit(state, float(info.get("def", 0.0)), mult, info, options)
		var heavy := home_run or family == "mallet"
		var hit := {
			"kind": "melee", "family": family, "heavy": heavy, "direction": player.facing, "source": player,
			"chain": chain, "position": target_pos, "home_run": home_run,
		}
		target.receive_hit(result, hit)
		state.restore_ep(Consts.EP_PER_MELEE_HIT)
		if float(state.derived["vamp_pct"]) > 0.0:
			state.heal(float(result["amount"]) * float(state.derived["vamp_pct"]) / 100.0)
		Combat.freeze(Consts.HITSTOP_HEAVY if (result["crit"] or heavy) else Consts.HITSTOP_NORMAL)
		AudioService.sfx("home_run" if home_run else ("crit" if result["crit"] else "hit_%d" % (mini(chain, 2) + 1)))
		player.spawn_spark(target_pos + Vector2(0, -20))
		if result["crit"] and "bobson" in state.derived["powers"]:
			_ricochet(target)


func _ricochet(from_target: Node) -> void:
	var shot := Projectile.spawn(player.get_parent(), (from_target as Node2D).global_position + Vector2(0, -24), Vector2.UP, 210.0, "sleve/spaceball", {
		"mult": Powers.BOBSON_DAMAGE, "kind": "melee", "family": "bobson", "homing": true, "life": 100, "owner_player": player, "sprite_scale": 0.7, "spin": 0.4,
	})
	shot._hits[from_target.get_instance_id()] = true


# --- sub-weapon --------------------------------------------------------------------------------------

func _sub() -> void:
	var state := _state()
	if sub_cd > 0:
		sub_cd -= 1
	if queued_shot > 0:
		queued_shot -= 1
		if queued_shot == 0:
			_fire_mitt(true, false)
	var item: Dictionary = state.data["equipped"].get("sub", {})
	if item.is_empty() or not player.can_use_sub():
		charging = false
		charge = 0
		return
	var data: Dictionary = Items.family_data(item)
	match String(item["family"]):
		"mitt_cannon":
			_mitt(state, data)
		"spread_gun":
			if player.input.just_pressed("sub") and sub_cd == 0 and state.ep >= float(data["ep"]):
				state.ep -= float(data["ep"])
				sub_cd = 16
				_fire_spread(int(data["pellets"]))
		"throwable":
			if player.input.just_pressed("sub") and not is_instance_valid(thrown) and state.ep >= float(data["ep"]):
				state.ep -= float(data["ep"])
				_throw()


func _muzzle() -> Vector2:
	return player.global_position + Vector2(player.facing * 20.0, -34.0)


func _mitt(state: GameState, data: Dictionary) -> void:
	var held := player.input.is_held("sub")
	if held and (charging or player.input.just_pressed("sub")):
		charging = true
		charge += 1
		if charge == Consts.CHARGE_FRAMES:
			AudioService.sfx("mitt_charge_loop")
		var pulse := 0.5 + 0.5 * sin(charge * 0.5)
		player.sprite.modulate = Color(1, 1, 1).lerp(Color(0.6, 1.0, 1.0), pulse) if charge >= Consts.CHARGE_FRAMES else Color.WHITE
	elif charging:
		charging = false
		player.sprite.modulate = Color.WHITE
		if sub_cd == 0:
			var cost := float(data["charge_ep"])
			var glove: bool = "power_glove" in state.derived["powers"]
			if charge >= Consts.CHARGE_FRAMES and state.ep >= cost:
				state.ep -= cost
				_fire_mitt(true, true)
				if glove:
					state.ep = maxf(0.0, state.ep - Powers.POWER_GLOVE_EP)
					queued_shot = 8
			else:
				_fire_mitt(false, true)
		charge = 0


func _fire_mitt(is_charged: bool, play_sound: bool) -> void:
	sub_cd = 12
	var key := "props/mitt_shot_charged" if is_charged else "props/mitt_shot"
	Projectile.spawn(player.get_parent(), _muzzle(), Vector2(player.facing, 0), 240.0 if not is_charged else 210.0, key, {
		"mult": float(Db.base_items()["weapons"]["mitt_cannon"]["charge_mult"]) if is_charged else 1.0,
		"kind": "sub", "family": "mitt_cannon", "charged": is_charged, "pierce": is_charged, "life": 150, "owner_player": player,
	})
	if play_sound:
		AudioService.sfx("mitt_charged_shot" if is_charged else "mitt_shot")


func _fire_spread(pellets: int) -> void:
	for i in pellets:
		var angle := deg_to_rad((i - (pellets - 1) / 2.0) * 14.0)
		var direction := Vector2(player.facing, 0).rotated(angle * player.facing)
		Projectile.spawn(player.get_parent(), _muzzle(), direction, 230.0, "props/enemy_bolt", {
			"mult": 1.0, "kind": "sub", "family": "spread_gun", "life": 24, "owner_player": player, "sprite_scale": 0.8,
		})
	AudioService.sfx("mitt_shot", -3.0, 1.3)


func _throw() -> void:
	thrown = Projectile.spawn(player.get_parent(), _muzzle(), Vector2(player.facing, 0), 200.0, "sleve/spaceball", {
		"mult": 1.0, "kind": "sub", "family": "throwable", "life": 200, "boomerang_after": 26, "owner_player": player, "sprite_scale": 0.6, "spin": 0.5,
	})
	AudioService.sfx("swing_2", -4.0, 1.4)
