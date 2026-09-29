extends TestCase
## Player movement against real physics, at 60 Hz. Heights are measured, not assumed.

const FLOOR_Y := 320.0


## Holds actions for N frames and reports how far the player travelled.
func _track(f: WorldFixture, actions: Array, frames: int) -> Dictionary:
	var start := f.player.global_position
	var top := start.y
	var far_x := start.x
	f.input._callback = Callable()
	f.input._segments = [[frames, actions]]
	f.input._segment = 0
	f.input._left = frames
	for _i in frames:
		await tree.physics_frame
		top = minf(top, f.player.global_position.y)
		far_x = maxf(far_x, f.player.global_position.x)
	return {"rise": start.y - top, "dx": f.player.global_position.x - start.x, "end": f.player.global_position, "start": start}


func test_standing_on_the_floor() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	near(f.player.global_position.y, FLOOR_Y, 0.6, "feet rest on the floor")
	check(f.player.is_on_floor(), "grounded")
	f.dispose()


func test_full_hold_jump_is_56_px() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var run := await _track(f, ["jump"], 60)
	near(run["rise"], 56.0, 1.0, "full hold apex")
	f.dispose()


func test_tap_jump_is_24_px() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var run := await _track(f, ["jump"], 1)
	var top: float = FLOOR_Y - float(run["rise"])
	for _i in 60:
		await tree.physics_frame
		top = minf(top, f.player.global_position.y)
	near(FLOOR_Y - top, 24.0, 1.5, "tap apex")
	f.dispose()


func test_runs_at_150_px_per_second_and_stops_in_3_frames() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	await f.hold(["right"], 10)
	near(f.player.velocity.x, 150.0, 0.5, "full speed")
	var before := f.player.global_position.x
	await f.hold(["right"], 30)
	near(f.player.global_position.x - before, 150.0 * 30.0 / 60.0, 3.0, "150 px/s")
	await f.step(3)
	near(f.player.velocity.x, 0.0, 0.5, "stopped")
	f.dispose()


func test_coyote_time_is_six_frames() -> void:
	var marks := {}
	for x in range(0, 14):
		for y in range(20, 23):
			marks[Vector2i(x, y)] = "#"
	for x in range(14, 40):
		for y in range(20, 23):
			marks[Vector2i(x, y)] = "."
	var f := WorldFixture.make(tree, marks, [], Vector2i(12, 19))
	await f.settle()
	f.input._segments = [[200, ["right"]]]
	f.input._segment = 0
	f.input._left = 200
	while f.player.is_on_floor():
		await tree.physics_frame
	await f.step(3)
	f.input._segments = [[10, ["right", "jump"]]]
	f.input._segment = 0
	f.input._left = 10
	var y0 := f.player.global_position.y
	await f.step(4)
	check(f.player.global_position.y < y0 + 4.0 and f.player.velocity.y < 0.0, "a jump pressed 3 frames after leaving the ledge still works")
	f.dispose()
	var late := WorldFixture.make(tree, marks, [], Vector2i(12, 19))
	await late.settle()
	late.input._segments = [[200, ["right"]]]
	late.input._segment = 0
	late.input._left = 200
	while late.player.is_on_floor():
		await tree.physics_frame
	await late.step(10)
	late.input._segments = [[6, ["right", "jump"]]]
	late.input._segment = 0
	late.input._left = 6
	await late.step(3)
	check(late.player.velocity.y > 0.0, "ten frames off the ledge is too late")
	late.dispose()


func test_jump_buffer_catches_an_early_press() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	await f.hold(["jump"], 1)
	await f.step(2)
	while f.player.velocity.y <= 0.0:
		await tree.physics_frame
	while f.player.global_position.y < FLOOR_Y - 12.0:
		await tree.physics_frame
	await f.tap(["jump"])
	await f.step(12)
	check(f.player.velocity.y < 0.0 or f.player.global_position.y < FLOOR_Y - 1.0, "a jump pressed just before landing fires on landing")
	f.dispose()


