class_name SealOverlay
extends Modal
## The Autograph Seal: a fighting-game motion (down, down-forward, forward, then attack) inside a time window.
## Boss mode ends with the result after a short flourish; practice mode (the signing table) has no limit and
## X gives up. close() returns true when the autograph was signed.

const TOKEN_LABELS := {"D": "DOWN", "DF": "DOWN-FWD", "F": "FORWARD", "A": "ATTACK", "B": "BACK", "DB": "DOWN-BACK", "U": "UP", "UF": "UP-FWD", "UB": "UP-BACK"}
const FLOURISH := 55

var seal_id := 1
var practice := false
var facing := 1
var sealer: SealInput
var tokens: Array[String] = []
var window := 180
var frames_left := 180
var state := "input"
var flourish := 0
var live := LiveInput.new()
var current_token := ""
var attack_flash := 0


func _init(id: int = 1, is_practice: bool = false, player_facing: int = 1, difficulty: Dictionary = {}) -> void:
	super._init()
	seal_id = id
	practice = is_practice
	facing = player_facing
	var def: Dictionary = Db.areas()["seals"][str(id)]
	tokens.assign(def["tokens"])
	window = roundi(float(difficulty.get("seal_window", 3.0)) * Consts.FPS)
	frames_left = window
	sealer = SealInput.new(tokens, window if not practice else 1 << 20, Settings.seal_assist)
	AudioService.sfx("seal_prompt")


func handle(action: String) -> void:
	if action == "cancel" and practice and state == "input":
		close(false)


## One frame of input. Tests call this directly; _physics_process feeds it from the keyboard and pad.
func tick(direction: Vector2i, attack: bool) -> void:
	if state != "input":
		flourish -= 1
		if flourish <= 0:
			close(state == "success")
		return
	current_token = SealInput.direction_token(direction, facing)
	if attack:
		attack_flash = 8
	attack_flash = maxi(0, attack_flash - 1)
	if not practice:
		frames_left -= 1
	if sealer.advance(direction, facing, attack):
		state = "success"
		flourish = FLOURISH
		AudioService.sfx("seal_success")
	elif not practice and frames_left <= 0:
		state = "fail"
		flourish = FLOURISH
		AudioService.sfx("seal_fail")


func _physics_process(_delta: float) -> void:
	if done:
		return
	live.poll()
	tick(live.direction(), live.just_pressed("attack"))


func _draw() -> void:
	var panel := Rect2(100, 90, 440, 180)
	UIKit.draw_panel(self, panel, Color(0.04, 0.03, 0.1, 0.96), UIKit.COLORS["xp"])
	var def: Dictionary = Db.areas()["seals"][str(seal_id)]
	UIKit.draw_text_center(self, "AUTOGRAPH SEAL %d: %s" % [seal_id, String(def["name"])], 320, 100, UIKit.COLORS["xp"], 2)
	var title := "PRACTICE. NO TIME LIMIT." if practice else "SIGN HIM BEFORE HE RECOVERS!"
	UIKit.draw_text_center(self, title, 320, 122, UIKit.COLORS["dim"])
	var width := 84.0
	var gap := 12.0
	var x := 320.0 - (tokens.size() * width + (tokens.size() - 1) * gap) / 2.0
	for token in tokens:
		var lit := token == current_token or (token == "A" and attack_flash > 0)
		var rect := Rect2(x, 146, width, 34)
		draw_rect(rect, UIKit.COLORS["xp"].darkened(0.3) if lit else Color(0.1, 0.08, 0.18))
		draw_rect(rect, UIKit.COLORS["xp"] if lit else UIKit.COLORS["border"], false, 2.0)
		UIKit.draw_text_center(self, String(TOKEN_LABELS.get(token, token)), rect.position.x + width / 2.0, 158, UIKit.COLORS["text"] if lit else UIKit.COLORS["dim"])
		x += width + gap
	if not practice:
		UIKit.draw_bar(self, Rect2(140, 200, 360, 10), float(frames_left) / maxf(1.0, float(window)), UIKit.COLORS["hp"] if frames_left < window / 3 else UIKit.COLORS["xp"])
	UIKit.draw_text_center(self, "HOLD THE DIRECTIONS IN ORDER, THEN PRESS ATTACK (X)" if not Settings.seal_assist else "SEAL ASSIST: PRESS ATTACK (X)", 320, 222, UIKit.COLORS["text"])
	if practice:
		UIKit.draw_text_center(self, "X: GIVE UP", 320, 244, UIKit.COLORS["dim"])
	if state == "success":
		UIKit.draw_text_center(self, "SIGNED!", 320, 244, UIKit.COLORS["good"], 2)
	elif state == "fail":
		UIKit.draw_text_center(self, "SMUDGED!", 320, 244, UIKit.COLORS["bad"], 2)
