"""Environment art: a 16x16 space-gothic tileset and parallax background layers."""

from __future__ import annotations

import math

import numpy as np

from pixel import Canvas, Sprite, glow, hexc, mat, quantize, value_noise

TILE = 16
STEEL = mat("#5d6788", spec=(236, 244, 255), spec_cut=0.8)
STONE = mat("#463b66", dark=0.55)
BACK = mat("#2a2340", dark=0.5, light=0.3)
COPPER = mat("#b06a3a", spec=(255, 226, 190), spec_cut=0.7)
HAZARD = mat("#f2b632", 3)
INKY = mat("#1c1628", 3)
VINE = mat("#2f9c78")
CONDUIT = glow("#39e6ff")
BULB = glow("#9dff6a")
PANEL = glow("#6ae8ff", core="#e8fdff")


def _tile() -> Sprite:
    return Sprite(TILE, TILE)


def floor_top() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=2), STEEL)
    stripes = s.mask_rect(0, 3, 16, 6) & ((np.floor(s.x) - np.floor(s.y)) % 6 < 3)
    s.fill(stripes, HAZARD, 1)
    s.fill(s.mask_rect(0, 3, 16, 6) & ~stripes, INKY, 1)
    s.shift(s.mask_points([(3, 10), (12, 10)]), 2)
    return s


def floor_fill() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=2), STEEL, bias=-0.1)
    s.shift(s.mask_line([(0, 8), (15, 8)]), -1)
    s.shift(s.mask_points([(3, 4), (12, 4), (3, 12), (12, 12)]), 2)
    return s


def brick() -> Sprite:
    s = _tile()
    for y0, offset in ((0, 0), (8, 8)):
        for x0 in (-16, 0, 16):
            x = x0 + offset
            s.paint(s.rrect(x, y0, x + 15, y0 + 7, radius=1, bevel=1.6), STONE)
    s.shift(s.mask_points([(5, 3), (12, 11), (2, 13)]), -1)
    return s


def brick_conduit() -> Sprite:
    s = brick()
    s.paint(s.rrect(0, 6, 15, 9, radius=1, bevel=1), INKY)
    s.paint(s.capsule(0, 7.5, 16, 7.5, 1.0), CONDUIT)
    return s


def back_wall() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=0, bevel=1.5), BACK)
    for x in (4, 11):
        s.paint(s.capsule(x, 0, x, 16, 1.4), BACK, bias=0.12)
    return s


def pipe(vertical: bool = False) -> Sprite:
    s = _tile()
    if vertical:
        s.paint(s.capsule(8, -2, 8, 18, 4.5, bulge=1.0), COPPER)
        s.paint(s.rrect(2, 6, 13, 9, radius=1, bevel=1.2), STEEL)
    else:
        s.paint(s.capsule(-2, 8, 18, 8, 4.5), COPPER)
        s.paint(s.rrect(6, 2, 9, 13, radius=1, bevel=1.2), STEEL)
    return s


def grate() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=1.5), STEEL, bias=-0.15)
    slots = s.mask_rect(2, 2, 14, 14) & (np.floor(s.y) % 3 == 0)
    s.fill(slots, INKY, 0)
    return s


def platform() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 5, radius=1, bevel=1.5), STEEL)
    s.fill(s.mask_rect(0, 5, 16, 7) & ((np.floor(s.x) + 1) % 4 < 2), HAZARD, 1)
    s.fill(s.mask_rect(0, 5, 16, 7) & ((np.floor(s.x) + 1) % 4 >= 2), INKY, 1)
    return s


def light_panel() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=1.5), STEEL, bias=-0.1)
    s.paint(s.rrect(3, 2, 12, 13, radius=2, bevel=2.0), PANEL)
    return s


def vine() -> Sprite:
    s = _tile()
    for x0, x1, length in ((4, 3, 14), (11, 12, 10)):
        s.paint(s.capsule(x0, -1, x1, length, 1.3, 0.8), VINE)
        s.paint(s.ellipse(x1, length + 0.5, 1.6, 1.6), BULB)
    return s


def hazard_block() -> Sprite:
    s = _tile()
    s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=1.5), STEEL)
    stripes = s.mask_rect(2, 2, 14, 14) & ((np.floor(s.x) + np.floor(s.y)) % 8 < 4)
    s.fill(stripes, HAZARD, 1)
    s.fill(s.mask_rect(2, 2, 14, 14) & ~stripes, INKY, 1)
    return s


def pillar() -> Sprite:
    s = _tile()
    s.paint(s.rrect(2, 0, 13, 15, radius=0, bevel=3.0), STONE, bias=0.05)
    s.shift(s.mask_line([(7, 0), (7, 15)]), 1)
    return s


