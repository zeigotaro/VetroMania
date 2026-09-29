extends SceneTree
## Headless test runner.
##   godot --headless --path game --script res://tests/run_tests.gd [-- --filter=name]
## Runs every test_*.gd under res://tests. Exit code 1 if any check fails.

const TEST_DIR := "res://tests"


func _initialize() -> void:
	_run()


func _run() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var total_checks := 0
	var failed: Array[String] = []
	var suites := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR))
	files.sort()
	for file: String in files:
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		if filter != "" and not file.contains(filter):
			continue
		var script: GDScript = load("%s/%s" % [TEST_DIR, file])
		if script == null:
			failed.append("%s: failed to load" % file)
			continue
		var suite: TestCase = script.new()
		suite.tree = self
		suites += 1
		var methods: Array[String] = []
		for info in script.get_script_method_list():
			if String(info["name"]).begins_with("test_"):
				methods.append(info["name"])
		methods.sort()
		for method in methods:
			suite.current = "%s::%s" % [file.get_basename(), method]
			await suite.call(method)
		total_checks += suite.checks
		failed.append_array(suite.failures)
	if failed.is_empty():
		print("OK: %d suites, %d checks passed" % [suites, total_checks])
		quit(0)
	else:
		for message in failed:
			printerr("FAIL ", message)
		printerr("FAILED: %d of %d checks in %d suites" % [failed.size(), total_checks, suites])
		quit(1)
