class_name Combat
extends RefCounted
## Damage resolution between Sleve and enemies (docs/design/player-and-combat.md#damage-model).

## Global freeze in physics frames. Actors return early while it is above zero; the World counts it down.
static var hitstop := 0


static func freeze(frames: int) -> void:
	hitstop = maxi(hitstop, frames + 1)


## What Sleve deals. Returns {amount, crit, weak, resist}. melee uses ATK, otherwise the sub-weapon ATK.
## variance < 0 rolls the usual 0.95-1.05.
static func player_hit(state: GameState, target_def: float, move_mult: float, target: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var d := state.derived
	var melee := String(options.get("kind", "melee")) == "melee"
	var atk := float(d["atk"]) if melee else float(d["sub_atk"])
	atk *= float(options.get("extra_mult", 1.0))
	if "leeroy" in d["powers"]:
		atk *= Powers.leeroy_mult(state.hp / float(d["max_hp"]))
	var variance := float(options.get("variance", -1.0))
	if variance < 0.0:
		variance = state.rng.randf_range(0.95, 1.05)
	var amount := Damage.hit(atk, move_mult, target_def, variance)
	var chance := float(d["crit_chance"]) + float(options.get("crit_bonus", 0.0))
	var crit := bool(options.get("force_crit", false)) or state.rng.randf() * 100.0 < chance
	if crit:
		amount = roundi(amount * float(d["crit_damage"]))
	var weak := false
	var resist := false
	var elemental := 0.0
	for element: String in Gear.ELEMENTS:
		var bonus := float(d["dmg"][element])
		if bonus <= 0.0:
			continue
		var mult := 1.0
		if String(target.get("weak", "")) == element:
			mult = Damage.element_mult("weak")
			weak = true
		elif String(target.get("resist", "")) == element:
			mult = Damage.element_mult("resist")
			resist = true
		elemental += bonus * mult
	amount += roundi(elemental)
	return {"amount": maxi(1, amount), "crit": crit, "weak": weak, "resist": resist}


## What an enemy attack deals to Sleve, after difficulty and elemental resistance.
static func enemy_hit(state: GameState, enemy_level: int, mult: float, element: String = "") -> int:
	var d := state.derived
	var amount := float(Damage.hit(Damage.enemy_atk(enemy_level, mult), 1.0, float(d["def"]), 1.0))
	amount *= float(state.mode()["damage_taken"])
	if element != "" and d["resist"].has(element):
		amount *= 1.0 - minf(75.0, float(d["resist"][element])) / 100.0
	return maxi(1, roundi(amount))
