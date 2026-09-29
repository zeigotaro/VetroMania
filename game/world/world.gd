class_name World
extends Node2D
## The playable slice: one global tile grid, Sleve, the props of every room, and the enemies of the room he
## is in. UI lives elsewhere and talks to the World through signals (has_ui = true); without UI everything
## resolves immediately, which is how headless tests and bots run it.

signal room_changed(room: Dictionary, previous: Dictionary)
signal area_entered(area_id: String, first_time: bool)
signal dialogue_requested(speaker: String, lines: Array, done: Callable)
signal pod_requested(prop: Prop)
signal warp_requested(prop: Prop)
signal seal_requested(seal_id: int, practice: bool, done: Callable)
signal toast_requested(text: String, color: Color)
signal item_toast_requested(item: Dictionary, equipped: bool)
signal hint_changed(text: String)
signal montage_requested
signal boss_changed(boss: BossKrate)
signal player_died
signal slice_completed

const PLAYER_CENTER := Vector2(0, -28)
const END_DELAY_FRAMES := 150

var level: Level
var geometry: Dictionary = {}
var gs: GameState
var player: Player
var camera: GameCamera
var background: ParallaxBg
var actors: Node2D
var tiles: Dictionary = {}
var gates: Array = []
var targets: Array = []
var props: Array = []
var current_room: Dictionary = {}
var has_ui := false
var auto_seal := true
var boss: BossKrate
var arena_door: Prop
var arena_armed := false
var active_hint: Prop
var hint_text := ""
var frame := 0
var end_timer := -1
var problems: Array[String] = []


func build(state: GameState, input: InputSource = null, level_override: Level = null) -> void:
	gs = state
	GameState.current = state
	level = level_override if level_override != null else Level.load_all()
	problems = level.validate()
	for problem in problems:
		push_error("Level: " + problem)
	geometry = LevelGeometry.build(level)
	background = ParallaxBg.new()
	add_child(background)
	var visuals := Node2D.new()
	visuals.name = "Tiles"
	add_child(visuals)
	tiles = WorldBuilder.build_tiles(visuals, level)
	add_child(HitstopClock.new())
	add_child(WorldBuilder.solid_body(geometry))
	add_child(WorldBuilder.platform_body(geometry))
	add_child(WorldBuilder.spike_areas(geometry, func(tile: Vector2i) -> int: return _hazard_level(tile)))
	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)
	_build_gates()
	_build_props()
	player = Player.new()
	player.input = input if input != null else LiveInput.new()
	actors.add_child(player)
	player.died.connect(func() -> void: player_died.emit())
	player.knack_used.connect(_on_knack)
	camera = GameCamera.new()
	add_child(camera)
	gs.leveled_up.connect(_on_level_up)
	gs.montage_ready.connect(func() -> void: montage_requested.emit())
	gs.tally_event.connect(_on_tally_event)
	gs.item_gained.connect(func(item: Dictionary, equipped: bool) -> void: item_toast_requested.emit(item, equipped))
	gs.ability_gained.connect(_on_ability)
	var spawn := _spawn_position()
	player.respawn(spawn)
	camera.target = spawn
	current_room = {}
	_enter_room(level.room_at_pixel(spawn + PLAYER_CENTER), true)
	camera.set_room(level.room_rect(current_room), true)


func _hazard_level(tile: Vector2i) -> int:
	var room := level.room_at_cell(Vector2i(floori(tile.x / float(Consts.CELL_TILES.x)), floori(tile.y / float(Consts.CELL_TILES.y))))
	return gs.enemy_level(room["area"]) if not room.is_empty() else 1


func _spawn_position() -> Vector2:
	var checkpoint: Dictionary = gs.data["checkpoint"]
	if checkpoint.has("pos"):
		return Vector2(float(checkpoint["pos"][0]), float(checkpoint["pos"][1]))
	var room := level.room(String(checkpoint["room"]))
	for entity: Dictionary in room.get("entities", []):
		if entity["type"] == "spawn" and entity["id"] == checkpoint["spawn"]:
			return level.entity_position(room, entity["at"])
	if room.is_empty():
		room = level.rooms[level.order[0]]
	return level.entity_position(room, [3, 19])


