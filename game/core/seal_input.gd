class_name SealInput
extends RefCounted
## Autograph Seal motions (docs/design/player-and-combat.md#autograph-seals). Fighting-game style:
## the recent direction changes must end with the required sequence, then a button. Diagonals
## are lenient: a d-pad that skips the diagonal still counts.
##   var seal := SealInput.new(["D", "DF", "F", "A"], 180)
##   each frame: if seal.advance(Vector2i(x, y), facing, attack_pressed): success
## Direction tokens are relative to facing: F forward, B back, U up, D down, DF, DB, UF, UB.

const DIAGONALS: Array[String] = ["DF", "DB", "UF", "UB"]

var sequence: Array[String] = []
var window_frames := 180
var assist := false
var frame := 0

var _events: Array = []
var _last_direction := ""


func _init(tokens: Array[String] = [], window: int = 180, assist_mode: bool = false) -> void:
	sequence = tokens
	window_frames = window
	assist = assist_mode


func reset() -> void:
	_events.clear()
	_last_direction = ""
	frame = 0


static func direction_token(direction: Vector2i, facing: int) -> String:
	var x := direction.x * facing
	var token := ""
	if direction.y < 0:
		token += "U"
	elif direction.y > 0:
		token += "D"
	if x > 0:
		token += "F"
	elif x < 0:
		token += "B"
	return token


## Call once per frame. direction is (-1..1, -1..1) with y positive down. Returns true on success.
func advance(direction: Vector2i, facing: int, attack_pressed: bool, sub_pressed: bool = false) -> bool:
	frame += 1
	var token := direction_token(direction, facing)
	if token != _last_direction:
		_last_direction = token
		if token != "":
			_events.append([token, frame])
	if sub_pressed:
		_events.append(["S", frame])
	if attack_pressed:
		if assist:
			return true
		_events.append(["A", frame])
		return _matches()
	return false


func _matches() -> bool:
	var fresh: Array = []
	for event: Array in _events:
		if frame - int(event[1]) <= window_frames:
			fresh.append(event[0])
	for variant: Array in _variants():
		if fresh.size() >= variant.size() and _tail_equals(fresh, variant):
			return true
	return false


static func _tail_equals(tokens: Array, variant: Array) -> bool:
	var offset := tokens.size() - variant.size()
	for i in variant.size():
		if tokens[offset + i] != variant[i]:
			return false
	return true


## The required sequence with every subset of its diagonals removed, longest first.
func _variants() -> Array:
	var optional_indexes: Array[int] = []
	for i in sequence.size():
		if sequence[i] in DIAGONALS:
			optional_indexes.append(i)
	var out: Array = []
	for mask in range(1 << optional_indexes.size()):
		var variant: Array = []
		for i in sequence.size():
			var slot := optional_indexes.find(i)
			if slot >= 0 and (mask >> slot) & 1 == 1:
				continue
			variant.append(sequence[i])
		out.append(variant)
	out.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return out
