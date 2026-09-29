"""HUD and menu widgets drawn straight onto a scene Canvas."""

from __future__ import annotations

import numpy as np

from pixel import INK, Canvas, Sprite, mix, text_width
from items import _armor_gem, _weapon_gem

PANEL = (22, 16, 36)
EDGE = (92, 78, 140)
TEXT = (236, 230, 255)
DIM = (150, 140, 180)
COLORS = {
    "common": (216, 216, 224), "magic": (104, 150, 255), "rare": (255, 214, 64),
    "legendary": (255, 138, 28), "set": (64, 224, 122), "flavor": (196, 170, 128),
    "good": (96, 232, 120), "bad": (255, 84, 96),
}


def panel(c: Canvas, x0: int, y0: int, x1: int, y1: int, *, edge=EDGE, fill=PANEL, alpha: float = 0.92) -> None:
    """A bevelled UI panel with a lit top-left edge and bright corner studs."""
    c.rect(x0, y0, x1, y1, fill, alpha)
    c.rect(x0, y0, x1, y0 + 1, edge)
    c.rect(x0, y0, x0 + 1, y1, edge)
    c.rect(x0, y1 - 1, x1, y1, mix(edge, INK, 0.6))
    c.rect(x1 - 1, y0, x1, y1, mix(edge, INK, 0.6))
    for cx, cy in ((x0, y0), (x1 - 2, y0), (x0, y1 - 2), (x1 - 2, y1 - 2)):
        c.rect(cx, cy, cx + 2, cy + 2, mix(edge, (255, 255, 255), 0.4))


def bar(c: Canvas, x: int, y: int, width: int, height: int, fraction: float, color, *, glow: bool = True) -> None:
    """A segmented meter: dark trough, two-tone fill, and a bright top highlight."""
    c.rect(x - 1, y - 1, x + width + 1, y + height + 1, INK)
    c.rect(x, y, x + width, y + height, mix(color, INK, 0.75))
    filled = int(round(width * fraction))
    c.rect(x, y, x + filled, y + height, color)
    c.rect(x, y, x + filled, y + 1, mix(color, (255, 255, 255), 0.55))
    c.rect(x, y + height - 1, x + filled, y + height, mix(color, INK, 0.35))
    for tick in range(x + 8, x + width, 8):
        c.rect(tick, y, tick + 1, y + height, mix(color, INK, 0.5), alpha=0.6)
    if glow:
        mask = np.ones((height, filled), bool)
        c.add_glow(mask, color, x, y, strength=0.35)


def label(c: Canvas, x: int, y: int, text: str, color=TEXT, *, scale: int = 1, backing: bool = False) -> int:
    width = text_width(text, scale)
    if backing:
        c.rect(x - 3, y - 2, x + width + 3, y + 7 * scale + 2, INK, alpha=0.8)
    c.text(x, y, text, color, scale=scale)
    return width


def mini_gem(kind: str, color: str):
    s = Sprite(12, 12)
    (_armor_gem if kind == "armor" else _weapon_gem)(s, color, 6, 6, 4.2)
    return s.render()


def mini_coin():
    from items import GOLD

    s = Sprite(12, 12)
    coin = s.paint(s.ellipse(6, 6, 4.6, 4.6), GOLD)
    s.shift(s.mask_line([(4, 4), (6, 8), (8, 4)]) & coin, -2)
    return s.render()


def minimap(c: Canvas, x: int, y: int, *, cols: int = 9, rows: int = 6, here=(4, 3), seed: int = 4,
            color=(88, 108, 220), save=(2, 1), warp=(7, 4)) -> None:
    rng = np.random.default_rng(seed)
    panel(c, x - 4, y - 4, x + cols * 8 + 3, y + rows * 6 + 3)
    for gy in range(rows):
        for gx in range(cols):
            if rng.random() < 0.28 and (gx, gy) not in (here, save, warp):
                continue
            tone = color
            if (gx, gy) == save:
                tone = (230, 60, 70)
            elif (gx, gy) == warp:
                tone = (250, 210, 70)
            c.rect(x + gx * 8, y + gy * 6, x + gx * 8 + 7, y + gy * 6 + 5, mix(tone, INK, 0.25))
            c.rect(x + gx * 8, y + gy * 6, x + gx * 8 + 7, y + gy * 6 + 1, mix(tone, (255, 255, 255), 0.3))
    hx, hy = here
    c.rect(x + hx * 8 + 2, y + hy * 6 + 1, x + hx * 8 + 5, y + hy * 6 + 4, (255, 255, 255))
    c.add_glow(np.ones((3, 3), bool), (255, 255, 255), x + hx * 8 + 2, y + hy * 6 + 1, 0.8)


def counter(c: Canvas, x: int, y: int, icon, text: str) -> int:
    c.blit(icon, x, y - 2)
    return 14 + label(c, x + 14, y, text)
