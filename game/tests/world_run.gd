class_name WorldRun
extends RefCounted
## The real game world (real level, real props, real enemies) driven headless by a ScriptedInput.
## Tests await step()/hold()/walk_to(); has_ui stays false so dialogue and menus resolve instantly.

var tree: SceneTree
var world: World
var state: GameState
var input: ScriptedInput
var player: Player


## abilities are granted up front; room/tile place Sleve (default: the start of the game).
static func make(scene_tree: SceneTree, abilities: Array = [], room_id: String = "", tile: Array = [], seed_value: int = 7, gear: bool = false) -> WorldRun:
	var run := WorldRun.new()
	run.tree = scene_tree
	LiveInput.register_defaults()
	seed(seed_value)
	Combat.hitstop = 0
	run.state = GameState.begin(1, "normal", seed_value)
	GameState.current = run.state
	for ability: String in abilities:
		run.state.grant_ability(ability)
	if gear or abilities.has("beam_bat"):
		run.state.add_item(Items.make("weapon", "bat", 0, 0, 1, "common"))
	if abilities.has("mitt_cannon"):
		run.state.add_item(Items.make("sub", "mitt_cannon", 0, 0, 1, "common"))
	run.world = World.new()
	scene_tree.root.add_child(run.world)
	await scene_tree.process_frame
	run.input = ScriptedInput.new()
	run.world.build(run.state, run.input)
	run.player = run.world.player
	if room_id != "":
		run.world.teleport_to_room(room_id, tile)
	return run


func step(frames: int) -> void:
	for _i in frames:
		await tree.physics_frame


func hold(actions: Array, frames: int) -> void:
	input._callback = Callable()
	input._segments = [[frames, actions]]
	input._segment = 0
	input._left = frames
	await step(frames)
	input._segments = []


func tap(actions: Array) -> void:
	await hold(actions, 1)


## Walks along the floor until Sleve's x is within tolerance of world x. Returns whether it got there.
func walk_to(x: float, max_frames: int = 900, tolerance: float = 3.0) -> bool:
	var goal := x
	input._segments = []
	input._callback = func(_frame: int) -> Array:
		var dx := goal - player.global_position.x
		if absf(dx) <= tolerance:
			return []
		return ["right"] if dx > 0.0 else ["left"]
	var frames := 0
	while frames < max_frames and absf(goal - player.global_position.x) > tolerance:
		await tree.physics_frame
		frames += 1
	input._callback = Callable()
	await tree.physics_frame
	return absf(goal - player.global_position.x) <= tolerance


func tile_x(room_id: String, col: int) -> float:
	return world.level.entity_position(world.level.room(room_id), [col, 0]).x


## Feet position for standing in a tile of a room (the same convention as entity `at`).
func feet(room_id: String, col: int, row: int) -> Vector2:
	return world.level.entity_position(world.level.room(room_id), [col, row])


## Steers Sleve to a feet position and waits for him to stand there. Jumps walls and gaps and climbs toward
## a higher goal, so it plays a route the way a person would: one waypoint at a time.
func go(goal: Vector2, max_frames: int = 900, tolerance: float = 5.0) -> bool:
	var memory := {"hold": 0, "last_jump": false}
	input._segments = []
	input._callback = func(_frame: int) -> Array:
		return _steer(goal, memory)
	var frames := 0
	while frames < max_frames and not _arrived(goal, tolerance):
		await tree.physics_frame
		frames += 1
	input._callback = Callable()
	await tree.physics_frame
	return _arrived(goal, tolerance)


func _arrived(goal: Vector2, tolerance: float) -> bool:
	var at := player.global_position
	return absf(goal.x - at.x) <= tolerance and absf(goal.y - at.y) <= 6.0 and player.is_on_floor()


func _steer(goal: Vector2, memory: Dictionary) -> Array:
	var at := player.global_position
	var dx := goal.x - at.x
	var dy := goal.y - at.y
	var dir := 0
	if absf(dx) > 3.0:
		dir = 1 if dx > 0.0 else -1
	var actions: Array = []
	if dir > 0:
		actions.append("right")
	elif dir < 0:
		actions.append("left")
	var grounded := player.is_on_floor()
	var air_jump := false
	if not grounded and dy < -8.0 and player.velocity.y > -30.0 and not bool(memory["last_jump"]) and state.has_ability("jetpack") and not player.air_jump_used:
		air_jump = true
	if grounded:
		var want := false
		if dy < -10.0 and absf(dx) < 110.0:
			want = true
		if dir != 0 and player.test_move(player.global_transform, Vector2(dir * 5.0, 0)):
			want = true
		if dir != 0 and absf(dx) > 30.0 and not player.test_move(player.global_transform.translated(Vector2(dir * 13.0, 0)), Vector2(0, 10)):
			want = true
		if want and not bool(memory["last_jump"]):
			memory["hold"] = 44
	var jumping: bool = air_jump or (int(memory["hold"]) > 0 and (grounded or player.velocity.y < 0.0))
	if jumping:
		actions.append("jump")
		memory["hold"] = int(memory["hold"]) - 1
	else:
		memory["hold"] = 0
	memory["last_jump"] = jumping
	return actions


## Wall-kicks up a shaft: alternate walls, jump every time a wall is touched, steer to the other wall.
func climb(top_y: float, max_frames: int = 900) -> bool:
	var memory := {"side": -1, "last_jump": false}
	input._segments = []
	input._callback = func(_frame: int) -> Array:
		var actions: Array = []
		var touching: int = int(player.call("_wall_side"))
		if touching != 0:
			memory["side"] = touching
		actions.append("left" if int(memory["side"]) > 0 else "right")
		var press := (player.is_on_floor() or touching != 0) and not bool(memory["last_jump"])
		if press:
			actions.append("jump")
		memory["last_jump"] = press
		return actions
	var frames := 0
	while frames < max_frames and player.global_position.y > top_y:
		await tree.physics_frame
		frames += 1
	input._callback = Callable()
	await tree.physics_frame
	return player.global_position.y <= top_y


func swing() -> void:
	await hold(["attack"], 1)
	await step(28)


## Adds an enemy the same way the World does when Sleve enters its room.
func spawn_enemy(enemy_id: String, at: Vector2, enemy_level: int = 1, elite: bool = false, affix: String = "") -> Enemy:
	var enemy := Enemy.create(enemy_id, enemy_level, elite, affix, at)
	enemy.room_id = String(world.current_room["id"])
	enemy.died.connect(world._on_enemy_died)
	world.actors.add_child(enemy)
	return enemy


func count_nodes(script_class: String) -> int:
	var total := 0
	for node in world.actors.get_children():
		var script: Script = node.get_script()
		if script != null and String(script.get_global_name()) == script_class:
			total += 1
	return total


## Removes every enemy so a test about props and gates is not interrupted by a hunch-bot's bolt.
func clear_enemies() -> void:
	for enemy in tree.get_nodes_in_group("enemy"):
		enemy.queue_free()
	await tree.physics_frame


func dispose() -> void:
	Combat.hitstop = 0
	world.queue_free()
	GameState.current = null