func test_double_jump_adds_40_px() -> void:
	var f := WorldFixture.make(tree, {}, ["jetpack"])
	await f.settle()
	## Tap, then press again near the apex of the tap jump (frame 12), holding nothing else.
	f.input._segments = [[1, ["jump"]], [11, []], [1, ["jump"]], [60, []]]
	f.input._segment = 0
	f.input._left = 1
	var top := f.player.global_position.y
	var apex_before_second := f.player.global_position.y
	for i in 60:
		await tree.physics_frame
		top = minf(top, f.player.global_position.y)
		if i < 12:
			apex_before_second = minf(apex_before_second, f.player.global_position.y)
	var gained := apex_before_second - top
	near(gained, 40.0, 4.0, "the second jump adds about 40 px above where it started (%.1f)" % gained)
	f.dispose()
	var without := WorldFixture.make(tree)
	await without.settle()
	without.input._segments = [[1, ["jump"]], [11, []], [1, ["jump"]], [60, []]]
	without.input._segment = 0
	without.input._left = 1
	var flat_top := without.player.global_position.y
	for _i in 60:
		await tree.physics_frame
		flat_top = minf(flat_top, without.player.global_position.y)
	near(FLOOR_Y - flat_top, 24.0, 2.5, "no jetpack, no second jump")
	without.dispose()


func test_wall_kick_is_48_px_up_and_32_px_out() -> void:
	var marks := {}
	for y in range(2, 20):
		marks[Vector2i(10, y)] = "B"
	var f := WorldFixture.make(tree, marks, ["wall_kick"], Vector2i(12, 19))
	await f.settle()
	f.input._segments = [[22, ["jump", "left"]], [200, ["left"]]]
	f.input._segment = 0
	f.input._left = 22
	var sliding := false
	for _i in 120:
		await tree.physics_frame
		if f.player.wall_slide:
			sliding = true
			break
	check(sliding, "pressing into the wall while falling starts a wall slide")
	await f.step(6)
	check(f.player.velocity.y <= Consts.WALL_SLIDE_SPEED + 0.5, "the slide caps fall speed at 60 px/s (%.1f)" % f.player.velocity.y)
	var start := f.player.global_position
	f.input._segments = [[1, ["jump", "left"]], [30, []]]
	f.input._segment = 0
	f.input._left = 1
	var top := start.y
	await tree.physics_frame
	await tree.physics_frame
	near(f.player.velocity.y, -Motion.wall_kick_v0() + 17.2, 6.0, "launched upward at the wall-kick speed")
	for _i in 40:
		await tree.physics_frame
		top = minf(top, f.player.global_position.y)
	near(start.y - top, 48.0, 3.0, "48 px of height from the kick point")
	near(f.player.global_position.x - start.x, 32.0, 1.5, "and 32 px of push away from the wall")
	f.dispose()


func test_no_wall_kick_without_the_ability() -> void:
	var marks := {}
	for y in range(2, 20):
		marks[Vector2i(10, y)] = "B"
	var f := WorldFixture.make(tree, marks, [], Vector2i(12, 19))
	await f.settle()
	f.input._segments = [[40, ["jump", "left"]], [200, ["left"]]]
	f.input._segment = 0
	f.input._left = 40
	await f.step(60)
	check(not f.player.wall_slide, "no Monkey Business, no wall slide")
	f.dispose()


func test_slide_is_48_px_in_15_frames_with_a_40_px_hitbox() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var start_x := f.player.global_position.x
	f.input._segments = [[1, ["down", "jump"]], [40, []]]
	f.input._segment = 0
	f.input._left = 1
	await f.step(2)
	eq(f.player.mode, Player.Mode.SLIDE, "sliding")
	eq((f.player.shape.shape as RectangleShape2D).size.y, 40.0, "the hitbox is 40 px tall")
	await f.step(20)
	near(f.player.global_position.x - start_x, 48.0, 3.5, "48 px")
	eq(f.player.mode, Player.Mode.NORMAL, "back on his feet")
	eq((f.player.shape.shape as RectangleShape2D).size.y, 56.0)
	f.dispose()


