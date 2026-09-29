"""Menu and front-end mockups: title screen, equipment screen, and world map."""

from __future__ import annotations

import numpy as np

import characters
import items
import ui
import world
from pixel import INK, Canvas, hexc, mix, text_mask, text_width, upscale
from scenes import W, H, _dilate, _sprite

VETRO_PLANET = ("#160c2a", "#35185a", "#5e2a8c", "#9446b8", "#cf78d6", "#ffd4f2")


def _chrome_logo(c: Canvas, text: str, y: int, scale: int) -> None:
    """80s chrome lettering: sky-to-sunset gradient, horizon line, outline, drop shadow."""
    mask = text_mask(text, scale)
    h, w = mask.shape
    x = (W - w) // 2
    thick = _dilate(np.pad(mask, 3), 3)
    c.fill(thick, (58, 14, 72), x - 3 + 4, y - 3 + 5)
    c.fill(thick, INK, x - 3, y - 3)
    rows = np.linspace(0, 1, h)
    ramp_colors = []
    for t in rows:
        if t < 0.5:
            color = mix((236, 250, 255), (90, 150, 255), t / 0.5)
        elif t < 0.56:
            color = (30, 20, 70)
        else:
            color = mix((255, 150, 60), (255, 70, 170), (t - 0.56) / 0.44)
        ramp_colors.append(color)
    for row, color in enumerate(ramp_colors):
        line = np.zeros_like(mask)
        line[row] = mask[row]
        c.fill(line, color, x, y)
    top_edge = mask & ~np.roll(mask, 1, axis=0)
    c.fill(top_edge, (255, 255, 255), x, y)
    c.add_glow(mask, (255, 90, 200), x, y, strength=0.18)


