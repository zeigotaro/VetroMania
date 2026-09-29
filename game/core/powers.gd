class_name Powers
extends RefCounted
## Legendary powers that reduce to pure math. Powers that need the world (Bobson, Cardboard Box,
## Power Glove of Badness) are read from Gear totals by the systems that use them.

const LEEROY_THRESHOLD := 0.2
const LEEROY_BONUS := 0.3
const BOBSON_DAMAGE := 0.5
const CARDBOARD_STILL_FRAMES := 120
const POWER_GLOVE_EP := 2.0


## Mullet of Theseus: +1 to every stat per 10 levels.
static func mullet_bonus(level: int) -> int:
	return floori(level / 10.0)


## Leeroy's Last Stand: +30% damage below 20% HP.
static func leeroy_mult(hp_fraction: float) -> float:
	return 1.0 + LEEROY_BONUS if hp_fraction < LEEROY_THRESHOLD else 1.0
