class_name WorldFixture
extends RefCounted
## A tiny real world for headless physics tests: a synthetic room built with the same WorldBuilder the
## game uses, a Player driven by a ScriptedInput, and a fresh GameState.

var tree: SceneTree
var root: Node2D
var player: Player
var state: GameState
var level: Level
var input: ScriptedInput


## marks: {Vector2i tile: char}. The default room has a floor of ground at rows 20-22.
static func make(scene_tree: SceneTree, marks: Dictionary = {}, abilities: Array = [], spawn_tile: Vector2i = Vector2i(10, 19), gear: bool = true) -> WorldFixture:
	var fixture := WorldFixture.new()
	fixture.tree = scene_tree
	LiveInput.register_defaults()
	Combat.hitstop = 0
	fixture.state = GameState.begin(1, "normal", 7)
	GameState.current = fixture.state
	for ability: String in abilities:
		fixture.state.grant_ability(ability)
	if gear:
		fixture.state.add_item(Items.make("weapon", "bat", 0, 0, 1, "common"))
		fixture.state.add_item(Items.make("sub", "mitt_cannon", 0, 0, 1, "common"))
	var rows: Array = []
	for _y in Consts.CELL_TILES.y:
		rows.append(".".repeat(Consts.CELL_TILES.x))
	var layout := {}
	for x in Consts.CELL_TILES.x:
		for y in range(20, 23):
			layout[Vector2i(x, y)] = "#"
	layout.merge(marks, true)
	for tile: Vector2i in layout:
		var row: String = rows[tile.y]
		rows[tile.y] = row.substr(0, tile.x) + String(layout[tile]) + row.substr(tile.x + 1)
	fixture.level = Level.new()
	fixture.level.add_room({"id": "test", "area": "crash", "cell": [0, 0], "size": [1, 1], "tiles": rows, "entities": []})
	var geometry := LevelGeometry.build(fixture.level)
	fixture.root = Node2D.new()
	scene_tree.root.add_child(fixture.root)
	fixture.root.add_child(HitstopClock.new())
	fixture.root.add_child(WorldBuilder.solid_body(geometry))
	fixture.root.add_child(WorldBuilder.platform_body(geometry))
	fixture.input = ScriptedInput.new()
	fixture.player = Player.new()
	fixture.player.input = fixture.input
	fixture.root.add_child(fixture.player)
	fixture.player.global_position = Vector2(spawn_tile.x * Consts.TILE + 8, spawn_tile.y * Consts.TILE + Consts.TILE)
	return fixture


## Runs physics frames. Await it: `await fixture.step(30)`.
func step(frames: int) -> void:
	for _i in frames:
		await tree.physics_frame


## Holds actions for a number of frames.
func hold(actions: Array, frames: int) -> void:
	input._callback = Callable()
	input._segments = [[frames, actions]]
	input._segment = 0
	input._left = frames
	await step(frames)


func tap(actions: Array) -> void:
	await hold(actions, 1)


func settle() -> void:
	await step(20)


func dispose() -> void:
	Combat.hitstop = 0
	root.queue_free()
	GameState.current = null
