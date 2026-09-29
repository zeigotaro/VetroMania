class_name Icons
extends RefCounted
## Item icons and rarity frames from the exported atlas (assets/items).

const WEAPON_ICONS := {
	"bat": "beam_bat", "whip": "plasma_whip", "mallet": "mega_mallet", "cutter": "box_cutter",
	"mitt_cannon": "mitt_cannon", "spread_gun": "spread_gun", "throwable": "throwable",
}
const ARMOR_ICONS := {
	"helmet": "helm", "chest": "chest", "gauntlets": "gauntlets", "gloves": "gloves", "leggings": "leggings", "boots": "boots",
}
const RING_ICONS := {"quantum_band": "ring_band", "halo_loop": "ring_halo"}

static var _cache := {}


static func key_for_item(item: Dictionary) -> String:
	var family: String = item["family"]
	if item["slot"] == "ring":
		return RING_ICONS[family]
	if ARMOR_ICONS.has(family):
		return ARMOR_ICONS[family]
	return WEAPON_ICONS[family]


static func gem_key(kind: String, color: String) -> String:
	return "gem_%s_%s" % [kind, color]


static func texture(key: String) -> AtlasTexture:
	if _cache.has(key):
		return _cache[key]
	var icons: Dictionary = Db.manifest()["items"]["icons"]
	if not icons["index"].has(key):
		push_error("Icons: no icon '%s'" % key)
		return null
	var size := int(icons["icon_size"])
	var atlas := AtlasTexture.new()
	atlas.atlas = SpriteLib.texture(icons["file"])
	atlas.region = Rect2(int(icons["index"][key][0]) * size, int(icons["index"][key][1]) * size, size, size)
	_cache[key] = atlas
	return atlas


static func rarity_frame(rarity: String) -> AtlasTexture:
	var id := "frame_" + rarity
	if _cache.has(id):
		return _cache[id]
	var frames: Dictionary = Db.manifest()["items"]["rarity_frames"]
	var size := int(frames["size"])
	var atlas := AtlasTexture.new()
	atlas.atlas = SpriteLib.texture(frames["file"])
	atlas.region = Rect2(frames["order"].find(rarity) * size, 0, size, size)
	_cache[id] = atlas
	return atlas


static func item_texture(item: Dictionary) -> AtlasTexture:
	return texture(key_for_item(item))


static func drop_texture(drop: Dictionary) -> AtlasTexture:
	match drop["type"]:
		"bucks":
			return texture("vetro_buck")
		"gem":
			return texture(gem_key(drop["kind"], drop["color"]))
		"consumable":
			return texture(Db.legendary_data()["consumables"][drop["id"]]["icon"])
		"gear":
			return item_texture(drop["item"])
	return null
