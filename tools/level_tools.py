#!/usr/bin/env python3
"""Level model, linter and preview renderer for the VetroMania slice.

    python tools/level_tools.py lint                      # schema and design checks; exit 1 on problems
    python tools/level_tools.py preview --room crash_1    # one room at 1x to tmp/level_preview/crash_1.png
    python tools/level_tools.py preview --map             # the whole map, scaled down
    python tools/level_tools.py solve                     # reachability solver (see solver.py)

Rooms are JSON files in game/data/rooms/ with ASCII tiles; see docs/technical/level-format.md.
The same rules are enforced at runtime by game/core/level.gd.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game" / "data"
ROOMS_DIR = DATA / "rooms"
ASSETS = ROOT / "game" / "assets"

CELL_W, CELL_H, TILE = 40, 23, 16
HARD = set("#BZ")
GATES = set("%XTC")
SOLID = HARD | GATES
DECOR = {"w": "back_wall", "-": "pipe_h", "|": "pipe_v", "g": "grate", "L": "light_panel", "v": "vine", "P": "pillar", "b": "brick"}
LEGEND = set(".#B=^%XTCZ") | set(DECOR)
ENTITY_TYPES = {
    "spawn", "enemy", "boss", "save_pod", "vending", "statue", "npc", "table", "chest", "orb", "door", "warp", "hint",
}


@dataclass
class Room:
    id: str
    area: str
    cell: tuple[int, int]
    size: tuple[int, int]
    tiles: list[str]
    entities: list[dict] = field(default_factory=list)

    @property
    def origin(self) -> tuple[int, int]:
        return self.cell[0] * CELL_W, self.cell[1] * CELL_H

    @property
    def tile_size(self) -> tuple[int, int]:
        return self.size[0] * CELL_W, self.size[1] * CELL_H

    def cells(self) -> list[tuple[int, int]]:
        return [(self.cell[0] + x, self.cell[1] + y) for y in range(self.size[1]) for x in range(self.size[0])]


class Level:
    def __init__(self, rooms: list[Room]) -> None:
        self.rooms = {room.id: room for room in rooms}
        self.order = [room.id for room in rooms]
        self.cell_room: dict[tuple[int, int], str] = {}
        for room in rooms:
            for cell in room.cells():
                self.cell_room[cell] = room.id

    @classmethod
    def load(cls, directory: Path = ROOMS_DIR) -> "Level":
        rooms = []
        for path in sorted(directory.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            rooms.append(Room(
                id=data["id"], area=data["area"], cell=tuple(data["cell"]), size=tuple(data.get("size", [1, 1])),
                tiles=list(data["tiles"]), entities=list(data.get("entities", [])),
            ))
        return cls(rooms)

    def room_at_cell(self, cell: tuple[int, int]) -> Room | None:
        room_id = self.cell_room.get(cell)
        return self.rooms.get(room_id) if room_id else None

    def tile(self, gx: int, gy: int) -> str:
        room = self.room_at_cell((gx // CELL_W, gy // CELL_H))
        if room is None:
            return ""
        lx, ly = gx - room.origin[0], gy - room.origin[1]
        if 0 <= ly < len(room.tiles) and 0 <= lx < len(room.tiles[ly]):
            return room.tiles[ly][lx]
        return ""

    def solid(self, gx: int, gy: int) -> bool:
        ch = self.tile(gx, gy)
        return ch == "" or ch in SOLID

    def bounds(self) -> tuple[int, int, int, int]:
        xs = [c[0] for c in self.cell_room]
        ys = [c[1] for c in self.cell_room]
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    def entity_tile(self, room: Room, at: list[int]) -> tuple[int, int]:
        return room.origin[0] + int(at[0]), room.origin[1] + int(at[1])


def known_enemies() -> set[str]:
    return set(json.loads((DATA / "enemies.json").read_text(encoding="utf-8"))["enemies"])


def known_bosses() -> set[str]:
    return set(json.loads((DATA / "enemies.json").read_text(encoding="utf-8"))["bosses"])


def known_areas() -> dict:
    return json.loads((DATA / "areas.json").read_text(encoding="utf-8"))


def roster_names() -> set[str]:
    return {p["name"] for p in json.loads((DATA / "roster.json").read_text(encoding="utf-8"))["players"]}


def lint(level: Level) -> list[str]:
    """Design and schema problems. Empty means clean."""
    problems: list[str] = []
    enemies, bosses, areas, names = known_enemies(), known_bosses(), known_areas(), roster_names()
    abilities = set(areas["abilities"])
    for room in level.rooms.values():
        w, h = room.tile_size
        if len(room.tiles) != h:
            problems.append(f"{room.id}: {len(room.tiles)} rows, expected {h}")
            continue
        for y, row in enumerate(room.tiles):
            if len(row) != w:
                problems.append(f"{room.id} row {y}: {len(row)} columns, expected {w}")
            for x, ch in enumerate(row):
                if ch not in LEGEND:
                    problems.append(f"{room.id} ({x},{y}): unknown tile {ch!r}")
        if room.area not in areas["areas"]:
            problems.append(f"{room.id}: unknown area {room.area!r}")
        has_target = any("T" in row for row in room.tiles)
        has_shutter = any("C" in row for row in room.tiles)
        if has_target != has_shutter:
            problems.append(f"{room.id}: a mitt target needs a conduit shutter, and the other way round")
        for entity in room.entities:
            problems.extend(_lint_entity(level, room, entity, enemies, bosses, abilities, names))
    problems.extend(_lint_edges(level))
    spawns = [e for r in level.rooms.values() for e in r.entities if e["type"] == "spawn" and e.get("id") == "start"]
    if len(spawns) != 1:
        problems.append(f"expected exactly one 'start' spawn, found {len(spawns)}")
    bosses_placed = [e for r in level.rooms.values() for e in r.entities if e["type"] == "boss"]
    if len(bosses_placed) != 1:
        problems.append(f"expected exactly one boss, found {len(bosses_placed)}")
    return problems


def _lint_entity(level: Level, room: Room, entity: dict, enemies: set, bosses: set, abilities: set, names: set) -> list[str]:
    problems: list[str] = []
    kind = entity.get("type")
    at = entity.get("at")
    where = f"{room.id}: {kind} at {at}"
    if kind not in ENTITY_TYPES:
        return [f"{where}: unknown entity type"]
    w, h = room.tile_size
    if not (isinstance(at, list) and len(at) == 2 and 0 <= at[0] < w and 0 <= at[1] < h):
        return [f"{where}: outside the room"]
    gx, gy = level.entity_tile(room, at)
    if kind in {"save_pod", "vending", "statue", "npc", "table", "chest", "warp", "door", "boss", "spawn"}:
        if level.solid(gx, gy):
            problems.append(f"{where}: stands inside a solid tile")
        if not level.solid(gx, gy + 1) and level.tile(gx, gy + 1) != "=":
            problems.append(f"{where}: has nothing to stand on")
    if kind == "enemy" and entity.get("id") not in enemies:
        problems.append(f"{where}: unknown enemy {entity.get('id')!r}")
    if kind == "boss" and entity.get("id") not in bosses:
        problems.append(f"{where}: unknown boss {entity.get('id')!r}")
    if kind == "orb" and entity.get("ability") not in abilities:
        problems.append(f"{where}: unknown ability {entity.get('ability')!r}")
    if kind == "npc" and entity.get("name") not in names:
        problems.append(f"{where}: {entity.get('name')!r} is not in game/data/roster.json")
    if kind == "npc":
        lines = next((p.get("lines") for p in json.loads((DATA / "roster.json").read_text(encoding="utf-8"))["players"] if p["name"] == entity.get("name")), None)
        if not lines:
            problems.append(f"{where}: this roster entry has no dialogue lines")
    return problems


def _hard(ch: str) -> bool:
    return ch in HARD


def _lint_edges(level: Level) -> list[str]:
    """A doorway must be open on both sides: one side hard-solid and the other open is a broken seam."""
    problems: list[str] = []
    for room in level.rooms.values():
        ox, oy = room.origin
        w, h = room.tile_size
        for y in range(h):
            right = level.tile(ox + w, oy + y)
            if right != "" and level.room_at_cell(((ox + w) // CELL_W, (oy + y) // CELL_H)).id != room.id:
                left = level.tile(ox + w - 1, oy + y)
                if _hard(left) != _hard(right) and left not in GATES and right not in GATES:
                    problems.append(f"seam {room.id} -> east at row {oy + y}: {left!r} meets {right!r}")
        for x in range(w):
            below = level.tile(ox + x, oy + h)
            if below != "" and level.room_at_cell(((ox + x) // CELL_W, (oy + h) // CELL_H)).id != room.id:
                above = level.tile(ox + x, oy + h - 1)
                if _hard(above) != _hard(below) and above not in GATES and below not in GATES:
                    problems.append(f"seam {room.id} -> south at column {ox + x}: {above!r} meets {below!r}")
    return problems


# --- preview -----------------------------------------------------------------------------------------------

MARKER_COLORS = {
    "enemy": (255, 80, 80), "boss": (255, 0, 0), "save_pod": (255, 60, 90), "vending": (80, 220, 255),
    "statue": (80, 220, 255), "npc": (200, 140, 255), "table": (255, 200, 60), "chest": (255, 215, 0),
    "orb": (255, 255, 120), "door": (160, 160, 255), "warp": (255, 220, 60), "hint": (90, 200, 90), "spawn": (60, 255, 120),
}


def render(level: Level, room_ids: list[str] | None = None, scale: float = 1.0, markers: bool = True):
    from PIL import Image, ImageDraw

    manifest = json.loads((ASSETS / "manifest.json").read_text(encoding="utf-8"))
    index = manifest["tiles"]["index"]
    atlases: dict[str, Image.Image] = {}
    area_tileset = {name: a["tileset"] for name, a in known_areas()["areas"].items()}
    x0, y0, x1, y1 = level.bounds()
    if room_ids:
        rooms = [level.rooms[i] for i in room_ids]
        x0 = min(r.cell[0] for r in rooms)
        y0 = min(r.cell[1] for r in rooms)
        x1 = max(r.cell[0] + r.size[0] for r in rooms)
        y1 = max(r.cell[1] + r.size[1] for r in rooms)
    else:
        rooms = list(level.rooms.values())
    canvas = Image.new("RGBA", ((x1 - x0) * CELL_W * TILE, (y1 - y0) * CELL_H * TILE), (12, 10, 24, 255))
    draw = ImageDraw.Draw(canvas)

    def tile_image(area: str, name: str):
        tileset = area_tileset[area]
        if tileset not in atlases:
            atlases[tileset] = Image.open(ASSETS / manifest["tiles"]["atlases"][tileset]).convert("RGBA")
        col, row = index[name]
        return atlases[tileset].crop((col * TILE, row * TILE, col * TILE + TILE, row * TILE + TILE))

    names = {"B": "brick", "%": "brick", "Z": "hazard", "=": "platform", "^": "spike", "X": "crate", "T": "mitt_target_0", "C": "brick_conduit"}
    for room in rooms:
        ox, oy = room.origin
        w, h = room.tile_size
        px, py = (ox - x0 * CELL_W) * TILE, (oy - y0 * CELL_H) * TILE
        draw.rectangle([px, py, px + w * TILE - 1, py + h * TILE - 1], fill=(20, 16, 40, 255))
        for ty, row in enumerate(room.tiles):
            for tx, ch in enumerate(row):
                if ch == ".":
                    continue
                if ch == "#":
                    above = level.tile(ox + tx, oy + ty - 1)
                    name = "floor_fill" if above in SOLID else "floor_top"
                elif ch in DECOR:
                    name = DECOR[ch]
                else:
                    name = names.get(ch, "")
                if name:
                    canvas.alpha_composite(tile_image(room.area, name), (px + tx * TILE, py + ty * TILE))
        if markers:
            for entity in room.entities:
                kind = entity["type"]
                ex, ey = int(entity["at"][0]), int(entity["at"][1])
                color = MARKER_COLORS.get(kind, (255, 255, 255))
                cx, cy = px + ex * TILE, py + ey * TILE
                draw.rectangle([cx, cy, cx + TILE - 1, cy + TILE - 1], outline=color + (255,), width=2)
                label = {"enemy": entity.get("id", "e")[:2], "npc": entity.get("name", "n")[:2], "orb": entity.get("ability", "o")[:2]}.get(kind, kind[:2])
                draw.text((cx + 2, cy + 2), label, fill=color + (255,))
        draw.rectangle([px, py, px + w * TILE - 1, py + h * TILE - 1], outline=(255, 255, 255, 90))
        draw.text((px + 4, py + 4), room.id, fill=(255, 255, 255, 255))
    if scale != 1.0:
        canvas = canvas.resize((int(canvas.width * scale), int(canvas.height * scale)), Image.NEAREST if scale >= 1 else Image.LANCZOS)
    return canvas


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("lint")
    preview = sub.add_parser("preview")
    preview.add_argument("--room", action="append", help="room id (repeatable)")
    preview.add_argument("--map", action="store_true", help="render every room")
    preview.add_argument("--scale", type=float, default=None)
    preview.add_argument("--out", type=Path, default=ROOT / "tmp" / "level_preview")
    preview.add_argument("--no-markers", action="store_true")
    sub.add_parser("solve")
    args = parser.parse_args(argv)
    level = Level.load()
    if args.command == "lint":
        problems = lint(level)
        for problem in problems:
            print("LINT:", problem)
        print(f"{len(level.rooms)} rooms, {len(level.cell_room)} cells, {len(problems)} problem(s)")
        return 1 if problems else 0
    if args.command == "preview":
        args.out.mkdir(parents=True, exist_ok=True)
        if args.map or not args.room:
            image = render(level, None, args.scale or 0.25, not args.no_markers)
            path = args.out / "map.png"
        else:
            image = render(level, args.room, args.scale or 1.0, not args.no_markers)
            path = args.out / ("_".join(args.room) + ".png")
        image.save(path)
        print("wrote", path, image.size)
        return 0
    from solver import main as solve_main  # noqa: PLC0415

    return solve_main(level)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