TILES = {
    "floor_top": floor_top, "floor_fill": floor_fill, "brick": brick, "brick_conduit": brick_conduit,
    "back_wall": back_wall, "pipe_h": pipe, "pipe_v": lambda: pipe(True), "grate": grate,
    "platform": platform, "light_panel": light_panel, "vine": vine, "hazard": hazard_block, "pillar": pillar,
}


def render_tiles() -> dict[str, tuple]:
    """Tiles render without outlines or contact shadows so they tile seamlessly."""
    out = {}
    for name, build in TILES.items():
        s = build()
        out[name] = (s.render(outline=False, contact=False), s.emission())
    return out


def pointed_arch(s: Sprite, x0: float, x1: float, spring: float, bottom: float) -> np.ndarray:
    """Equilateral gothic arch: a rectangle capped by two intersecting circles."""
    span = x1 - x0
    body = (s.x >= x0) & (s.x < x1) & (s.y >= spring) & (s.y < bottom)
    cap = (s.y < spring) & ((s.x - x0) ** 2 + (s.y - spring) ** 2 < span ** 2) \
        & ((s.x - x1) ** 2 + (s.y - spring) ** 2 < span ** 2)
    return body | cap


def gothic_window(stars_seed: int = 7) -> tuple:
    """A 32x48 pointed-arch window prop looking out on the starfield."""
    s = Sprite(32, 48)
    frame = pointed_arch(s, 2, 30, 20, 47)
    s.paint(s.from_mask(frame, bevel=3.0), STONE, bias=0.08)
    inner = pointed_arch(s, 6, 26, 21, 44)
    s.fill(inner, INKY, 0)
    rng = np.random.default_rng(stars_seed)
    points = [(rng.uniform(7, 25), rng.uniform(9, 43)) for _ in range(14)]
    s.fill(s.mask_points(points) & inner, mat("#e8f0ff", 3), 2)
    s.fill(s.mask_rect(15, 5, 17, 44) & inner, STONE, 1)
    s.fill(s.mask_rect(6, 27, 26, 29) & inner, STONE, 1)
    return s.render(contact=False), s.emission()


# Parallax background layers ------------------------------------------------------

NEBULA = ["#0b0718", "#140c2c", "#22103f", "#381452", "#5a1a63", "#86306e", "#b5507a", "#2a6f8f"]


def sky(canvas: Canvas, seed: int = 3, palette=NEBULA) -> None:
    h, w = canvas.h, canvas.w
    gradient = np.linspace(0.0, 0.55, h)[:, None] * np.ones((1, w))
    cloud = value_noise(w, h, 96, seed, octaves=5)
    wisps = value_noise(w, h, 40, seed + 1, octaves=3)
    field = np.clip(gradient * 0.55 + (cloud - 0.35) * 1.1 + (wisps - 0.5) * 0.35, 0, 1)
    colors = quantize(field * 0.86, palette[:-1])
    teal = (value_noise(w, h, 70, seed + 2, octaves=4) > 0.74) & (field > 0.45)
    colors[teal] = colors[teal] * 0.72 + np.array(hexc(palette[-1])) / 255.0 * 0.28
    canvas.rgb[:] = colors


def stars(canvas: Canvas, seed: int = 5, count: int = 260) -> None:
    rng = np.random.default_rng(seed)
    tints = [(255, 255, 255), (190, 220, 255), (255, 236, 190), (255, 190, 230)]
    for _ in range(count):
        x, y = int(rng.integers(0, canvas.w)), int(rng.integers(0, canvas.h))
        tint = np.array(tints[rng.integers(0, len(tints))]) / 255.0
        bright = rng.random()
        canvas.rgb[y, x] = np.maximum(canvas.rgb[y, x], tint * (0.45 + 0.55 * bright))
        if bright > 0.93:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < canvas.w and 0 <= y + dy < canvas.h:
                    canvas.rgb[y + dy, x + dx] = np.maximum(canvas.rgb[y + dy, x + dx], tint * 0.55)
            canvas.glow[y, x] += tint * 0.8