# --- building ---------------------------------------------------------------------------------------------

func _build_gates() -> void:
	for data: Dictionary in geometry["gates"]:
		if gs.is_opened(data["key"]):
			erase_tiles(data["tiles"])
			continue
		var gate := Gate.new()
		gate.setup(data, self)
		add_child(gate)
		gates.append(gate)
	for data: Dictionary in geometry["targets"]:
		var target := MittTarget.new()
		target.setup(data, self)
		target.lit = gs.is_opened(data["key"])
		add_child(target)
		targets.append(target)
		if target.lit:
			var room := level.room(data["room"])
			tiles["front"][room["area"]].set_cell(data["tile"], 0, WorldBuilder.tile_cell("mitt_target_1"))


func _build_props() -> void:
	for id: String in level.order:
		var room: Dictionary = level.rooms[id]
		for entity: Dictionary in room["entities"]:
			var kind: String = entity["type"]
			if kind in ["enemy", "spawn", "boss"]:
				continue
			var at := level.entity_position(room, entity["at"])
			var key := "%s:%s:%d,%d" % [id, kind, int(entity["at"][0]), int(entity["at"][1])]
			var prop := Prop.create(kind, entity, at, self, key, id)
			actors.add_child(prop)
			props.append(prop)
			if kind == "door":
				arena_door = prop


func erase_tiles(tile_list: Array) -> void:
	for tile: Vector2i in tile_list:
		var room := level.room_at_cell(Vector2i(floori(tile.x / float(Consts.CELL_TILES.x)), floori(tile.y / float(Consts.CELL_TILES.y))))
		if not room.is_empty() and tiles.has("front") and tiles["front"].has(room["area"]):
			tiles["front"][room["area"]].erase_cell(tile)


## True while a hollow wall in the room is still standing; props marked secret stay hidden until it breaks.
func has_sealed_wall(room_id: String) -> bool:
	for gate in gates:
		if is_instance_valid(gate) and gate.kind == "%" and gate.room_id == room_id:
			return true
	return false


func open_shutters(room_id: String) -> void:
	var opened := false
	for gate in gates:
		if is_instance_valid(gate) and gate.kind == "C" and gate.room_id == room_id:
			gate.open()
			opened = true
	var room := level.room(room_id)
	for target: MittTarget in targets:
		if target.room_id == room_id:
			tiles["front"][room["area"]].set_cell(target.tile, 0, WorldBuilder.tile_cell("mitt_target_1"))
	if opened:
		camera.shake(1.5, 14)
		toast("THE CONDUIT SHUTTER OPENS!", UIKit.COLORS["ep"])
	gates = gates.filter(func(gate: Variant) -> bool: return is_instance_valid(gate))


# --- per frame --------------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	frame += 1
	gs.data["playtime"] = float(gs.data["playtime"]) + Consts.DT
	var center := player.global_position + PLAYER_CENTER
	var room := level.room_at_pixel(center)
	if not room.is_empty() and room["id"] != current_room.get("id", ""):
		_enter_room(room, false)
	gs.visit_cell(MapCells.cell_of(center))
	camera.follow(player.global_position, player.facing)
	background.update_scroll(camera.global_position.x)
	if frame % 30 == 0:
		_animate_targets()
	if arena_armed and arena_door != null and arena_door.open and boss != null and player.global_position.x > arena_door.global_position.x + 44.0:
		arena_door.set_door(false)
	if end_timer > 0:
		end_timer -= 1
		if end_timer == 0:
			slice_completed.emit()


func _animate_targets() -> void:
	var phase := (frame / 30) % 2
	for target: MittTarget in targets:
		if not target.lit:
			var room := level.room(target.room_id)
			tiles["front"][room["area"]].set_cell(target.tile, 0, WorldBuilder.tile_cell("mitt_target_%d" % phase))


