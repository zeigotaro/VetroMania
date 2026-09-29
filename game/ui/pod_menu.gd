class_name PodMenu
extends Modal
## A save pod: the game is already saved and Sleve is healed when this opens. From here Sleve can upgrade or
## salvage gear (the bench) and choose which Knack sits on the Knack button.

enum Mode { MAIN, UPGRADE, AFFIX, SALVAGE, KNACKS }

const MAIN_OPTIONS: Array[String] = ["UPGRADE GEAR", "SALVAGE GEAR", "KNACK LOADOUT", "CLOSE"]
const ROW := 12
const ROWS := 15

var gs: GameState
var mode := Mode.MAIN
var index := 0
var scroll := 0
var target: Dictionary = {}
var armed_uid := -1
var message := ""
var items: Array[Dictionary] = []
var knacks: Array[String] = []


func _init(state: GameState = null) -> void:
	super._init()
	gs = state


func _gear() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in gs.data["inventory"]:
		out.append(item)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea := gs.equipped_slot_of(a) != ""
		var eb := gs.equipped_slot_of(b) != ""
		if ea != eb:
			return ea
		return int(a["ilvl"]) > int(b["ilvl"]))
	return out


func _enter(new_mode: Mode) -> void:
	mode = new_mode
	index = 0
	scroll = 0
	armed_uid = -1
	message = ""
	match mode:
		Mode.UPGRADE, Mode.SALVAGE:
			items = _gear()
		Mode.KNACKS:
			knacks.clear()
			for perk_id: String in gs.data["tallies"]["completed"]:
				if Tallies.perk_def(perk_id).get("type", "") == "knack":
					knacks.append(perk_id)
		Mode.AFFIX:
			pass


func _count() -> int:
	match mode:
		Mode.MAIN:
			return MAIN_OPTIONS.size()
		Mode.UPGRADE, Mode.SALVAGE:
			return items.size()
		Mode.AFFIX:
			return target["affixes"].size() + 1
		Mode.KNACKS:
			return knacks.size()
	return 0


func handle(action: String) -> void:
	match action:
		"up", "down":
			var count := _count()
			if count > 0:
				index = wrapi(index + (1 if action == "down" else -1), 0, count)
				scroll = clampi(scroll, maxi(0, index - ROWS + 1), index)
				armed_uid = -1
				AudioService.sfx("menu_move", -8.0)
		"cancel", "pause":
			AudioService.sfx("menu_back", -6.0)
			if mode == Mode.MAIN:
				close()
			elif mode == Mode.AFFIX:
				_enter(Mode.UPGRADE)
			else:
				_enter(Mode.MAIN)
		"confirm":
			_confirm()


func _confirm() -> void:
	match mode:
		Mode.MAIN:
			match index:
				0:
					_enter(Mode.UPGRADE)
				1:
					_enter(Mode.SALVAGE)
				2:
					_enter(Mode.KNACKS)
				3:
					close()
		Mode.UPGRADE:
			if items.is_empty():
				return
			var item := items[index]
			var problem := Upgrades.error_for(item, gs.level, gs.data["gems"], gs.bucks)
			if problem != "":
				AudioService.sfx("upgrade_fail", -4.0)
				message = problem
			elif item["affixes"].is_empty():
				_upgrade(item, -1)
			else:
				target = item
				_enter(Mode.AFFIX)
		Mode.AFFIX:
			_upgrade(target, index if index < target["affixes"].size() else -1)
			_enter(Mode.UPGRADE)
		Mode.SALVAGE:
			if items.is_empty():
				return
			var item := items[index]
			if armed_uid != int(item["uid"]):
				armed_uid = int(item["uid"])
				message = "PRESS Z AGAIN TO SALVAGE " + Items.compose_name(item)
				AudioService.sfx("menu_select", -6.0)
			else:
				var refund := gs.salvage(item)
				AudioService.sfx("pickup_gem", -4.0)
				items = _gear()
				index = clampi(index, 0, maxi(0, items.size() - 1))
				armed_uid = -1
				message = "SALVAGED: %d GEMS AND $%d" % [refund, Items.sell_price(item)]
		Mode.KNACKS:
			if knacks.is_empty():
				return
			var perk_id := knacks[index]
			var state: Dictionary = gs.data["tallies"]
			if perk_id in state["knacks"]:
				Tallies.unequip_knack(state, perk_id)
				message = "UNEQUIPPED"
			elif Tallies.equip_knack(state, perk_id):
				AudioService.sfx("equip_item", -4.0)
				message = "EQUIPPED ON THE KNACK BUTTON (V)"
			else:
				AudioService.sfx("menu_deny", -6.0)
				message = "NO FREE KNACK SLOT"


