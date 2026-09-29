class_name Motion
extends RefCounted
## Movement math shared by the Player, the tests and the level solver
## (docs/design/player-and-combat.md#movement). Pure functions, 60 Hz fixed step.
##
## Order of operations per physics frame, mirrored by Player._physics_process:
##   jump frame: velocity = -v0, then move. Any other frame: gravity, optional jump cut, then move.

static var _velocity_cache := {}


static func gravity_for(vy: float) -> float:
	var g := Consts.GRAVITY_UP if vy < 0.0 else Consts.GRAVITY_DOWN
	if absf(vy) < Consts.APEX_SPEED:
		g *= Consts.APEX_GRAVITY_MULT
	return g


static func fall_step(vy: float) -> float:
	return minf(vy + gravity_for(vy) * Consts.DT, Consts.TERMINAL_SPEED)


## Horizontal velocity for the next frame. Releasing or reversing uses the short deceleration.
static func run_step(vx: float, direction: float) -> float:
	var turning := direction != 0.0 and vx != 0.0 and signf(vx) != signf(direction)
	var frames := Consts.DECEL_FRAMES if direction == 0.0 or turning else Consts.ACCEL_FRAMES
	return move_toward(vx, direction * Consts.RUN_SPEED, Consts.RUN_SPEED / frames)


## Apex rise in pixels for a jump launched at v0. The button is held for hold_frames frames
## (counting the jump frame); a release at or after JUMP_CUT_MIN_FRAMES multiplies the rising
## velocity by cut once. Pass cut = 1.0 for jumps that are not variable height.
static func rise(v0: float, hold_frames: int = 100000, cut: float = Consts.JUMP_CUT) -> float:
	var vy := -v0
	var y := vy * Consts.DT
	var best := -y
	var cut_applied := false
	var frame := 1
	while frame < 600:
		var held := frame < hold_frames
		vy = fall_step(vy)
		if vy < 0.0 and not held and frame >= Consts.JUMP_CUT_MIN_FRAMES and not cut_applied:
			vy *= cut
			cut_applied = true
		y += vy * Consts.DT
		best = maxf(best, -y)
		if vy > 0.0:
			break
		frame += 1
	return best


## Launch speed (positive number, upward) whose full-hold apex is exactly height pixels.
static func velocity_for_height(height: float) -> float:
	if _velocity_cache.has(height):
		return _velocity_cache[height]
	var lo := 50.0
	var hi := 900.0
	for _i in 60:
		var mid := (lo + hi) * 0.5
		if rise(mid, 100000, 1.0) < height:
			lo = mid
		else:
			hi = mid
	var v0 := (lo + hi) * 0.5
	_velocity_cache[height] = v0
	return v0


static func jump_v0() -> float:
	return velocity_for_height(Consts.JUMP_HEIGHT)


static func double_jump_v0() -> float:
	return velocity_for_height(Consts.DOUBLE_JUMP_HEIGHT)


static func wall_kick_v0() -> float:
	return velocity_for_height(Consts.WALL_KICK_HEIGHT)


## Frames spent moving up after a full-hold jump, useful for horizontal reach estimates.
static func airtime_frames(v0: float, drop: float = 0.0) -> int:
	var vy := -v0
	var y := vy * Consts.DT
	var frames := 1
	while frames < 600:
		vy = fall_step(vy)
		y += vy * Consts.DT
		frames += 1
		if vy > 0.0 and y >= drop:
			break
	return frames
