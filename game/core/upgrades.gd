class_name Upgrades
extends RefCounted
## Gem upgrades at the upgrade bench (docs/design/progression-and-loot.md#upgrades).

const GEM_COST: Array[int] = [1, 3, 5, 8, 12]
const FEE_PER_ILVL := 25
const MAX_UPGRADES := 5


## Armor pieces and rings use armor gems; both weapon slots use weapon gems.
static func gem_kind(item: Dictionary) -> String:
	return "weapon" if item["slot"] in ["weapon", "sub"] else "armor"


## The cap follows the character's level, not the item.
static func cap_for_level(level: int) -> int:
	return mini(Stats.upgrade_cap(level), MAX_UPGRADES)


static func can_upgrade(item: Dictionary, level: int) -> bool:
	return int(item["upgrades"]) < cap_for_level(level)


static func gem_cost(item: Dictionary) -> int:
	return GEM_COST[mini(int(item["upgrades"]), GEM_COST.size() - 1)]


## Fee to go from +n to +(n+1): 25 x iLvl x (n + 1).
static func bucks_fee(item: Dictionary) -> int:
	return FEE_PER_ILVL * int(item["ilvl"]) * (int(item["upgrades"]) + 1)


static func error_for(item: Dictionary, level: int, gems: Dictionary, bucks: int) -> String:
	if not can_upgrade(item, level):
		return "Reach a higher level to upgrade further" if int(item["upgrades"]) < MAX_UPGRADES else "Maxed out"
	if int(gems.get(gem_kind(item), 0)) < gem_cost(item):
		return "Needs %d %s gems" % [gem_cost(item), gem_kind(item)]
	if bucks < bucks_fee(item):
		return "Needs %d Vetro-Bucks" % bucks_fee(item)
	return ""


## Applies one step in place: +10% base (+15% common), and raises the chosen affix by a step.
## Returns the gem cost. Rings and common items have nothing to raise unless affix_index is valid.
static func apply(item: Dictionary, affix_index: int = -1) -> int:
	var cost := gem_cost(item)
	if affix_index >= 0 and affix_index < item["affixes"].size():
		var entry: Dictionary = item["affixes"][affix_index]
		var def := Db.affix(entry["id"])
		entry["value"] = Items.round_value(def, float(entry["value"]) + Items.affix_step(def, int(entry["tier"])))
	item["upgrades"] = int(item["upgrades"]) + 1
	item["gems_spent"] = int(item["gems_spent"]) + cost
	return cost


static func salvage_refund(item: Dictionary) -> int:
	return floori(int(item["gems_spent"]) / 2.0)


## What the next step would do, for the bench UI.
static func preview(item: Dictionary, affix_index: int = -1) -> Dictionary:
	var out := {
		"value_now": Items.upgraded_value(item), "value_next": Items.upgraded_value(item, int(item["upgrades"]) + 1),
		"gems": gem_cost(item), "kind": gem_kind(item), "fee": bucks_fee(item), "affix_gain": 0.0,
	}
	if affix_index >= 0 and affix_index < item["affixes"].size():
		var entry: Dictionary = item["affixes"][affix_index]
		out["affix_gain"] = Items.affix_step(Db.affix(entry["id"]), int(entry["tier"]))
	return out
