class_name Tallies
extends RefCounted
## Kill Tallies (docs/design/bestiary.md#kill-tallies). State is plain data so it saves as JSON:
## {kills:{enemy_id:int}, completed:[perk_id], mirror_completed:[perk_id], knacks:[perk_id], seen:[enemy_id]}
## A perk never grants traversal or opens a gate.

static var threshold_override := 0


static func new_state() -> Dictionary:
	return {"kills": {}, "completed": [], "mirror_completed": [], "knacks": [], "seen": []}


static func threshold(enemy_id: String, mirror: bool = false) -> int:
	if threshold_override > 0:
		return threshold_override
	var perks := Db.perks()
	var tier: String = Db.enemy(enemy_id).get("tier", "fodder")
	var need := int(perks["thresholds"][tier])
	if mirror:
		need = maxi(1, ceili(need / float(perks["mirror_divisor"])))
	return need


static func perk_for(enemy_id: String) -> String:
	return Db.enemy(enemy_id).get("perk", "")


static func perk_def(perk_id: String) -> Dictionary:
	return Db.perks()["perks"].get(perk_id, {})


static func kills(state: Dictionary, enemy_id: String) -> int:
	return int(state["kills"].get(enemy_id, 0))


static func progress(state: Dictionary, enemy_id: String) -> Dictionary:
	var need := threshold(enemy_id)
	var count := kills(state, enemy_id)
	var pct := mini(100, floori(count * 100.0 / need))
	return {
		"kills": count, "threshold": need, "pct": pct,
		"seen": enemy_id in state["seen"],
		"revealed": pct >= int(Db.perks()["reveal_pct"]),
		"rival": pct >= int(Db.perks()["rival_pct"]),
		"complete": count >= need,
	}


## Registers a kill and returns the milestone events it triggered:
## "first_kill", "revealed", "rival", "complete".
static func add_kill(state: Dictionary, enemy_id: String) -> Array[String]:
	var events: Array[String] = []
	var before := progress(state, enemy_id)
	if not before["seen"]:
		state["seen"].append(enemy_id)
		events.append("first_kill")
	if before["complete"]:
		return events
	state["kills"][enemy_id] = kills(state, enemy_id) + 1
	var after := progress(state, enemy_id)
	if after["revealed"] and not before["revealed"]:
		events.append("revealed")
	if after["rival"] and not before["rival"]:
		events.append("rival")
	if after["complete"]:
		events.append("complete")
		var perk := perk_for(enemy_id)
		if perk != "" and perk not in state["completed"]:
			state["completed"].append(perk)
	return events


static func is_first_kill(state: Dictionary, enemy_id: String) -> bool:
	return enemy_id not in state["seen"]


static func has_perk(state: Dictionary, perk_id: String) -> bool:
	return perk_id in state["completed"]


## 1 normally, 2 (the EX version) once the Ainamortev mirror variant's tally is complete.
static func perk_level(state: Dictionary, perk_id: String) -> int:
	return 2 if perk_id in state["mirror_completed"] else 1


static func rival_active(state: Dictionary, enemy_id: String) -> bool:
	return bool(progress(state, enemy_id)["rival"])


static func knack_slots(state: Dictionary) -> int:
	var config: Dictionary = Db.perks()["knack_slots"]
	var slots := int(config["start"])
	for need: float in config["unlock_at_completed"]:
		if state["completed"].size() >= int(need):
			slots += 1
	return slots


static func equip_knack(state: Dictionary, perk_id: String) -> bool:
	var def := perk_def(perk_id)
	if def.is_empty() or def["type"] != "knack" or not has_perk(state, perk_id):
		return false
	if perk_id in state["knacks"]:
		return true
	if state["knacks"].size() >= knack_slots(state):
		return false
	state["knacks"].append(perk_id)
	return true


static func unequip_knack(state: Dictionary, perk_id: String) -> void:
	state["knacks"].erase(perk_id)


## Stat bonuses from completed trait perks, e.g. {"INT": 2}. Caps live in perks.json trait_caps.
static func trait_stats(state: Dictionary) -> Dictionary:
	var out := {}
	for perk_id: String in state["completed"]:
		var def := perk_def(perk_id)
		if def.is_empty() or def["type"] != "trait" or not def.has("stats"):
			continue
		var stats: Dictionary = def["stats"][perk_level(state, perk_id) - 1]
		for stat: String in stats:
			out[stat] = int(out.get(stat, 0)) + int(stats[stat])
	return out


static func label(state: Dictionary, enemy_id: String) -> String:
	var p := progress(state, enemy_id)
	var def := Db.enemy(enemy_id)
	var perk := perk_def(perk_for(enemy_id))
	return "%s TALLY %d/%d - %d MORE: %s" % [String(def["name"]).to_upper(), p["kills"], p["threshold"], maxi(0, p["threshold"] - p["kills"]), String(perk.get("name", "?")).to_upper()]
