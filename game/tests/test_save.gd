extends TestCase
## Save codec (schema 1, migration, validation) and slot files (atomic write, backup recovery).

const TEST_ROOT := "user://test_saves"


func _cleanup() -> void:
	for slot in SaveFiles.SLOTS:
		SaveFiles.delete(slot)


func _use_test_root() -> void:
	SaveFiles.root = TEST_ROOT
	_cleanup()


func _finish() -> void:
	_cleanup()
	SaveFiles.root = "user://saves"


func _rich_state() -> Dictionary:
	var state := SaveCodec.new_game("babby")
	state["player"]["level"] = 12
	state["player"]["xp"] = 345
	state["player"]["allocated"] = {"STR": 2}
	state["bucks"] = 987
	state["gems"]["armor"] = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var item := Loot.roll_gear(rng, 9, "rare", 12)
	item["uid"] = 1
	state["inventory"].append(item)
	state["equipped"]["weapon"] = item
	state["abilities"] = ["beam_bat", "mitt_cannon"]
	state["tallies"]["kills"]["space_bat"] = 33
	state["map"]["visited"] = ["0,1", "1,1"]
	state["world"]["bosses"]["krate"] = {"defeated": false, "hp_frac": 0.2}
	state["loot"]["counters"]["since_legendary"] = 7
	return state


func test_round_trip_preserves_everything() -> void:
	var state := _rich_state()
	var result := SaveCodec.decode(SaveCodec.encode(state))
	check(result["ok"], "decode ok: %s" % result["error"])
	eq(result["migrated_from"], SaveCodec.SCHEMA, "no migration needed")
	var decoded: Dictionary = result["state"]
	eq(decoded["player"]["level"], 12)
	eq(decoded["difficulty"], "babby")
	eq(decoded["inventory"][0]["name"], state["inventory"][0]["name"])
	eq(decoded["inventory"][0]["affixes"].size(), state["inventory"][0]["affixes"].size())
	eq(decoded["world"]["bosses"]["krate"]["hp_frac"], 0.2)
	eq(decoded["tallies"]["kills"]["space_bat"], 33)
	eq(decoded["loot"]["counters"]["since_legendary"], 7)
	eq(typeof(decoded["player"]["level"]), TYPE_INT, "integral numbers come back as ints")
	eq(SaveCodec.encode(SaveCodec.decode(SaveCodec.encode(decoded))["state"]), SaveCodec.encode(decoded), "encoding is stable and sorted after one round trip")


func test_migrates_the_schema_0_fixture() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v0.json")
	check(text != "", "fixture exists")
	var result := SaveCodec.decode(text)
	check(result["ok"], "migrates: %s" % result["error"])
	eq(result["migrated_from"], 0)
	var state: Dictionary = result["state"]
	eq(state["schema"], SaveCodec.SCHEMA)
	eq(state["player"]["level"], 3)
	eq(state["player"]["xp"], 120)
	eq(state["bucks"], 44)
	eq(state["abilities"], ["beam_bat", "mitt_cannon"])
	eq(state["map"]["visited"], ["0,1", "1,1", "2,1"])
	eq(state["checkpoint"]["room"], "crash_2")
	eq(state["inventory"].size(), 2, "the unknown 'sandwich' item is dropped")
	eq(state["inventory"][0]["name"], "Foam Bat")
	eq(state["inventory"][1]["family"], "boots")
	eq(state["inventory"][1]["rarity"], "magic")
	eq(state["loot"]["next_uid"], 3, "uids continue after migrated items")
	check(state.has("tallies") and state.has("world"), "new sections get defaults")


func test_partial_saves_are_filled_with_defaults() -> void:
	var result := SaveCodec.decode('{"schema": 1, "player": {"level": 7}}')
	check(result["ok"])
	var state: Dictionary = result["state"]
	eq(state["player"]["level"], 7)
	eq(state["player"]["xp"], 0, "missing keys come from the defaults")
	eq(state["gems"], {"armor": 0, "weapon": 0})
	eq(state["checkpoint"]["room"], "crash_1")


func test_bad_saves_are_rejected_with_a_reason() -> void:
	check(not SaveCodec.decode("not json")["ok"])
	check(not SaveCodec.decode("[1, 2]")["ok"], "a list is not a save")
	var newer := SaveCodec.decode('{"schema": 99}')
	check(not newer["ok"] and "newer" in newer["error"], "newer schema: %s" % newer["error"])
	var level := SaveCodec.decode('{"schema": 1, "player": {"level": 51}}')
	check(not level["ok"] and "out of range" in level["error"], "level range: %s" % level["error"])
	var money := SaveCodec.decode('{"schema": 1, "bucks": -5}')
	check(not money["ok"], "negative money")
	var broken := SaveCodec.decode('{"schema": 1, "inventory": [{"slot": "boots"}]}')
	check(not broken["ok"] and "missing" in broken["error"], "item missing fields: %s" % broken["error"])


func test_slot_files_write_and_read_back() -> void:
	_use_test_root()
	var state := _rich_state()
	eq(SaveFiles.write(1, state), OK)
	check(SaveFiles.exists(1))
	var result := SaveFiles.read(1)
	check(result["ok"] and not result["recovered"])
	eq(result["state"]["player"]["level"], 12)
	eq(SaveFiles.write(1, state), OK, "overwriting works")
	eq(SaveFiles.write(1, state), OK, "and again")
	check(not FileAccess.file_exists(SaveFiles.path(1) + ".tmp"), "no temp file left behind")
	check(not FileAccess.file_exists(SaveFiles.path(1) + ".bak"), "no backup left behind after a good write")
	var summary := SaveFiles.summary(1)
	eq(summary["level"], 12)
	eq(summary["cells"], 2)
	eq(SaveFiles.summary(2), {}, "empty slots have no summary")
	_finish()


func test_a_corrupt_save_recovers_from_the_backup() -> void:
	_use_test_root()
	var state := _rich_state()
	SaveFiles.write(2, state)
	var good := FileAccess.get_file_as_string(SaveFiles.path(2))
	var backup := FileAccess.open(SaveFiles.path(2) + ".bak", FileAccess.WRITE)
	backup.store_string(good)
	backup.close()
	var main := FileAccess.open(SaveFiles.path(2), FileAccess.WRITE)
	main.store_string('{"schema": 1, "player": {"lev')
	main.close()
	var result := SaveFiles.read(2)
	check(result["ok"], "recovered: %s" % result["error"])
	check(result["recovered"], "flagged as recovered")
	eq(result["state"]["player"]["level"], 12)
	_finish()


func test_an_interrupted_write_leaves_the_old_save_intact() -> void:
	_use_test_root()
	SaveFiles.write(1, _rich_state())
	var stray := FileAccess.open(SaveFiles.path(1) + ".tmp", FileAccess.WRITE)
	stray.store_string("half a save")
	stray.close()
	var result := SaveFiles.read(1)
	check(result["ok"] and not result["recovered"], "the .tmp file is ignored")
	eq(SaveFiles.write(1, _rich_state()), OK, "the next write replaces the stray temp file")
	_finish()


func test_missing_and_deleted_slots() -> void:
	_use_test_root()
	var missing := SaveFiles.read(3)
	check(not missing["ok"])
	SaveFiles.write(3, SaveCodec.new_game())
	check(SaveFiles.exists(3))
	SaveFiles.delete(3)
	check(not SaveFiles.exists(3), "deleted")
	_finish()
