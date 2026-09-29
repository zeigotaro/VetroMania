extends TestCase
## Autograph Seal motions, map percentages and the input sources.


func _run(seal: SealInput, steps: Array) -> bool:
	## steps: [direction Vector2i, attack bool, frames]
	var success := false
	for step: Array in steps:
		for i in int(step[2]):
			if seal.advance(step[0], 1, bool(step[1]) and i == 0):
				success = true
	return success


func _fastball() -> SealInput:
	return SealInput.new(["D", "DF", "F", "A"], 180)


func test_fastball_with_the_full_quarter_circle() -> void:
	var steps := [[Vector2i(0, 1), false, 4], [Vector2i(1, 1), false, 4], [Vector2i(1, 0), false, 4], [Vector2i(0, 0), true, 1]]
	check(_run(_fastball(), steps), "Down, Down-Forward, Forward, Attack")


func test_fastball_when_the_dpad_skips_the_diagonal() -> void:
	var steps := [[Vector2i(0, 1), false, 4], [Vector2i(1, 0), false, 4], [Vector2i(1, 0), true, 1]]
	check(_run(_fastball(), steps), "lenient diagonals")


func test_wrong_order_or_missing_attack_fails() -> void:
	check(not _run(_fastball(), [[Vector2i(1, 0), false, 4], [Vector2i(0, 1), false, 4], [Vector2i(0, 0), true, 1]]), "Forward then Down")
	check(not _run(_fastball(), [[Vector2i(0, 1), false, 4], [Vector2i(1, 1), false, 4], [Vector2i(1, 0), false, 30]]), "no attack")
	check(not _run(_fastball(), [[Vector2i(0, 1), false, 4], [Vector2i(0, 0), true, 1]]), "Down and Attack only")


func test_stray_input_between_steps_breaks_the_motion() -> void:
	var steps := [[Vector2i(0, 1), false, 4], [Vector2i(-1, 0), false, 4], [Vector2i(1, 0), false, 4], [Vector2i(0, 0), true, 1]]
	check(not _run(_fastball(), steps), "a Back in the middle")


func test_junk_before_the_motion_is_fine() -> void:
	var steps := [[Vector2i(-1, 0), false, 6], [Vector2i(0, -1), false, 6], [Vector2i(0, 1), false, 4], [Vector2i(1, 1), false, 4], [Vector2i(1, 0), false, 4], [Vector2i(0, 0), true, 1]]
	check(_run(_fastball(), steps))


func test_the_window_is_three_seconds() -> void:
	var slow := _fastball()
	var late := [[Vector2i(0, 1), false, 4], [Vector2i(1, 1), false, 4], [Vector2i(1, 0), false, 200], [Vector2i(0, 0), true, 1]]
	check(not _run(slow, late), "too slow at 3 s")
	var wide := SealInput.new(["D", "DF", "F", "A"], 360)
	check(_run(wide, late), "Babby's First Planet doubles the window to 6 s")


func test_facing_mirrors_forward_and_back() -> void:
	var seal := _fastball()
	var success := false
	for step: Array in [[Vector2i(0, 1), 4], [Vector2i(-1, 1), 4], [Vector2i(-1, 0), 4]]:
		for _i in int(step[1]):
			seal.advance(step[0], -1, false)
	success = seal.advance(Vector2i(0, 0), -1, true)
	check(success, "facing left, the motion is Down, Down-Left, Left")
	eq(SealInput.direction_token(Vector2i(-1, 1), -1), "DF")
	eq(SealInput.direction_token(Vector2i(-1, 0), 1), "B")
	eq(SealInput.direction_token(Vector2i(0, -1), 1), "U")
	eq(SealInput.direction_token(Vector2i.ZERO, 1), "")


func test_seal_assist_is_a_single_press() -> void:
	var seal := SealInput.new(["D", "DF", "F", "A"], 180, true)
	check(seal.advance(Vector2i.ZERO, 1, true), "Seal Assist: Attack alone signs")


func test_map_percent_truncates_to_one_decimal() -> void:
	near(MapCells.percent(12, 13), 92.3, 0.0001, "12 of 13 cells")
	near(MapCells.percent(13, 13), 100.0, 0.0001)
	near(MapCells.percent(999, 1000), 99.9, 0.0001, "never 100.0 before the last cell")
	near(MapCells.percent(1, 600), 0.1, 0.0001, "each Vetromania cell is about 0.17%")
	near(MapCells.percent(0, 0), 0.0, 0.0001)


func test_cell_geometry() -> void:
	eq(MapCells.cell_of(Vector2(0, 0)), Vector2i(0, 0))
	eq(MapCells.cell_of(Vector2(639, 367)), Vector2i(0, 0))
	eq(MapCells.cell_of(Vector2(640, 368)), Vector2i(1, 1))
	eq(MapCells.cell_of(Vector2(-1, -1)), Vector2i(-1, -1))
	eq(MapCells.cell_rect(Vector2i(2, 1), Vector2i(2, 1)), Rect2(1280, 368, 1280, 368))
	eq(MapCells.cells_of(Vector2i(4, 1), Vector2i(2, 1)).size(), 2)
	eq(MapCells.from_key(MapCells.key(Vector2i(7, 3))), Vector2i(7, 3))


func test_scripted_input_replays_segments_with_edges() -> void:
	var input := ScriptedInput.new([[2, ["right"]], [3, ["right", "jump"]], [1, []]])
	var log: Array = []
	for _i in 8:
		input.poll()
		log.append([int(input.is_held("right")), int(input.just_pressed("jump")), int(input.just_released("jump")), int(input.just_released("right"))])
	eq(log[0], [1, 0, 0, 0])
	eq(log[2], [1, 1, 0, 0], "jump pressed on its first frame")
	eq(log[3], [1, 0, 0, 0], "and only that frame")
	eq(log[5], [0, 0, 1, 1], "released together")
	check(input.done())
	eq(input.direction(), Vector2i.ZERO)


func test_callback_input_is_reactive() -> void:
	var input := ScriptedInput.new([], func(frame: int) -> Array: return ["left"] if frame < 3 else ["down"])
	input.poll()
	eq(input.direction(), Vector2i(-1, 0))
	for _i in 4:
		input.poll()
	eq(input.direction(), Vector2i(0, 1))


func test_default_bindings_register_once() -> void:
	LiveInput.register_defaults()
	LiveInput.register_defaults()
	for action: String in InputSource.ACTIONS:
		check(InputMap.has_action("vm_" + action), "vm_%s exists" % action)
	var jump_events := InputMap.action_get_events("vm_jump")
	var keycodes: Array = []
	for event: InputEvent in jump_events:
		if event is InputEventKey:
			keycodes.append(event.physical_keycode)
	check(KEY_Z in keycodes and KEY_SPACE in keycodes, "Jump is Z or Space")
	var count := InputMap.action_get_events("vm_left").size()
	LiveInput.register_defaults()
	eq(InputMap.action_get_events("vm_left").size(), count, "no duplicate events")
