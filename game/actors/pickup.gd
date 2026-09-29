class_name Pickup
extends CharacterBody2D
## Loot on the ground: Vetro-Bucks, gem packs, consumables and gear. Bucks and gems fly to Sleve within
## 48 px; gear and consumables are picked up by walking over them. Gear shows a rarity-coloured loot beam.

const MAGNET_RADIUS := 48.0
const MAGNET_SPEED := 260.0
const LIFETIME_FRAMES := 60 * 60 * 5

var drop: Dictionary = {}
var age := 0
var collected := false
var player: Player
var icon: Sprite2D
var settled := false


static func spawn(parent: Node, at: Vector2, loot: Dictionary, rng: RandomNumberGenerator) -> Pickup:
	var pickup := Pickup.new()
	pickup.drop = loot
	pickup.position = at
	pickup.velocity = Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-230.0, -150.0))
	parent.add_child(pickup)
	return pickup


func _ready() -> void:
	collision_layer = 1 << 5
	collision_mask = 1
	add_to_group("pickup")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8, 8)
	shape.shape = box
	shape.position = Vector2(0, -4)
	add_child(shape)
	z_index = 10
	var gear: bool = drop["type"] == "gear"
	if drop["type"] == "bucks":
		var glint := AnimSprite.new(["props/pickup_glint"])
		glint.position = Vector2.ZERO
		glint.scale = Vector2(1, 1)
		glint.play_key("props/pickup_glint", true)
		glint.sprite_frames.set_animation_loop(SpriteLib.anim_name("props/pickup_glint"), true)
		glint.offset = SpriteLib.offset_for("props/pickup_glint", false) + Vector2(0, -4)
		add_child(glint)
		icon = null
	else:
		icon = Sprite2D.new()
		icon.texture = Icons.drop_texture(drop)
		icon.position = Vector2(0, -14)
		if drop["type"] == "gem":
			icon.scale = Vector2(0.5, 0.5)
			icon.position = Vector2(0, -8)
		add_child(icon)
	if gear:
		var rarity: String = drop["item"]["rarity"]
		var frame := Sprite2D.new()
		frame.texture = Icons.rarity_frame(rarity)
		frame.position = Vector2(0, -14)
		add_child(frame)
		add_child(_beam(Consts.RARITY_COLORS[rarity], 90.0 if rarity in ["legendary", "set"] else 60.0))
		if rarity == "legendary":
			AudioService.sfx("pickup_item_rare", -2.0, 0.85)
		elif rarity == "rare":
			AudioService.sfx("pickup_item_rare", -6.0)
		elif rarity == "magic":
			AudioService.sfx("pickup_item_magic", -6.0)


func _beam(color: Color, height: float) -> Polygon2D:
	var beam := Polygon2D.new()
	beam.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(2, -height), Vector2(-2, -height)])
	var bottom := Color(color.r, color.g, color.b, 0.75)
	var top := Color(color.r, color.g, color.b, 0.0)
	beam.vertex_colors = PackedColorArray([bottom, bottom, top, top])
	beam.z_index = -1
	return beam


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0 or collected:
		return
	age += 1
	if age > LIFETIME_FRAMES:
		queue_free()
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	var center := player.global_position + Vector2(0, -28) if player != null else Vector2.ZERO
	var here := global_position + Vector2(0, -6)
	var distance := here.distance_to(center) if player != null else 9999.0
	var currency: bool = drop["type"] in ["bucks", "gem"]
	if player != null and player.mode != Player.Mode.DEAD and currency and age > 20 and distance < MAGNET_RADIUS:
		velocity = (center - here).normalized() * MAGNET_SPEED
		position += velocity * Consts.DT
	else:
		velocity.y = Motion.fall_step(velocity.y)
		velocity.x = move_toward(velocity.x, 0.0, 4.0)
		var was_falling := velocity.y > 0.0
		move_and_slide()
		if is_on_floor():
			if was_falling and absf(velocity.y) < 1.0 and not settled and age > 10:
				settled = true
			velocity.y = 0.0
	if icon != null and settled:
		icon.position.y = (-8.0 if drop["type"] == "gem" else -14.0) + sin(age * 0.1) * 1.5
	var reach := 14.0 if currency else 22.0
	if player != null and player.mode != Player.Mode.DEAD and age > 12 and distance < reach:
		_collect()


func _collect() -> void:
	collected = true
	var gs := GameState.current
	if gs == null:
		queue_free()
		return
	gs.collect(drop)
	var at := global_position + Vector2(0, -30)
	match drop["type"]:
		"bucks":
			AudioService.sfx("pickup_coin", -4.0)
			FloatText.spawn(get_parent(), at, "+%d" % int(drop["amount"]), UIKit.COLORS["xp"])
		"gem":
			AudioService.sfx("pickup_gem", -3.0)
			FloatText.spawn(get_parent(), at, "+%d %s GEM%s" % [int(drop["count"]), String(drop["kind"]).to_upper(), "S" if int(drop["count"]) > 1 else ""], Color("9ad4ff"))
		"consumable":
			AudioService.sfx("pickup_item_common")
			FloatText.spawn(get_parent(), at, String(Db.legendary_data()["consumables"][drop["id"]]["name"]).to_upper(), UIKit.COLORS["good"])
		"gear":
			AudioService.sfx("pickup_item_common", -3.0)
	queue_free()