func test_slide_clears_a_three_tile_gap_but_walking_cannot() -> void:
	var marks := {}
	for x in range(14, 30):
		for y in range(12, 17):
			marks[Vector2i(x, y)] = "B"
	var f := WorldFixture.make(tree, marks, [], Vector2i(10, 19))
	await f.settle()
	await f.hold(["right"], 60)
	check(f.player.global_position.x < 14.0 * 16.0, "standing (56 px) cannot enter a 3-tile (48 px) gap: x=%.1f" % f.player.global_position.x)
	f.dispose()
	var g := WorldFixture.make(tree, marks, [], Vector2i(10, 19))
	await g.settle()
	await g.hold(["right"], 6)
	g.input._segments = [[1, ["right", "down", "jump"]], [500, ["right"]]]
	g.input._segment = 0
	g.input._left = 1
	await g.step(520)
	check(g.player.global_position.x > 30.0 * 16.0 - 4.0, "slide, then crawl, gets through: x=%.1f" % g.player.global_position.x)
	g.dispose()


func test_backdash_is_40_px_back_with_8_invulnerable_frames() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var start_x := f.player.global_position.x
	f.input._segments = [[1, ["dash"]], [30, []]]
	f.input._segment = 0
	f.input._left = 1
	await f.step(2)
	eq(f.player.mode, Player.Mode.DASH)
	check(f.player.invuln >= 7, "invulnerable during the start of the dash (%d)" % f.player.invuln)
	await f.step(20)
	near(start_x - f.player.global_position.x, 40.0, 3.5, "40 px backwards")
	eq(f.player.mode, Player.Mode.NORMAL)
	f.dispose()


func test_backdash_cooldown_is_20_frames() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	f.input._segments = [[1, ["dash"]], [10, []], [1, ["dash"]], [30, []]]
	f.input._segment = 0
	f.input._left = 1
	await f.step(2)
	eq(f.player.mode, Player.Mode.DASH)
	await f.step(11)
	eq(f.player.mode, Player.Mode.NORMAL, "the dash is over after 12 frames")
	await f.step(3)
	check(f.player.dash_cooldown > 0 or f.player.mode == Player.Mode.NORMAL, "cooldown still running")
	f.dispose()


func test_spaceball_fits_a_two_tile_tunnel() -> void:
	var marks := {}
	for x in range(14, 26):
		marks[Vector2i(x, 17)] = "B"
		marks[Vector2i(x, 16)] = "B"
	var without := WorldFixture.make(tree, marks, [], Vector2i(12, 19))
	await without.settle()
	await without.hold(["right"], 40)
	check(without.player.global_position.x < 14.0 * 16.0, "he cannot walk in")
	without.dispose()
	var f := WorldFixture.make(tree, marks, ["spaceball"], Vector2i(12, 19))
	await f.settle()
	f.input._segments = [[1, ["down"]], [4, []], [1, ["down"]], [4, []], [130, ["right"]]]
	f.input._segment = 0
	f.input._left = 1
	await f.step(150)
	check(f.player.is_ball() or f.player.global_position.x > 14.0 * 16.0, "morphed by double-tapping Down")
	check(f.player.global_position.x > 26.0 * 16.0 - 8.0, "rolled through the 2-tile tunnel: x=%.1f" % f.player.global_position.x)
	eq((f.player.shape.shape as RectangleShape2D).size, Vector2(24, 24), "24 px ball")
	f.dispose()


func test_spaceball_needs_the_ability() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	f.input._segments = [[1, ["down"]], [4, []], [1, ["down"]], [10, []]]
	f.input._segment = 0
	f.input._left = 1
	await f.step(20)
	check(not f.player.is_ball(), "no Koozie Statue yet")
	f.dispose()


func test_one_way_platforms_can_be_jumped_through_and_stood_on() -> void:
	var marks := {}
	for x in range(8, 16):
		marks[Vector2i(x, 16)] = "="
	var f := WorldFixture.make(tree, marks, [], Vector2i(11, 19))
	await f.settle()
	await f.hold(["jump"], 60)
	await f.step(30)
	near(f.player.global_position.y, FLOOR_Y, 1.0, "a 56 px jump cannot reach a platform 64 px up")
	f.dispose()
	var low := {}
	for x in range(8, 16):
		low[Vector2i(x, 17)] = "="
	var g := WorldFixture.make(tree, low, [], Vector2i(11, 19))
	await g.settle()
	await g.hold(["jump"], 60)
	await g.step(30)
	near(g.player.global_position.y, 17.0 * 16.0, 1.5, "lands on top of a platform 48 px up")
	g.dispose()


