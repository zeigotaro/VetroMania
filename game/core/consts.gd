class_name Consts
extends RefCounted
## Numbers from docs/design/*. Pure data: every value here traces to a design doc.

const TILE := 16
const CELL_TILES := Vector2i(40, 23)
const CELL_PX := Vector2i(640, 368)
const VIEW := Vector2i(640, 360)
const FPS := 60
const DT := 1.0 / 60.0

const LEVEL_CAP := 50
const RING_SLOT_LEVELS: Array[int] = [20, 37]
const RING_DROP_MIN_LEVEL := 20
const TRAINING_MONTAGE_EVERY := 5
const TRAINING_MONTAGE_POINTS := 2

const SLOTS: Array[String] = [
	"helmet", "chest", "gauntlets", "gloves", "leggings", "boots", "ring1", "ring2", "weapon", "sub",
]
const ARMOR_SLOTS: Array[String] = ["helmet", "chest", "gauntlets", "gloves", "leggings", "boots"]
const RARITIES: Array[String] = ["common", "magic", "rare", "set", "legendary"]

## Rarity display colors, shared by the HUD, the tooltip and the loot beams.
const RARITY_COLORS := {
	"common": Color("d8d8e0"), "magic": Color("4f86ff"), "rare": Color("ffd23a"),
	"legendary": Color("ff8a1c"), "set": Color("3fe07a"),
}

## Bosses have 20x fodder HP at their level; final bosses 30x.
const BOSS_HP_MULT := 20.0
const FINAL_BOSS_HP_MULT := 30.0
const ELITE_HP_MULT := 3.0
const ELITE_LEVEL_BONUS := 2

## Fixed physics numbers at 60 Hz (docs/design/player-and-combat.md).
const RUN_SPEED := 150.0
const ACCEL_FRAMES := 4
const DECEL_FRAMES := 3
const GRAVITY_UP := 1030.0
const GRAVITY_DOWN := 1440.0
const TERMINAL_SPEED := 420.0
const APEX_SPEED := 40.0
const APEX_GRAVITY_MULT := 0.5
const COYOTE_FRAMES := 6
const BUFFER_FRAMES := 6
const JUMP_HEIGHT := 56.0
const JUMP_CUT := 0.43
const JUMP_CUT_MIN_FRAMES := 3
const DOUBLE_JUMP_HEIGHT := 40.0
const WALL_KICK_HEIGHT := 48.0
const WALL_KICK_PUSH_SPEED := 160.0
const WALL_KICK_PUSH_FRAMES := 12
const WALL_SLIDE_SPEED := 60.0
const SLIDE_DISTANCE := 48.0
const SLIDE_FRAMES := 15
const BACKDASH_DISTANCE := 40.0
const BACKDASH_FRAMES := 12
const BACKDASH_INVULN_FRAMES := 8
const BACKDASH_COOLDOWN_FRAMES := 20
const HURT_INVULN_FRAMES := 60
const BALL_SPEED := 130.0
const HITSTOP_NORMAL := 3
const HITSTOP_HEAVY := 6
const EP_REGEN_PER_SEC := 1.5
const EP_PER_MELEE_HIT := 1.0
const CHARGE_FRAMES := 48
const CHARGED_SHOT_EP := 6.0
