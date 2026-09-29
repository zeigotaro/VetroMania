class_name Prop
extends Node2D
## Everything in the world that is not an enemy, a tile or a pickup. One class with a `kind` keeps the
## slice's dozen interactables together; each defers to the World for UI (dialogue, menus, toasts).
## kinds: save_pod, vending, statue, npc, table, chest, orb, door, warp, hint

const PROMPT_RANGE_X := 26.0
const SPRITES := {
	"save_pod": "props/save_pod", "vending": "props/vending_machine", "statue": "props/koozie_statue",
	"table": "props/signing_table", "chest": "props/chest", "orb": "props/ability_orb",
	"door": "props/door", "warp": "props/warp_pipe",
}

var kind := ""
var data: Dictionary = {}
var world: Node
var key := ""
var room_id := ""
var sprite: AnimSprite
var prompt: Label
var area: Area2D
var solid: StaticBody2D
var player: Player
var near := false
var open := false
var secret := false
var age := 0
var hint_size := Vector2(64, 48)


static func create(prop_kind: String, prop_data: Dictionary, at: Vector2, world_ref: Node, prop_key: String, room: String) -> Prop:
	var prop := Prop.new()
	prop.kind = prop_kind
	prop.data = prop_data
	prop.position = at
	prop.world = world_ref
	prop.key = prop_key
	prop.room_id = room
	return prop


func _ready() -> void:
	var gs := GameState.current
	if SPRITES.has(kind):
		sprite = AnimSprite.new([SPRITES[kind]])
		sprite.play_key(SPRITES[kind], true)
		add_child(sprite)
	match kind:
		"npc":
			sprite = AnimSprite.new(["sleve/idle"])
			sprite.play_key("sleve/idle", true)
			sprite.modulate = _hologram_tint(String(data.get("name", "")))
			var ring := AnimSprite.new(["props/hologram_ring"])
			ring.play_key("props/hologram_ring", true)
			ring.z_index = -1
			add_child(ring)
			add_child(sprite)
		"chest":
			secret = bool(data.get("secret", false))
			if gs != null and gs.is_collected(key):
				open = true
				sprite.play_key("props/chest", true)
				sprite.pause()
				sprite.frame = 1
			else:
				sprite.pause()
				sprite.frame = 0
		"door":
			solid = StaticBody2D.new()
			solid.collision_layer = 1
			solid.collision_mask = 0
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(16, 64)
			shape.shape = box
			shape.position = Vector2(0, -32)
			solid.add_child(shape)
			add_child(solid)
			set_door(bool(data.get("open", true)))
		"warp":
			sprite.pause()
		"orb":
			if gs != null and gs.is_collected(key):
				queue_free()
				return
		"hint":
			var size: Array = data.get("size", [4, 3])
			hint_size = Vector2(float(size[0]), float(size[1])) * Consts.TILE
	if _interactive():
		area = Area2D.new()
		area.collision_layer = 1 << 6
		area.collision_mask = 0
		area.monitoring = false
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(32, 56)
		shape.shape = box
		shape.position = Vector2(0, -28)
		area.add_child(shape)
		area.set_meta("interactable", self)
		add_child(area)
		prompt = UIKit.label("UP", UIKit.COLORS["select"])
		prompt.position = Vector2(-6, -_top() - 12)
		prompt.z_index = 90
		prompt.visible = false
		add_child(prompt)


func _interactive() -> bool:
	return kind in ["save_pod", "vending", "statue", "npc", "table", "chest", "warp"]


func _top() -> float:
	match kind:
		"npc":
			return 74.0
		"save_pod", "vending", "warp":
			return 52.0
		"statue":
			return 60.0
		"chest", "table":
			return 30.0
	return 40.0


static func _hologram_tint(name: String) -> Color:
	var hue := float(absi(hash(name)) % 360) / 360.0
	var tint := Color.from_hsv(hue, 0.55, 1.0, 0.62)
	return Color(tint.r * 1.2, tint.g * 1.2, tint.b * 1.2, 0.62)


func set_door(is_open: bool) -> void:
	open = is_open
	if solid != null:
		solid.collision_layer = 0 if open else 1
	if sprite != null:
		sprite.pause()
		sprite.frame = 1 if open else 0
		if not is_open:
			AudioService.sfx("door_locked", -2.0)
		else:
			AudioService.sfx("door_open")


func _physics_process(_delta: float) -> void:
	age += 1
	if secret:
		visible = not (world != null and world.has_method("has_sealed_wall") and bool(world.call("has_sealed_wall", room_id)))
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var dx := player.global_position.x - global_position.x
	var dy := player.global_position.y - global_position.y
	near = absf(dx) < PROMPT_RANGE_X and dy > -_top() - 20.0 and dy < 20.0
	if prompt != null:
		prompt.visible = near and not player.is_frozen() and not (kind == "chest" and open)
		prompt.position.y = -_top() - 12 + sin(age * 0.15) * 1.5
	if kind == "npc" and sprite != null:
		sprite.set_facing(1 if dx > 0.0 else -1)
	match kind:
		"orb":
			if near and absf(dy + 12.0) < 40.0:
				_take_orb()
		"hint":
			var inside := absf(dx) < hint_size.x / 2.0 and dy > -hint_size.y and dy < 24.0
			if world != null and world.has_method("set_hint"):
				world.call("set_hint", self, String(data.get("text", "")) if inside else "")


