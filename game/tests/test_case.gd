class_name TestCase
extends RefCounted
## Base class for tests. Test methods are named test_* and record results here.
## Failures do not abort a test: every failed check is reported at the end.

var failures: Array[String] = []
var checks := 0
var current := ""
var tree: SceneTree


func check(condition: bool, message: String = "") -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current, message])


func eq(actual: Variant, expected: Variant, message: String = "") -> void:
	checks += 1
	if not (actual == expected):
		failures.append("%s: %s expected %s, got %s" % [current, message, _show(expected), _show(actual)])


func near(actual: float, expected: float, eps: float, message: String = "") -> void:
	checks += 1
	if absf(actual - expected) > eps:
		failures.append("%s: %s expected %s +/- %s, got %s" % [current, message, str(expected), str(eps), str(actual)])


static func _show(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 240 else text.substr(0, 240) + "... (%d chars)" % text.length()
