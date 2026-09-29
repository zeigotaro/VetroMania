class_name Stats
extends RefCounted
## XP curve, stat growth, and derived stats (docs/design/progression-and-loot.md#leveling).

const NAMES: Array[String] = ["STR", "CON", "INT", "DEX", "LCK"]
const BASE := {"STR": 8, "CON": 7, "INT": 6, "DEX": 7, "LCK": 5}
## Growth per level in hundredths, so floor() stays exact.
const GROWTH_PCT := {"STR": 90, "CON": 80, "INT": 50, "DEX": 70, "LCK": 35}


static func xp_to_next(level: int) -> int:
	if level >= Consts.LEVEL_CAP:
		return 0
	return roundi(20.0 * pow(float(level), 2.2) + 75.0)


static func total_xp_to_reach(level: int) -> int:
	var total := 0
	for l in range(1, level):
		total += xp_to_next(l)
	return total


static func enemy_xp(enemy_level: int) -> int:
	var e := float(enemy_level)
	return roundi(4.0 + 3.0 * e + 0.15 * e * e)


## Level difference multiplier: +5 or more x1.5, -6 or less x0.1, otherwise 1 + 0.1 d.
static func xp_level_factor(enemy_level: int, player_level: int) -> float:
	var d := enemy_level - player_level
	if d >= 5:
		return 1.5
	if d <= -6:
		return 0.1
	return 1.0 + 0.1 * d


static func base_stat(stat: String, level: int) -> int:
	return int(BASE[stat]) + floori(int(GROWTH_PCT[stat]) * (level - 1) / 100.0)


## Free stat points earned by reaching a level (Training Montage every 5 levels).
static func montage_points(level: int) -> int:
	return floori(level / float(Consts.TRAINING_MONTAGE_EVERY)) * Consts.TRAINING_MONTAGE_POINTS


## Final stats: base growth + allocated Montage points + gear bonuses.
static func final_stats(level: int, allocated: Dictionary, gear: Dictionary) -> Dictionary:
	var out := {}
	for stat: String in NAMES:
		out[stat] = base_stat(stat, level) + int(allocated.get(stat, 0)) + int(gear.get(stat, 0))
	return out


static func max_hp(con: int, level: int, bonus: int = 0) -> int:
	return 40 + 10 * con + 3 * level + bonus


static func max_ep(int_stat: int, level: int, bonus: int = 0) -> int:
	return 20 + 2 * int_stat + level + bonus


## Crit chance in percent: 3% + DEX / 8, plus gear.
static func crit_chance(dex: int, bonus: float = 0.0) -> float:
	return 3.0 + dex / 8.0 + bonus


## Loot Luck in percent: floor(2/3 LCK), plus gear.
static func loot_luck(lck: int, bonus: float = 0.0) -> float:
	return floorf(lck * 2.0 / 3.0) + bonus


static func upgrade_cap(level: int) -> int:
	if level >= Consts.LEVEL_CAP:
		return 5
	return mini(4, 1 + floori((level - 1) / 12.0))