func _enter_room(room: Dictionary, first: bool) -> void:
	if room.is_empty():
		return
	var previous := current_room
	current_room = room
	camera.set_room(level.room_rect(room), false)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Enemy and not (enemy is BossKrate):
			enemy.queue_free()
	_spawn_room_enemies(room)
	var area_id: String = room["area"]
	if previous.is_empty() or previous["area"] != area_id:
		var area: Dictionary = Db.areas()["areas"][area_id]
		background.set_area(area_id, _area_span(area_id))
		if boss == null:
			AudioService.music(String(area["music"]))
		var seen_flag := "area_seen_" + area_id
		var first_time := not bool(gs.flag(seen_flag, false))
		gs.set_flag(seen_flag, true)
		area_entered.emit(area_id, first_time)
		if not first:
			gs.checkpoint(String(room["id"]), "auto", player.global_position)
			gs.save()
	_maybe_start_boss(room)
	room_changed.emit(room, previous)


func _area_span(area_id: String) -> Vector2:
	var lo := 1.0e9
	var hi := -1.0e9
	for id: String in level.order:
		var room: Dictionary = level.rooms[id]
		if room["area"] == area_id:
			var rect := level.room_rect(room)
			lo = minf(lo, rect.position.x)
			hi = maxf(hi, rect.end.x)
	return Vector2(lo, hi)


func _spawn_room_enemies(room: Dictionary) -> void:
	var elite_chance := float(Db.elite()["chance"]) * float(gs.mode()["elite_rolls"])
	for entity: Dictionary in room["entities"]:
		if entity["type"] != "enemy":
			continue
		var count := int(entity.get("count", 1))
		for i in count:
			var at := level.entity_position(room, entity["at"]) + Vector2((i - (count - 1) / 2.0) * 22.0, -float(i % 2) * 10.0)
			var enemy_level := gs.enemy_level(room["area"], int(entity.get("level", 0)))
			var elite: bool = bool(entity["elite"]) if entity.has("elite") else gs.rng.randf() < elite_chance
			var affix := ""
			if elite:
				enemy_level += Consts.ELITE_LEVEL_BONUS
				var affixes: Array = Db.elite()["affixes"]
				affix = affixes[gs.rng.randi() % affixes.size()]
			var enemy := Enemy.create(entity["id"], enemy_level, elite, affix, at)
			enemy.room_id = room["id"]
			enemy.died.connect(_on_enemy_died)
			actors.add_child(enemy)


func _maybe_start_boss(room: Dictionary) -> void:
	if boss != null and is_instance_valid(boss):
		return
	for entity: Dictionary in room["entities"]:
		if entity["type"] != "boss":
			continue
		var state := gs.boss_state(entity["id"])
		if bool(state["defeated"]):
			return
		var at := level.entity_position(room, entity["at"])
		boss = BossKrate.make(at, float(state["hp_frac"]))
		var rect := level.room_rect(room)
		boss.arena_left = rect.position.x + Consts.TILE
		boss.arena_right = rect.end.x - Consts.TILE
		boss.died.connect(_on_boss_died)
		boss.finish_requested.connect(_on_boss_finish)
		actors.add_child(boss)
		arena_armed = true
		toast("KRATE", UIKit.COLORS["bad"])
		boss_changed.emit(boss)
		return


# --- kills, drops, bosses ----------------------------------------------------------------------------------

func _on_enemy_died(enemy: Enemy) -> void:
	var result := gs.register_kill(enemy.id, enemy.level, enemy.elite, enemy.affix == "extra_salty")
	var at := enemy.global_position + Vector2(0, -enemy.bounds.y / 2.0)
	FloatText.spawn(actors, enemy.global_position + Vector2(0, -enemy.bounds.y - 16.0), "+%d XP" % int(result["xp"]), UIKit.COLORS["xp"], 1, 44)
	spawn_drops(result["drops"], at)