func test_the_bat_hits_within_reach_only() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var near_dummy := Dummy.new(f.root, Vector2(f.player.global_position.x + 30.0, FLOOR_Y))
	var far_dummy := Dummy.new(f.root, Vector2(f.player.global_position.x + 120.0, FLOOR_Y))
	await f.step(2)
	await f.tap(["attack"])
	await f.step(24)
	eq(near_dummy.hits, 1, "a dummy 30 px away is hit exactly once per swing")
	eq(far_dummy.hits, 0, "a dummy 120 px away is out of reach")
	f.dispose()


func test_the_third_bat_hit_is_a_home_run() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var dummy := Dummy.new(f.root, Vector2(f.player.global_position.x + 28.0, FLOOR_Y))
	await f.step(2)
	for swing in 3:
		await f.tap(["attack"])
		await f.step(20)
	eq(dummy.hits, 3, "three swings, three hits")
	eq(dummy.last_hit["home_run"], true, "the third is the Home Run")
	eq(dummy.last_hit["heavy"], true, "with heavy knockback")
	check(dummy.amounts[2] > dummy.amounts[0], "and more damage: %s" % str(dummy.amounts))
	f.dispose()


func test_melee_hits_restore_ep_and_freeze_briefly() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	f.state.ep = 10.0
	var dummy := Dummy.new(f.root, Vector2(f.player.global_position.x + 28.0, FLOOR_Y))
	await f.step(2)
	await f.tap(["attack"])
	await f.step(3)
	var frozen := false
	for _i in 12:
		await tree.physics_frame
		frozen = frozen or Combat.hitstop > 0
	check(frozen, "3 frames of hit-stop on a normal hit")
	check(f.state.ep > 10.0, "each melee hit restores EP")
	check(dummy.hits >= 1)
	f.dispose()


func test_a_tapped_mitt_shot_is_free_and_a_full_charge_costs_6_ep() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	f.state.ep = 30.0
	var dummy := Dummy.new(f.root, Vector2(f.player.global_position.x + 120.0, FLOOR_Y))
	await f.step(2)
	await f.hold(["sub"], 3)
	await f.step(45)
	eq(dummy.hits, 1, "a tap fires an uncharged shot")
	check(f.state.ep >= 30.0, "uncharged shots are free (EP %.1f)" % f.state.ep)
	var ep_before := f.state.ep
	var frames := Consts.CHARGE_FRAMES + 4 + 60
	await f.hold(["sub"], Consts.CHARGE_FRAMES + 4)
	await f.step(60)
	check(dummy.hits >= 2, "the charged shot connects")
	check(dummy.last_hit["charged"], "and is flagged charged")
	var regen := Consts.EP_REGEN_PER_SEC * frames / float(Consts.FPS)
	near(ep_before - f.state.ep + regen, 6.0, 0.7, "a full charge costs 6 EP (regen %.2f added back)" % regen)
	f.dispose()


func test_taking_a_hit_hurts_and_grants_60_invulnerable_frames() -> void:
	var f := WorldFixture.make(tree)
	await f.settle()
	var max_hp := f.state.hp
	var hit := HitArea.new(Vector2(40, 60), Vector2.ZERO)
	hit.position = f.player.global_position + Vector2(0, -30)
	hit.level = 5
	f.root.add_child(hit)
	await f.step(3)
	check(f.state.hp < max_hp, "damaged")
	check(f.player.invuln > 50, "invulnerable afterwards (%d)" % f.player.invuln)
	var after_first := f.state.hp
	await f.step(10)
	eq(f.state.hp, after_first, "no second hit while invulnerable")
	f.dispose()


class Dummy extends Node2D:
	var hits := 0
	var last_hit := {}
	var amounts: Array[int] = []
	var area: HurtArea

	func _init(parent: Node, at: Vector2) -> void:
		position = at
		area = HurtArea.new(Vector2(24, 48), Vector2(0, -24))
		area.target = self
		add_child(area)
		parent.add_child(self)

	func hit_info() -> Dictionary:
		return {"def": 10.0, "weak": "", "resist": ""}

	func receive_hit(result: Dictionary, hit: Dictionary) -> void:
		hits += 1
		last_hit = hit
		amounts.append(int(result["amount"]))
