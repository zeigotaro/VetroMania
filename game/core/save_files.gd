class_name SaveFiles
extends RefCounted
## Slot files under user://saves. Writes go to a temp file, are verified by decoding, then swapped in
## with the previous save kept as .bak until the swap succeeds. A missing or corrupt slot falls back to .bak.

const SLOTS := 3

static var root := "user://saves"


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [root, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot) + ".bak")


static func write(slot: int, state: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(root)
	var final := path(slot)
	var tmp := final + ".tmp"
	var bak := final + ".bak"
	var text := SaveCodec.encode(state)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if not SaveCodec.decode(FileAccess.get_file_as_string(tmp))["ok"]:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	var had_previous := FileAccess.file_exists(final)
	if had_previous:
		var moved := DirAccess.rename_absolute(final, bak)
		if moved != OK:
			DirAccess.remove_absolute(tmp)
			return moved
	var swapped := DirAccess.rename_absolute(tmp, final)
	if swapped != OK:
		if had_previous:
			DirAccess.rename_absolute(bak, final)
		return swapped
	if had_previous:
		DirAccess.remove_absolute(bak)
	return OK


## Returns {ok, state, error, migrated_from, recovered}.
static func read(slot: int) -> Dictionary:
	var result := _read_file(path(slot))
	if result["ok"]:
		result["recovered"] = false
		return result
	var backup := _read_file(path(slot) + ".bak")
	if backup["ok"]:
		backup["recovered"] = true
		return backup
	result["recovered"] = false
	return result


static func _read_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "state": {}, "error": "No save in this slot", "migrated_from": -1}
	return SaveCodec.decode(FileAccess.get_file_as_string(file_path))


static func delete(slot: int) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path(slot) + suffix):
			DirAccess.remove_absolute(path(slot) + suffix)


## Title-screen summary of a slot, or an empty dictionary.
static func summary(slot: int) -> Dictionary:
	var result := read(slot)
	if not result["ok"]:
		return {}
	var state: Dictionary = result["state"]
	return {
		"level": state["player"]["level"], "playtime": state["playtime"], "saved_at": state["saved_at"],
		"room": state["checkpoint"]["room"], "cells": state["map"]["visited"].size(),
		"difficulty": state["difficulty"], "recovered": result["recovered"],
	}