func spawn_drops(drops: Array, at: Vector2) -> void:
	for drop: Dictionary in drops:
		Pickup.spawn(actors, at, drop, gs.rng)


func _on_boss_finish(b: BossKrate) -> void:
	var seal_id := int(b.boss_def["seal"])
	var has_seal := gs.has_seal(seal_id)
	Combat.hitstop = 1000000
	var finish := func(success: bool) -> void:
		Combat.hitstop = 0
		var signed := success and has_seal
		b.resolve_finish(signed)
		if not signed and not has_seal:
			_retreat_boss(b)
	if has_ui:
		seal_requested.emit(seal_id, false, finish)
	else:
		finish.call(auto_seal)


func _retreat_boss(b: BossKrate) -> void:
	gs.set_boss_state("krate", false, float(b.boss_def["fail_recover"]))
	toast("THE ARENA DOORS OPEN. HE'LL WAIT AT 20% HP. GO GET YOUR SEAL.", UIKit.COLORS["bad"])
	if arena_door != null:
		arena_door.set_door(true)
	arena_armed = false
	b.queue_free()
	boss = null
	boss_changed.emit(null)
	AudioService.music(String(Db.areas()["areas"][current_room["area"]]["music"]))


func _on_boss_died(b: BossKrate) -> void:
	var result := gs.register_kill("krate", b.level, false, false, true)
	gs.set_boss_state("krate", true, 0.0)
	var at := b.global_position + Vector2(0, -50)
	FloatText.spawn(actors, b.global_position + Vector2(0, -b.bounds.y - 20.0), "+%d XP" % int(result["xp"]), UIKit.COLORS["xp"], 2, 90)
	spawn_drops(result["drops"], at)
	var orb := Prop.create("orb", {"ability": "jetpack", "line": ""}, b.global_position + Vector2(0, -6), self, "krate:jetpack", String(current_room["id"]))
	actors.add_child.call_deferred(orb)
	if arena_door != null:
		arena_door.set_door(true)
	arena_armed = false
	boss = null
	boss_changed.emit(null)
	AudioService.music(String(Db.areas()["areas"][current_room["area"]]["music"]))
	AudioService.music_pitch(1.0)
	toast("KRATE SIGNED OFF! THE CRATE IS A LIE.", UIKit.COLORS["select"])


# --- signals from the state ------------------------------------------------------------------------------

func _on_level_up(new_level: int) -> void:
	AudioService.sfx("level_up")
	toast("LEVEL UP! LV %d" % new_level, UIKit.COLORS["xp"])
	if player != null:
		FloatText.spawn(actors, player.global_position + Vector2(0, -72), "LEVEL UP!", UIKit.COLORS["xp"], 2, 70)


func _on_tally_event(enemy_id: String, event: String) -> void:
	var name := String(Db.enemy(enemy_id)["name"]).to_upper()
	var perk := String(Tallies.perk_def(Tallies.perk_for(enemy_id)).get("name", "")).to_upper()
	match event:
		"first_kill":
			toast("BESTIARY: %s LOGGED. FIRST KILL BONUS: 5X XP" % name, UIKit.COLORS["dim"])
		"revealed":
			toast("%s: WEAKNESSES AND DROPS REVEALED" % name, UIKit.COLORS["ep"])
		"rival":
			toast("RIVAL! %s DROP LOOT MORE OFTEN FOR YOU" % name, UIKit.COLORS["ep"])
		"complete":
			AudioService.sfx("tally_complete")
			toast("TALLY COMPLETE! %s" % perk, UIKit.COLORS["xp"])


func _on_ability(id: String) -> void:
	if id == "jetpack" and end_timer < 0:
		end_timer = END_DELAY_FRAMES


func _on_knack(perk_id: String) -> void:
	match perk_id:
		"echolocation_ping":
			ping()
		"satellite_uplink":
			var on := not bool(gs.runtime_flags.get("uplink", false))
			gs.runtime_flags["uplink"] = on
			AudioService.sfx("toast")
			toast("SATELLITE UPLINK %s" % ("ON" if on else "OFF"), UIKit.COLORS["ep"])