func _upgrade(item: Dictionary, affix_index: int) -> void:
	var problem := gs.upgrade_item(item, affix_index)
	if problem != "":
		AudioService.sfx("upgrade_fail", -4.0)
		message = problem
	else:
		AudioService.sfx("upgrade_success", -2.0)
		message = "UPGRADED TO +%d" % int(item["upgrades"])


# --- drawing -----------------------------------------------------------------------------------------

func _draw() -> void:
	UIKit.draw_panel(self, Rect2(40, 24, 560, 312), Color(0.04, 0.03, 0.1, 0.97))
	UIKit.draw_text(self, "SAVE POD", Vector2(56, 34), UIKit.COLORS["select"], 2)
	UIKit.draw_text(self, "GAME SAVED. HP AND EP RESTORED.", Vector2(56, 52), UIKit.COLORS["good"])
	UIKit.draw_text_right(self, "$%d   WEAPON GEMS %d   ARMOR GEMS %d" % [gs.bucks, gs.gems("weapon"), gs.gems("armor")], 584, 36, UIKit.COLORS["xp"])
	draw_line(Vector2(48, 66), Vector2(592, 66), UIKit.COLORS["border"].darkened(0.3))
	match mode:
		Mode.MAIN:
			_draw_main()
		Mode.UPGRADE:
			_draw_items(true)
		Mode.AFFIX:
			_draw_affixes()
		Mode.SALVAGE:
			_draw_items(false)
		Mode.KNACKS:
			_draw_knacks()
	if message != "":
		UIKit.draw_text(self, message, Vector2(56, 320), UIKit.COLORS["select"])
	UIKit.draw_text_right(self, "Z: SELECT   X: BACK", 584, 320, UIKit.COLORS["dim"])


func _cursor(y: float) -> void:
	draw_rect(Rect2(52, y - 2, 250, ROW), UIKit.COLORS["border"].darkened(0.5))
	UIKit.draw_text(self, ">", Vector2(54, y), UIKit.COLORS["select"])


func _draw_main() -> void:
	for i in MAIN_OPTIONS.size():
		var y := 84.0 + i * 18.0
		if i == index:
			_cursor(y)
		UIKit.draw_text(self, MAIN_OPTIONS[i], Vector2(68, y), UIKit.COLORS["text"], 1)
	var blurbs := [
		"SPEND GEMS AND VETRO-BUCKS TO MAKE GEAR BETTER. THE CAP FOLLOWS YOUR LEVEL: ONE UPGRADE AT LV 1, FIVE AT LV 50.",
		"BREAK GEAR DOWN. YOU KEEP HALF THE GEMS YOU SPENT ON IT, PLUS ITS SELL PRICE.",
		"CHOOSE WHICH COMPLETED KILL TALLY POWER SITS ON THE KNACK BUTTON (V).",
		"THE POD WILL BE HERE. IT'S A POD. IT DOESN'T GO ANYWHERE.",
	]
	var y := 84.0
	for line in UIKit.wrap(blurbs[index], 44):
		UIKit.draw_text(self, line, Vector2(330, y), UIKit.COLORS["dim"])
		y += 11.0


func _draw_row_item(item: Dictionary, y: float, suffix: String) -> void:
	var worn := gs.equipped_slot_of(item) != ""
	draw_texture_rect(Icons.item_texture(item), Rect2(66, y - 2, 12, 12), false)
	UIKit.draw_text(self, ("E " if worn else "") + UIKit.item_title(item).left(31), Vector2(82, y), UIKit.rarity_color(item["rarity"]))
	UIKit.draw_text_right(self, suffix, 296, y, UIKit.COLORS["dim"])