func interact(_player: Player) -> void:
	if world == null or not visible:
		return
	match kind:
		"save_pod":
			world.call("open_pod", self)
		"vending":
			_vending()
		"statue":
			_statue()
		"npc":
			_npc()
		"table":
			_table()
		"chest":
			_chest()
		"warp":
			world.call("open_warp", self)


func _say(speaker: String, lines: Array, done: Callable = Callable()) -> void:
	world.call("say", speaker, lines, done)


func _vending() -> void:
	var gs := GameState.current
	if gs.is_collected(key):
		_say("VENDING MACHINE", ["OUT OF STOCK.", "A HANDWRITTEN NOTE SAYS: 'THE BAT WAS THE LAST ONE.'"])
		return
	_say("VENDING MACHINE", [
		"IT'S DANGEROUS TO GO ALONE. TAKE THIS.",
		"*THE MACHINE DISPENSES A FOAM BAT. IT ALSO COUNTS AS A BEAM BAT. DON'T ASK.*",
	], func() -> void:
		gs.mark_collected(key)
		gs.grant_ability("beam_bat")
		gs.add_item(Items.make("weapon", "bat", 0, 0, 1, "common"))
		AudioService.sfx("ability_get")
		world.call("toast", "BEAM BAT GET! IT SMASHES CRATE BULKHEADS.", UIKit.COLORS["select"]))


func _statue() -> void:
	var gs := GameState.current
	if gs.has_ability("spaceball"):
		_say("KOOZIE STATUE", ["THE STATUE IS HOLDING A KOOZIE. THE KOOZIE IS EMPTY.", "IT LOOKS PROUD ANYWAY."])
		return
	_say("KOOZIE STATUE", [
		"*THE ANCIENT KOOZIE GOD, KEEPER OF COLD DRINKS AND SMALL SPACES, OFFERS YOU THE SPACEBALL.*",
		"TAP DOWN TWICE TO CURL UP INTO A BALL. THAT'S THE WHOLE TEACHING.",
	], func() -> void:
		gs.grant_ability("spaceball")
		AudioService.sfx("ability_get")
		world.call("toast", "SPACEBALL GET! DOUBLE-TAP DOWN. FITS 2-TILE TUNNELS.", UIKit.COLORS["select"]))


func _npc() -> void:
	var lines: Array = []
	var name := String(data.get("name", "???"))
	for player_entry: Dictionary in Db.roster()["players"]:
		if player_entry["name"] == name:
			lines = player_entry.get("lines", [])
	if lines.is_empty():
		lines = ["...", "THE HOLOGRAM FLICKERS. IT HAS NOTHING TO SAY."]
	var talked: Array = GameState.current.data["world"]["talked"]
	if name not in talked:
		talked.append(name)
	_say(name.to_upper(), lines)


func _table() -> void:
	var gs := GameState.current
	if gs.has_seal(1):
		_say("THE SIGNING TABLE", ["YOUR FASTBALL IS ALREADY ON FILE.", "THE PEN IS STILL WARM."])
		return
	_say("THE SIGNING TABLE", [
		"AUTOGRAPHS! THE TABLE OFFERS YOU A PEN.",
		"PRACTICE THE FASTBALL SEAL: DOWN, DOWN-FORWARD, FORWARD, THEN ATTACK.",
	], func() -> void:
		world.call("start_seal", 1, true, func(success: bool) -> void:
			if success:
				gs.grant_seal(1)
				AudioService.sfx("ability_get")
				world.call("toast", "AUTOGRAPH SEAL 1: FASTBALL", UIKit.COLORS["select"])
			else:
				_say("THE SIGNING TABLE", ["THE PEN DRIES OUT. TRY AGAIN WHEN YOU'RE READY."])))


func _chest() -> void:
	if open:
		return
	var gs := GameState.current
	open = true
	gs.mark_collected(key)
	sprite.frame = 1
	AudioService.sfx("door_open")
	AudioService.sfx("pickup_item_rare", -2.0)
	var level := int(data.get("level", 5))
	var drops := Loot.roll_drops(gs.rng, gs.drop_context("chest", level))
	world.call("spawn_drops", drops, global_position + Vector2(0, -22))
	world.call("toast", "SECRET CACHE FOUND!", UIKit.COLORS["xp"])


func _take_orb() -> void:
	var gs := GameState.current
	var ability := String(data.get("ability", ""))
	gs.mark_collected(key)
	gs.grant_ability(ability)
	if data.has("item"):
		gs.add_item(Items.make(data["item"]["slot"], data["item"]["family"], 0, 0, int(data["item"].get("ilvl", 1)), "common"))
	var info: Dictionary = Db.areas()["abilities"].get(ability, {"name": ability, "text": ""})
	AudioService.sfx("ability_get")
	world.call("toast", "%s GET! %s" % [String(info["name"]).to_upper(), String(info["text"]).to_upper()], UIKit.COLORS["select"])
	if data.has("line"):
		world.call("say", "SPACE MONKEYS", [String(data["line"])], Callable())
	queue_free()
