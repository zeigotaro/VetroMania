extends SceneTree
## Loads every GDScript file under res:// so parse and type errors fail loudly instead of hiding until a
## scene happens to use the script. Run through tools/godot.py, which also fails on engine error lines.


func _init() -> void:
	var failures: Array[String] = []
	var count := 0
	for path in _scripts("res://"):
		count += 1
		var script: Variant = load(path)
		if script == null or (script is Script and not (script as Script).can_instantiate()):
			failures.append(path)
	if failures.is_empty():
		print("OK: %d scripts compile" % count)
		quit(0)
	else:
		for path in failures:
			printerr("COMPILE FAILED: ", path)
		quit(1)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_directories_at(dir):
		if entry.begins_with(".") or entry == "assets":
			continue
		out.append_array(_scripts(dir.path_join(entry)))
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".gd"):
			out.append(dir.path_join(file_name))
	return out
