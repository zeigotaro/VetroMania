extends SceneTree
## Monte Carlo loot simulator. It drives the real Loot code, so tuning changes can be checked against real numbers:
##   python tools/godot.py script res://tests/loot_sim.gd -- --kills=200000 --level=30 --source=fodder --luck=0 --seed=1
## Options: --kills, --level (enemy level), --player-level, --source (fodder|elite|boss|chest), --luck, --seed, --rival.
## Prints the drop mix, the rarity mix of gear, gem packs, and the longest stretch without a legendary.

const RARITY_ORDER := ["common", "magic", "rare", "set", "legendary"]


func _initialize() -> void:
	var options := _parse(OS.get_cmdline_user_args())
	var kills := int(options.get("kills", "100000"))
	var level := int(options.get("level", "20"))
	var source := String(options.get("source", "fodder"))
	if source not in ["fodder", "elite", "boss", "chest"]:
		printerr("unknown --source ", source)
		quit(2)
		return
	var luck := float(options.get("luck", "0"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", "1"))
	var legendary := Db.legendary_data()
	var ctx := {
		"source": source, "level": level, "player_level": int(options.get("player-level", str(level))), "luck": luck,
		"counters": Loot.new_counters(), "pools": {"legendary": legendary["legendaries"], "set": legendary["sets"]},
		"rival": options.has("rival"),
	}
	var by_type := {}
	var by_rarity := {}
	var gems := {}
	var bucks := 0
	var gear_drops := 0
	var legendary_drops := 0
	var dry := 0
	var longest_dry := 0
	for _kill in kills:
		var got_legendary := false
		for drop: Dictionary in Loot.roll_drops(rng, ctx):
			by_type[drop["type"]] = int(by_type.get(drop["type"], 0)) + 1
			match drop["type"]:
				"bucks":
					bucks += int(drop["amount"])
				"gem":
					var key := "%s %s x%d" % [drop["color"], drop["kind"], int(drop["count"])]
					gems[key] = int(gems.get(key, 0)) + 1
				"gear":
					gear_drops += 1
					var rarity: String = drop["item"]["rarity"]
					by_rarity[rarity] = int(by_rarity.get(rarity, 0)) + 1
					if rarity == "legendary":
						legendary_drops += 1
						got_legendary = true
		dry = 0 if got_legendary else dry + 1
		longest_dry = maxi(longest_dry, dry)
	print("LOOT SIM: %d %s kills, enemy Lv %d, Loot Luck %s, seed %s" % [kills, source, level, str(luck), options.get("seed", "1")])
	print("drops per kill by type:")
	for key: String in by_type:
		print("  %-11s %8.4f" % [key, float(by_type[key]) / kills])
	print("gear by rarity (%d pieces):" % gear_drops)
	for rarity in RARITY_ORDER:
		var count := int(by_rarity.get(rarity, 0))
		print("  %-11s %7.2f%%  (%d)" % [rarity, 100.0 * count / maxf(1.0, gear_drops), count])
	print("gem packs:")
	var keys := gems.keys()
	keys.sort()
	for key: String in keys:
		print("  %-16s %d" % [key, gems[key]])
	print("bucks per kill: %.2f" % (float(bucks) / kills))
	print("legendaries: %d (one per %.0f kills), longest dry spell %d kills" % [legendary_drops, float(kills) / maxf(1.0, legendary_drops), longest_dry])
	quit(0)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in args:
		if arg.begins_with("--"):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			out[pair[0]] = pair[1] if pair.size() > 1 else "1"
	return out
