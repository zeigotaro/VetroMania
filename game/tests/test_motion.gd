extends TestCase
## Jump heights are the contract in docs/design/player-and-combat.md: hold 56 px, tap 24 px.


func test_full_hold_jump_reaches_56_px() -> void:
	near(Motion.rise(Motion.jump_v0()), Consts.JUMP_HEIGHT, 0.5, "full hold apex")


func test_tap_jump_reaches_about_24_px() -> void:
	near(Motion.rise(Motion.jump_v0(), 1), 24.0, 1.0, "1-frame tap")
	near(Motion.rise(Motion.jump_v0(), 3), 24.0, 1.0, "3-frame tap is the same as a tap")


func test_jump_height_grows_with_hold_time() -> void:
	var previous := 0.0
	for hold in [1, 5, 8, 12, 20, 100]:
		var height := Motion.rise(Motion.jump_v0(), hold)
		check(height >= previous, "height should not shrink at hold %d" % hold)
		previous = height


func test_double_jump_and_wall_kick_heights() -> void:
	near(Motion.rise(Motion.double_jump_v0(), 100000, 1.0), 40.0, 0.5, "double jump")
	near(Motion.rise(Motion.wall_kick_v0(), 100000, 1.0), 48.0, 0.5, "wall kick")


func test_launch_velocity_is_sane() -> void:
	near(Motion.jump_v0(), 329.1, 0.5, "v0 from the calibration run")
	check(Motion.jump_v0() > Motion.wall_kick_v0(), "jump beats wall kick")
	check(Motion.wall_kick_v0() > Motion.double_jump_v0(), "wall kick beats double jump")


func test_run_acceleration_and_deceleration_frames() -> void:
	var vx := 0.0
	for frame in Consts.ACCEL_FRAMES:
		vx = Motion.run_step(vx, 1.0)
	near(vx, Consts.RUN_SPEED, 0.001, "full speed after %d frames" % Consts.ACCEL_FRAMES)
	for frame in Consts.DECEL_FRAMES:
		vx = Motion.run_step(vx, 0.0)
	near(vx, 0.0, 0.001, "stopped after %d frames" % Consts.DECEL_FRAMES)


func test_turning_uses_the_short_deceleration() -> void:
	var vx := Motion.run_step(Consts.RUN_SPEED, -1.0)
	near(vx, Consts.RUN_SPEED - Consts.RUN_SPEED / Consts.DECEL_FRAMES, 0.001)


func test_gravity_is_lighter_at_the_apex_and_capped_when_falling() -> void:
	check(Motion.gravity_for(-20.0) < Motion.gravity_for(-100.0), "apex hang")
	check(Motion.gravity_for(200.0) > Motion.gravity_for(-200.0), "falls faster than it rises")
	var vy := 0.0
	for i in 300:
		vy = Motion.fall_step(vy)
	near(vy, Consts.TERMINAL_SPEED, 0.001, "terminal velocity")
