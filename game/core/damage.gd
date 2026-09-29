class_name Damage
extends RefCounted
## Damage formulas and enemy scaling (docs/design/player-and-combat.md#damage-model).

const TIER_HP := {"fodder": 50.0, "sturdy": 90.0, "elite": 150.0, "rare": 60.0}
const CRIT_MULT := 1.75
const WEAKNESS_MULT := 1.5
const RESIST_MULT := 0.5


static func melee_atk(weapon_damage: int, strength: int) -> int:
	return weapon_damage + floori(1.25 * strength)


static func sub_atk(weapon_damage: int, dexterity: int, intelligence: int) -> int:
	return weapon_damage + floori(0.75 * dexterity + 0.5 * intelligence)


static func defense(constitution: int, armor_total: int) -> int:
	return floori(constitution / 2.0) + floori(armor_total / 5.0)


## Hit damage: ATK x move multiplier x 100 / (100 + DEF) x variance, at least 1.
static func hit(atk: float, move_mult: float, target_def: float, variance: float = 1.0) -> int:
	return maxi(1, roundi(atk * move_mult * 100.0 / (100.0 + target_def) * variance))


static func element_mult(kind: String) -> float:
	match kind:
		"weak":
			return WEAKNESS_MULT
		"resist":
			return RESIST_MULT
		"immune":
			return 0.0
	return 1.0


static func enemy_hp(tier: String, level: int, elite: bool = false) -> int:
	var hp: float = TIER_HP[tier] * (1.0 + 0.14 * (level - 1))
	if elite:
		hp *= Consts.ELITE_HP_MULT
	return roundi(hp)


static func boss_hp(level: int, final_boss: bool = false) -> int:
	var mult := Consts.FINAL_BOSS_HP_MULT if final_boss else Consts.BOSS_HP_MULT
	return roundi(TIER_HP["fodder"] * (1.0 + 0.14 * (level - 1)) * mult)


static func enemy_atk(level: int, attack_mult: float = 1.0) -> float:
	return (12.0 + 2.2 * level) * attack_mult


static func enemy_def(level: int) -> float:
	return 5.0 + 1.5 * level