def title() -> Canvas:
    c = Canvas(W, H)
    world.sky(c, seed=8)
    world.stars(c, seed=12, count=320)
    world.planet(c, 470, 212, 104, seed=5, palette=VETRO_PLANET)
    world.spires(c, seed=44, base_y=372, color="#0c0716", window="#ffcf6a", heights=(40, 120), count=18, lit=0.2,
                 rim="#2a1f45")
    c.rect(60, 262, 140, H, (12, 7, 22))
    c.rect(60, 262, 140, 264, (60, 46, 96))
    sleve, emission = _sprite(characters.build(characters.idle()[0]))
    c.blit(sleve, 52, 262 - sleve.getbbox()[3], emission=emission)
    _chrome_logo(c, "VETROMANIA", 54, 6)
    subtitle = "SYMPHONY OF THE SPACEBALL"
    c.text((W - text_width(subtitle, 2)) // 2, 118, subtitle, (255, 110, 200), scale=2, glow=(255, 60, 180))
    tag = "STARRING SLEVE BONZALEZ  -  IT'S STRAIGHT UP SPACE TIME"
    c.text((W - text_width(tag)) // 2, 146, tag, (140, 230, 255))
    start = "PRESS START"
    c.text((W - text_width(start, 2)) // 2, 292, start, (255, 214, 64), scale=2, glow=(255, 170, 40))
    legal = "(C) 199X VETROSOFT - ALL YOUR BASE RESERVED"
    c.text((W - text_width(legal)) // 2, 340, legal, (150, 140, 180))
    c.bloom(radius=6, strength=0.8)
    return c


def _backdrop(c: Canvas) -> None:
    y = np.linspace(0, 1, H)[:, None]
    gradient = np.array([20, 12, 36]) * (1 - y) + np.array([8, 5, 16]) * y
    c.rgb[:] = gradient[:, None, :] / 255.0
    grid = np.zeros((H, W), bool)
    grid[::16, :] = True
    grid[:, ::16] = True
    c.fill(grid, (36, 26, 60), alpha=0.5)


def _tabs(c: Canvas, active: str) -> None:
    ui.panel(c, 8, 6, W - 8, 26)
    x = 18
    for name in ("EQUIP", "TALLIES", "BESTIARY", "MAP", "SYSTEM"):
        width = text_width(name)
        if name == active:
            c.rect(x - 5, 9, x + width + 5, 23, (92, 78, 140))
            c.text(x, 12, name, (255, 214, 64))
        else:
            c.text(x, 12, name, (150, 140, 180))
        x += width + 22


def _pips(c: Canvas, x: int, y: int, filled: int, cap: int, total: int = 5) -> None:
    for i in range(total):
        diamond = np.array([[0, 0, 1, 0, 0], [0, 1, 1, 1, 0], [1, 1, 1, 1, 1], [0, 1, 1, 1, 0], [0, 0, 1, 0, 0]], bool)
        if i < filled:
            color = (255, 214, 64)
        elif i < cap:
            color = (120, 104, 60)
        else:
            color = (60, 50, 80)
        c.fill(diamond, color, x + i * 8, y)
        if i < filled:
            c.add_glow(diamond, color, x + i * 8, y, strength=0.5)


def _lock(c: Canvas, x: int, y: int) -> None:
    body = np.ones((7, 9), bool)
    shackle = np.array([[0, 1, 1, 1, 0], [1, 0, 0, 0, 1], [1, 0, 0, 0, 1]], bool)
    c.fill(shackle, (150, 140, 180), x + 2, y)
    c.fill(body, (150, 140, 180), x, y + 3)
    c.rect(x + 4, y + 5, x + 5, y + 8, INK)


SLOTS = [
    ("HEAD", items.helm, "magic"), ("BOOTS", items.boots, "rare"),
    ("CHEST", items.chest, "rare"), ("RING 1", lambda: items.ring("band"), "legendary"),
    ("GAUNTLETS", items.gauntlets, "common"), ("RING 2", None, None),
    ("GLOVES", items.gloves, "set"), ("WEAPON", items.beam_bat, "legendary"),
    ("LEGS", items.leggings, "magic"), ("SUB", items.mitt_cannon, "rare"),
]


def equipment() -> Canvas:
    c = Canvas(W, H)
    _backdrop(c)
    _tabs(c, "EQUIP")

    ui.panel(c, 8, 32, 196, 250)
    doll, _ = _sprite(characters.build(characters.idle()[0]))
    doll = upscale(doll.crop(doll.getbbox()), 2)
    c.blit(doll, 102 - doll.width // 2, 238 - doll.height)
    ui.label(c, 16, 38, "SLEVE BONZALEZ", (255, 214, 64))
    ui.label(c, 16, 48, "BOUNTY HUNTER  LV 24", (150, 140, 180))

    ui.panel(c, 202, 32, 334, 250)
    for i, (name, build, rarity) in enumerate(SLOTS):
        col, row = i % 2, i // 2
        x, y = 210 + col * 64, 38 + row * 42
        if build is None:
            c.blit(items.rarity_frame("common"), x, y)
            c.rect(x + 2, y + 2, x + 26, y + 26, (16, 11, 26))
            _lock(c, x + 9, y + 8)
            ui.label(c, x, y + 30, "LV 37", (255, 84, 96))
            continue
        c.blit(items.framed(build(), rarity), x, y)
        ui.label(c, x, y + 30, name, (236, 230, 255) if name != "BOOTS" else (255, 214, 64))
        if name == "BOOTS":
            c.rect(x - 2, y - 2, x + 30, y - 1, (255, 214, 64))
            c.rect(x - 2, y + 28, x + 30, y + 29, (255, 214, 64))
            c.rect(x - 2, y - 2, x - 1, y + 29, (255, 214, 64))
            c.rect(x + 29, y - 2, x + 30, y + 29, (255, 214, 64))

    ui.panel(c, 340, 32, W - 8, 250, edge=(255, 214, 64))
    col = ui.COLORS
    lines = [
        ("OVERCLOCKED MAG-BOOTS", col["rare"]), ("OF THE LEEROY", col["rare"]),
        ("BOOTS  -  ITEM LV 22  -  REQ LV 18", (150, 140, 180)), None,
        ("ARMOR 48", (236, 230, 255)), ("+6 DEXTERITY", col["magic"]), ("+12% SLIDE DISTANCE", col["magic"]),
        ("+8% LOOT LUCK", col["magic"]), ("+15% CRYO RESIST", col["magic"]),
        ("BATTLE CRY: +20% DAMAGE FOR 3S", col["legendary"]), ("AFTER YOU SHOUT YOUR OWN NAME", col["legendary"]),
        None, ('"AT LEAST I HAVE CHICKEN."', col["flavor"]), None,
    ]
    y = 40
    for line in lines:
        if line is None:
            c.rect(348, y + 2, W - 16, y + 3, (60, 50, 90))
            y += 7
            continue
        text, color = line
        ui.label(c, 348, y, text, color)
        if text == "ARMOR 48":
            ui.label(c, 348 + text_width(text) + 8, y, "+6", col["good"])
        y += 11
    ui.label(c, 348, y, "UPGRADES", (236, 230, 255))
    _pips(c, 348 + text_width("UPGRADES") + 8, y + 1, filled=1, cap=2)
    ui.label(c, 348 + text_width("UPGRADES") + 52, y, "1/2  (CAP AT LV 24)", (150, 140, 180))
    y += 12
    ui.label(c, 348, y, "NEXT: 3 ARMOR GEMS", (255, 214, 64))
    ui.label(c, 348 + text_width("NEXT: 3 ARMOR GEMS") + 8, y, "ARMOR 52, +7 DEX", col["good"])

    ui.panel(c, 8, 256, W - 8, H - 6)
    stats = [("STR", 31), ("CON", 27), ("INT", 18), ("DEX", 29), ("LCK", 15)]
    x = 18
    for name, value in stats:
        ui.label(c, x, 264, name, (150, 140, 180))
        ui.label(c, x + 22, 264, str(value), (236, 230, 255))
        x += 58
    derived = "HP 412   EP 96   ATK 88   DEF 64   CRIT 7%   LOOT LUCK +18%"
    ui.label(c, 18, 278, derived, (236, 230, 255))
    x = 18
    x += ui.counter(c, x, 296, ui.mini_gem("armor", "blue"), "ARMOR GEMS 23") + 18
    x += ui.counter(c, x, 296, ui.mini_gem("weapon", "ruby"), "WEAPON GEMS 11") + 18
    ui.counter(c, x, 296, ui.mini_coin(), "VETRO-BUCKS 4096")
    ui.label(c, 18, 316, "UPGRADE CAP BY LEVEL", (150, 140, 180))
    x = 18
    for band, cap in (("1-12", 1), ("13-24", 2), ("25-36", 3), ("37-49", 4), ("50", 5)):
        text = f"LV {band} X{cap}"
        color = (255, 214, 64) if cap == 2 else (150, 140, 180)
        if cap == 2:
            c.rect(x - 3, 327, x + text_width(text) + 3, 339, (60, 48, 30))
        ui.label(c, x, 330, text, color)
        x += text_width(text) + 20
    ui.label(c, 18, 344, "RINGS: SLOT 1 AT LV 20, SLOT 2 AT LV 37. NO RING DROPS BEFORE LV 20.", (150, 140, 180))
    c.bloom(radius=4, strength=0.6)
    return c


# World map: rooms as rectangles of map cells, grouped by area ---------------------------

AREAS = {
    "C": ("CRASH SITE Z-0", "#6f8cff", [(1, 17, 7, 1), (1, 18, 2, 3)]),
    "H": ("HULL CATHEDRAL", "#8a6cff",
          [(8, 17, 26, 1), (12, 14, 1, 3), (17, 12, 4, 5), (25, 15, 3, 2), (31, 13, 1, 4)]),
    "O": ("OUTER HULL", "#4fb3ff", [(6, 4, 1, 13), (2, 4, 4, 1), (2, 9, 4, 1), (2, 5, 1, 4)]),
    "S": ("SERVER CHAPEL", "#ff7ad8", [(10, 7, 14, 1), (10, 8, 1, 6), (22, 4, 5, 3), (16, 5, 1, 2)]),
    "T": ("CHRONO CLOCKTOWER", "#ffb04a", [(28, 2, 3, 11), (31, 6, 6, 1), (36, 3, 1, 3)]),
    "D": ("LONG DATA ARCHIVE", "#c07aff", [(34, 17, 12, 1), (40, 12, 8, 5)]),
    "L": ("LASER COLOSSEUM", "#ff6a6a", [(46, 14, 7, 4), (48, 18, 1, 3), (53, 15, 3, 1)]),
    "B": ("BIO-LAB LAMBDA", "#6fe07a", [(3, 22, 9, 3), (8, 19, 1, 3), (3, 25, 1, 3)]),
    "K": ("CRYO CAVERNS", "#3fd0d0", [(14, 18, 1, 9), (14, 27, 12, 1), (19, 22, 6, 4), (25, 19, 1, 8)]),
    "A": ("ARCADE NECROPOLIS", "#b0b0c8", [(32, 22, 10, 2), (36, 24, 1, 5), (33, 29, 8, 2)]),
    "M": ("ASTEROID MINE", "#c89a6a", [(26, 29, 7, 1), (28, 30, 1, 3), (22, 32, 7, 1)]),
    "V": ("CYBER-MALL 1996", "#5ff0c8", [(50, 23, 6, 3), (53, 26, 1, 3)]),
    "E": ("ESPRESSO SPIRE", "#ff4a6a", [(19, 0, 3, 4)]),
}
UNDISCOVERED = {"M", "V", "E"}
PARTIAL = {"A": 0.5, "T": 0.7, "L": 0.8}
SAVES = [(3, 17), (20, 17), (41, 13), (21, 27), (47, 15), (37, 23), (10, 7)]
WARPS = [(8, 17), (44, 17), (29, 3), (5, 23)]
BOSSES = [(6, 4), (23, 5), (29, 2), (22, 24), (50, 16), (38, 30), (20, 0), (40, 14)]
SECRETS = [(15, 10), (45, 25), (27, 21)]
HERE = (24, 17)


def world_map() -> Canvas:
    c = Canvas(W, H)
    _backdrop(c)
    _tabs(c, "MAP")
    ox, oy, pitch = 20, 44, 7
    ui.panel(c, 10, 34, 420, 274)
    total = explored = 0
    seen: set[tuple[int, int]] = set()
    for code, (_, color, rooms) in AREAS.items():
        base = hexc(color)
        cells = [(gx, gy) for x0, y0, w, h in rooms for gy in range(y0, y0 + h) for gx in range(x0, x0 + w)]
        total += len(cells)
        if code in UNDISCOVERED:
            continue
        # Partially explored areas are revealed breadth-first from the cell nearest the player, so they stay contiguous.
        pool = set(cells)
        start = min(cells, key=lambda p: (p[0] - HERE[0]) ** 2 + (p[1] - HERE[1]) ** 2)
        order, queue = [start], [start]
        pool.discard(start)
        while queue:
            x, y = queue.pop(0)
            for step in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if step in pool:
                    pool.discard(step)
                    order.append(step)
                    queue.append(step)
        cells = (order + sorted(pool))[: round(len(cells) * PARTIAL.get(code, 1.0))]
        explored += len(cells)
        for gx, gy in cells:
            seen.add((gx, gy))
            px, py = ox + gx * pitch, oy + gy * pitch
            c.rect(px, py, px + pitch - 1, py + pitch - 1, mix(base, INK, 0.45))
            c.rect(px, py, px + pitch - 1, py + 1, mix(base, (255, 255, 255), 0.15))
            c.rect(px, py, px + 1, py + pitch - 1, base)
    for marks, color in ((SAVES, (235, 60, 72)), (WARPS, (250, 210, 70))):
        for gx, gy in marks:
            if (gx, gy) not in seen:
                continue
            px, py = ox + gx * pitch, oy + gy * pitch
            c.rect(px + 1, py + 1, px + pitch - 2, py + pitch - 2, color)
    for gx, gy in BOSSES:
        if (gx, gy) not in seen:
            continue
        px, py = ox + gx * pitch, oy + gy * pitch
        c.rect(px + 2, py + 2, px + 4, py + 4, (255, 255, 255))
    for gx, gy in SECRETS:
        c.text(ox + gx * pitch, oy + gy * pitch - 1, "?", (255, 214, 64))
    hx, hy = HERE
    here = (120, 240, 255)
    c.rect(ox + hx * pitch + 1, oy + hy * pitch + 1, ox + hx * pitch + 5, oy + hy * pitch + 5, here)
    c.add_glow(np.ones((6, 6), bool), here, ox + hx * pitch, oy + hy * pitch, 1.0)

    ui.panel(c, 428, 34, W - 8, 274)
    ui.label(c, 436, 40, "VETROMANIA", (255, 214, 64))
    percent = 100.0 * explored / total
    ui.label(c, 436, 52, f"MAP {percent:.1f}%", (236, 230, 255))
    y = 68
    for code, (name, color, _) in AREAS.items():
        known = code not in UNDISCOVERED
        c.rect(436, y, 442, y + 6, hexc(color) if known else (60, 50, 80))
        ui.label(c, 448, y, name if known else "???", (236, 230, 255) if known else (110, 100, 140))
        y += 11
    ui.panel(c, 10, 280, W - 8, H - 6)
    legend = [((120, 240, 255), "YOU"), ((235, 60, 72), "SAVE POD"), ((250, 210, 70), "WARP PIPE"),
              ((255, 255, 255), "BOSS"), ((255, 214, 64), "? SECRET")]
    x = 20
    for color, text in legend:
        c.rect(x, 290, x + 6, 296, color)
        x += 10 + ui.label(c, x + 10, 290, text) + 16
    ui.label(c, 20, 306, "THE PLANET FLIPS AFTER THE TRUE ENDING: AINAMORTEV ADDS THE OTHER 100%.", (150, 140, 180))
    ui.label(c, 20, 320, "WALLS THAT SOUND HOLLOW WHEN YOU HIT THEM WITH THE BEAM BAT USUALLY ARE.", (150, 140, 180))
    ui.label(c, 20, 334, "BEST COMPLETION: 200.6%. DON'T ASK WHERE THE .6 COMES FROM.", (150, 140, 180))
    c.bloom(radius=4, strength=0.6)
    return c