def planet(canvas: Canvas, cx: float, cy: float, r: float, *, seed: int = 11, ring: bool = True,
           palette=("#2b1430", "#5a2238", "#9a3c3a", "#d0703f", "#f0a860", "#ffe0a0")) -> None:
    """A banded gas giant with a dithered terminator and a tilted ring."""
    h, w = canvas.h, canvas.w
    y, x = np.mgrid[0:h, 0:w] + 0.5
    tilt = -0.28
    c, s = math.cos(tilt), math.sin(tilt)

    def ring_mask(front: bool):
        u = ((x - cx) * c + (y - cy) * s) / r
        v = (-(x - cx) * s + (y - cy) * c) / r
        radius = np.sqrt(u * u + (v / 0.26) ** 2)
        band = (radius > 1.35) & (radius < 2.05) & ~((radius > 1.62) & (radius < 1.7))
        return band & ((v > 0) if front else (v <= 0)), radius

    ring_colors = [np.array(hexc(p)) / 255.0 for p in ("#7a5a70", "#c8a088", "#f0d4b0")]

    def draw_ring(front: bool):
        mask, radius = ring_mask(front)
        level = np.clip(((radius - 1.35) / 0.7 * 3).astype(int), 0, 2)
        shade = 1.0 if front else 0.7
        for i in range(3):
            canvas.rgb[mask & (level == i)] = ring_colors[2 - i] * shade

    if ring:
        draw_ring(False)
    dx, dy = (x - cx) / r, (y - cy) / r
    disk = dx * dx + dy * dy <= 1.0
    nz = np.sqrt(np.clip(1 - dx * dx - dy * dy, 0, 1))
    light = np.clip(dx * -0.62 + dy * -0.42 + nz * 0.66, 0, 1)
    swirl = value_noise(w, h, 22, seed, octaves=3)
    bands = 0.5 + 0.5 * np.sin(dy * 11 + swirl * 3.2)
    shade = np.clip(light * (0.72 + 0.28 * bands), 0, 1)
    colors = quantize(shade, palette)
    canvas.rgb[disk] = colors[disk]
    rim = disk & (dx * dx + dy * dy > 0.86) & (dx < 0.2) & (dy < 0.3)
    canvas.rgb[rim] = canvas.rgb[rim] * 0.5 + np.array([1.0, 0.85, 0.6]) * 0.5
    if ring:
        draw_ring(True)


def spires(canvas: Canvas, *, seed: int, base_y: int, color: str, window: str, heights=(40, 120),
           count: int = 16, widths=(10, 24), lit: float = 0.35, rim: str | None = None) -> None:
    """A skyline of space-gothic towers with pointed roofs, antennas, and lit windows."""
    rng = np.random.default_rng(seed)
    h, w = canvas.h, canvas.w
    y, x = np.mgrid[0:h, 0:w] + 0.5
    body = np.zeros((h, w), bool)
    windows = np.zeros((h, w), bool)
    for _ in range(count):
        width = rng.integers(*widths)
        left = rng.uniform(-10, w)
        top = base_y - rng.uniform(*heights)
        body |= (x >= left) & (x < left + width) & (y >= top) & (y <= h)
        peak = top - width * rng.uniform(0.9, 1.6)
        mid = left + width / 2
        roof = (y < top + 1) & (y >= peak) & (np.abs(x - mid) <= (y - peak) / (top - peak) * (width / 2 + 1))
        body |= roof
        antenna = (np.abs(x - mid) < 0.6) & (y >= peak - rng.uniform(4, 14)) & (y < peak)
        body |= antenna
        for _ in range(int(width * (base_y - top) / 90)):
            wx = left + rng.uniform(2, width - 3)
            wy = rng.uniform(top + 4, min(base_y, h) - 4)
            if rng.random() < lit:
                windows |= (x >= int(wx)) & (x < int(wx) + 2) & (y >= int(wy)) & (y < int(wy) + 3)
    fill = np.array(hexc(color)) / 255.0
    canvas.rgb[body] = fill
    if rim is not None:
        edge = body & ~np.roll(body, 1, axis=1)
        canvas.rgb[edge] = np.array(hexc(rim)) / 255.0
    lamp = np.array(hexc(window)) / 255.0
    canvas.rgb[windows & body] = lamp
    canvas.glow[windows & body] += lamp * 0.6


def colonnade(canvas: Canvas, *, top: int, bottom: int, spacing: int, color: str, light: str,
              offset: int = 0) -> np.ndarray:
    """A wall pierced by pointed (equilateral) arches; returns the wall mask."""
    h, w = canvas.h, canvas.w
    y, x = np.mgrid[0:h, 0:w] + 0.5
    wall = (y >= top) & (y < bottom)
    pillar = 12
    spring = top + (bottom - top) * 0.45
    for left in range(offset - spacing, w + spacing, spacing):
        xl, xr = left + pillar, left + spacing
        span = xr - xl
        opening = (x >= xl) & (x < xr) & (y >= spring) & (y < bottom)
        arch = ((y < spring) & ((x - xl) ** 2 + (y - spring) ** 2 < span ** 2)
                & ((x - xr) ** 2 + (y - spring) ** 2 < span ** 2))
        wall &= ~(opening | arch)
    base = np.array(hexc(color)) / 255.0
    canvas.rgb[wall] = base
    lit = wall & ~np.roll(wall, 1, axis=1)
    canvas.rgb[lit] = np.array(hexc(light)) / 255.0
    course = wall & ((np.floor(y) - top) % 22 == 0)
    canvas.rgb[course] = base * 0.7
    return wall
