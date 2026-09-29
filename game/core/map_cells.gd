class_name MapCells
extends RefCounted
## Map cell helpers. One cell is 40 x 23 tiles (640 x 368 px); completion counts visited cells.


static func cell_of(pixel: Vector2) -> Vector2i:
	return Vector2i(floori(pixel.x / Consts.CELL_PX.x), floori(pixel.y / Consts.CELL_PX.y))


static func cell_rect(cell: Vector2i, size: Vector2i = Vector2i.ONE) -> Rect2:
	return Rect2(Vector2(cell * Consts.CELL_PX), Vector2(size * Consts.CELL_PX))


static func cells_of(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(origin + Vector2i(x, y))
	return out


static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func from_key(text: String) -> Vector2i:
	var parts := text.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


## Visited fraction as a percentage, truncated to one decimal so 100.0 only shows at the last cell.
static func percent(visited: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return floorf(visited * 1000.0 / total) / 10.0