## Reveals hollow walls near Sleve. It never breaks them.
func ping() -> void:
	var def := Tallies.perk_def("echolocation_ping")
	var range_px := float(def["range_px"][Tallies.perk_level(gs.data["tallies"], "echolocation_ping") - 1])
	var center := player.global_position + PLAYER_CENTER
	var ring := PingRing.new(range_px)
	ring.position = center
	actors.add_child(ring)
	AudioService.sfx("hey_listen")
	for gate in gates:
		if is_instance_valid(gate) and gate.kind == "%" and gate.bounds.get_center().distance_to(center) <= range_px:
			gate.reveal_for(360)


## Global positions of things worth finding in the current room, for Satellite Uplink.
func item_markers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rect := level.room_rect(current_room)
	for prop: Prop in props:
		if not is_instance_valid(prop) or not rect.has_point(prop.global_position + Vector2(0, -8)):
			continue
		if (prop.kind == "chest" and not prop.open) or (prop.kind == "orb"):
			out.append(prop.global_position)
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if pickup is Pickup and rect.has_point(pickup.global_position) and pickup.drop["type"] == "gear":
			out.append(pickup.global_position)
	return out


# --- services for props and UI ---------------------------------------------------------------------------

func toast(text: String, color: Color = UIKit.COLORS["text"]) -> void:
	toast_requested.emit(text, color)


func say(speaker: String, lines: Array, done: Callable = Callable()) -> void:
	if not has_ui:
		if not done.is_null():
			done.call()
		return
	player.freeze(true)
	dialogue_requested.emit(speaker, lines, func() -> void:
		player.freeze(false)
		if not done.is_null():
			done.call())


func start_seal(seal_id: int, practice: bool, done: Callable) -> void:
	if not has_ui:
		done.call(auto_seal)
		return
	player.freeze(true)
	seal_requested.emit(seal_id, practice, func(success: bool) -> void:
		player.freeze(false)
		done.call(success))


func set_hint(prop: Prop, text: String) -> void:
	if text != "":
		active_hint = prop
	elif prop != active_hint:
		return
	elif active_hint != null:
		active_hint = null
	if text != hint_text:
		hint_text = text
		hint_changed.emit(text)


func open_pod(prop: Prop) -> void:
	gs.full_restore()
	gs.checkpoint(prop.room_id, "pod", prop.global_position + Vector2(0, 0))
	AudioService.sfx("save_pod")
	var error := gs.save()
	if has_ui:
		player.freeze(true)
		pod_requested.emit(prop)
	else:
		toast("GAME SAVED" if error == OK else "SAVE FAILED", UIKit.COLORS["good"] if error == OK else UIKit.COLORS["bad"])


func open_warp(prop: Prop) -> void:
	var pipes: Array = gs.flag("pipes", [])
	if prop.key not in pipes:
		pipes.append(prop.key)
		gs.set_flag("pipes", pipes)
	AudioService.sfx("warp_pipe")
	if has_ui:
		player.freeze(true)
		warp_requested.emit(prop)
	else:
		toast("WELCOME TO WARP ZONE!", UIKit.COLORS["xp"])


func pipe_props() -> Array[Prop]:
	var out: Array[Prop] = []
	var pipes: Array = gs.flag("pipes", [])
	for prop: Prop in props:
		if is_instance_valid(prop) and prop.kind == "warp" and prop.key in pipes:
			out.append(prop)
	return out


func teleport_to(at: Vector2) -> void:
	player.respawn(at)
	var room := level.room_at_pixel(at + PLAYER_CENTER)
	if not room.is_empty() and room["id"] != current_room.get("id", ""):
		_enter_room(room, false)
	camera.target = at
	camera.set_room(level.room_rect(current_room), true)


func teleport_to_room(room_id: String, tile: Array) -> void:
	teleport_to(level.entity_position(level.room(room_id), tile))