func _draw_items(upgrading: bool) -> void:
	if items.is_empty():
		UIKit.draw_text(self, "NOTHING IN THE BAG. GO KILL SOMETHING.", Vector2(68, 84), UIKit.COLORS["dim"])
		return
	for i in ROWS:
		var at := scroll + i
		if at >= items.size():
			break
		var y := 76.0 + i * ROW
		if at == index:
			_cursor(y)
		var suffix := "+%d" % int(items[at]["upgrades"]) if upgrading else "$%d" % Items.sell_price(items[at])
		_draw_row_item(items[at], y, suffix)
	var item := items[index]
	ItemCard.draw(self, item, gs.level, Vector2(330, 76), 46, gs.data["equipped"])
	var y := 220.0
	if upgrading:
		_draw_upgrade_info(item, y)
	else:
		UIKit.draw_text(self, "SALVAGE REFUND: %d %s GEMS" % [Upgrades.salvage_refund(item), Upgrades.gem_kind(item).to_upper()], Vector2(330, y), UIKit.COLORS["good"])
		UIKit.draw_text(self, "SELL PRICE: $%d" % Items.sell_price(item), Vector2(330, y + 11), UIKit.COLORS["xp"])


func _draw_upgrade_info(item: Dictionary, y: float) -> void:
	var preview := Upgrades.preview(item)
	var problem := Upgrades.error_for(item, gs.level, gs.data["gems"], gs.bucks)
	if int(item["upgrades"]) >= Upgrades.MAX_UPGRADES:
		UIKit.draw_text(self, "FULLY UPGRADED", Vector2(330, y), UIKit.COLORS["good"])
		return
	UIKit.draw_text(self, "NEXT STEP: %d -> %d" % [int(preview["value_now"]), int(preview["value_next"])], Vector2(330, y), UIKit.COLORS["text"])
	UIKit.draw_text(self, "COST: %d %s GEMS AND $%d" % [int(preview["gems"]), String(preview["kind"]).to_upper(), int(preview["fee"])], Vector2(330, y + 11), UIKit.COLORS["xp"])
	UIKit.draw_text(self, "LEVEL CAP: %d UPGRADES AT LV %d" % [Upgrades.cap_for_level(gs.level), gs.level], Vector2(330, y + 22), UIKit.COLORS["dim"])
	if problem != "":
		UIKit.draw_text(self, problem, Vector2(330, y + 36), UIKit.COLORS["bad"])
	else:
		UIKit.draw_text(self, "Z: UPGRADE", Vector2(330, y + 36), UIKit.COLORS["good"])


func _draw_affixes() -> void:
	UIKit.draw_text(self, "RAISE WHICH AFFIX? (THE BASE VALUE GOES UP EITHER WAY)", Vector2(56, 74), UIKit.COLORS["dim"])
	var affixes: Array = target["affixes"]
	for i in affixes.size() + 1:
		var y := 92.0 + i * 16.0
		if i == index:
			_cursor(y)
		if i < affixes.size():
			var gain := float(Upgrades.preview(target, i)["affix_gain"])
			UIKit.draw_text(self, "%s  (+%s)" % [Items.affix_text(affixes[i]), ("%.1f" % gain) if gain != floorf(gain) else str(int(gain))], Vector2(68, y), UIKit.COLORS["ep"])
		else:
			UIKit.draw_text(self, "BASE ONLY", Vector2(68, y), UIKit.COLORS["text"])
	ItemCard.draw(self, target, gs.level, Vector2(330, 92), 46, gs.data["equipped"])


func _draw_knacks() -> void:
	if knacks.is_empty():
		UIKit.draw_text(self, "NO KNACKS YET. FINISH A KILL TALLY TO EARN ONE.", Vector2(68, 84), UIKit.COLORS["dim"])
		return
	var state: Dictionary = gs.data["tallies"]
	UIKit.draw_text(self, "KNACK SLOTS: %d/%d" % [state["knacks"].size(), Tallies.knack_slots(state)], Vector2(56, 74), UIKit.COLORS["ep"])
	for i in knacks.size():
		var y := 92.0 + i * 16.0
		if i == index:
			_cursor(y)
		var def := Tallies.perk_def(knacks[i])
		var on: bool = knacks[i] in state["knacks"]
		UIKit.draw_text(self, ("ON  " if on else "OFF ") + String(def["name"]), Vector2(68, y), UIKit.COLORS["good"] if on else UIKit.COLORS["text"])
	var y := 92.0
	for line in UIKit.wrap(String(Tallies.perk_def(knacks[index]).get("text", "")), 44):
		UIKit.draw_text(self, line, Vector2(330, y), UIKit.COLORS["dim"])
		y += 11.0
