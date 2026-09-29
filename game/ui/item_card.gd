class_name ItemCard
extends RefCounted
## Draws an item's details: icon and frame, name, requirements, value, affixes, upgrades, and the power or
## set bonuses of legendaries and set pieces. Used by the pause menu and the upgrade bench.

const LINE := 10


static func kind_label(item: Dictionary) -> String:
	return String(item["family"]).replace("_", " ").to_upper()


static func power_text(item: Dictionary) -> String:
	var power := String(item.get("power", ""))
	if power == "":
		return ""
	for entry: Dictionary in Db.legendary_data()["legendaries"]:
		if String(entry["power"]) == power:
			return String(entry["text"])
	return ""


## Draws the card with its top-left corner at `at` and returns the y just below it.
static func draw(node: CanvasItem, item: Dictionary, level: int, at: Vector2, max_chars: int, equipped: Dictionary = {}) -> float:
	var rarity: String = item["rarity"]
	var frame := Icons.rarity_frame(rarity)
	var icon := Icons.item_texture(item)
	node.draw_texture(frame, at)
	if icon != null:
		node.draw_texture(icon, at + Vector2(2, 2))
	var x := at.x + 34.0
	var y := at.y
	var title_lines := UIKit.wrap(UIKit.item_title(item), max_chars - 5)
	for line in title_lines:
		UIKit.draw_text(node, line, Vector2(x, y), UIKit.rarity_color(rarity))
		y += LINE
	UIKit.draw_text(node, "%s %s" % [rarity.to_upper(), kind_label(item)], Vector2(x, y), UIKit.COLORS["dim"])
	y = maxf(y + LINE, at.y + 30.0)
	var required := Items.required_level(item)
	var need_color: Color = UIKit.COLORS["good"] if level >= required else UIKit.COLORS["bad"]
	UIKit.draw_text(node, "ILVL %d" % int(item["ilvl"]), Vector2(at.x, y), UIKit.COLORS["text"])
	UIKit.draw_text(node, "REQUIRES LV %d" % required, Vector2(at.x + 70, y), need_color)
	y += LINE
	if item["slot"] != "ring":
		var label := "ARMOR" if Items.is_armor_slot(item["slot"]) else "DAMAGE"
		UIKit.draw_text(node, "%s %d" % [label, Items.effective_value(item)], Vector2(at.x, y), UIKit.COLORS["xp"])
		UIKit.draw_text(node, "UPGRADES %d/%d" % [int(item["upgrades"]), Upgrades.MAX_UPGRADES], Vector2(at.x + 100, y), UIKit.COLORS["dim"])
		y += LINE
	elif int(item["upgrades"]) > 0:
		UIKit.draw_text(node, "UPGRADES %d/%d" % [int(item["upgrades"]), Upgrades.MAX_UPGRADES], Vector2(at.x, y), UIKit.COLORS["dim"])
		y += LINE
	y += 2.0
	for entry: Dictionary in item["affixes"]:
		for line in UIKit.wrap("+ " + Items.affix_text(entry), max_chars):
			UIKit.draw_text(node, line, Vector2(at.x, y), UIKit.COLORS["ep"])
			y += LINE
	var power := power_text(item)
	if power != "":
		y += 2.0
		for line in UIKit.wrap(power, max_chars):
			UIKit.draw_text(node, line, Vector2(at.x, y), Consts.RARITY_COLORS["legendary"])
			y += LINE
	var set_id := String(item.get("set_id", ""))
	if set_id != "":
		y += 2.0
		y = _draw_set(node, set_id, at.x, y, max_chars, equipped)
	return y


static func _draw_set(node: CanvasItem, set_id: String, x: float, y: float, max_chars: int, equipped: Dictionary) -> float:
	for set_def: Dictionary in Db.legendary_data()["sets"]:
		if String(set_def["id"]) != set_id:
			continue
		var worn := 0
		for slot: String in equipped:
			if String(equipped[slot].get("set_id", "")) == set_id:
				worn += 1
		UIKit.draw_text(node, "%s (%d/%d)" % [String(set_def["name"]), worn, set_def["pieces"].size()], Vector2(x, y), Consts.RARITY_COLORS["set"])
		y += LINE
		for bonus: Dictionary in set_def["bonuses"]:
			var active := worn >= int(bonus["pieces"])
			for line in UIKit.wrap("%d PCS: %s" % [int(bonus["pieces"]), String(bonus["text"])], max_chars):
				UIKit.draw_text(node, line, Vector2(x, y), Consts.RARITY_COLORS["set"] if active else UIKit.COLORS["dim"])
				y += LINE
	return y
