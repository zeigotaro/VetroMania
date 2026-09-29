"""Inventory icons: gear slots, weapons, upgrade gems and gem packs, currency, and the card."""

from __future__ import annotations

import math

import numpy as np

from characters import ARMOR, BEAM, GRIP, LEATHER, MUZZLE, STEEL, VISOR
from pixel import Material, Sprite, glow, hexc, mat, mix, ramp

GOLD = mat("#f2b632", spec=(255, 248, 214), spec_cut=0.55)
SILVER = mat("#b8c0d8", spec=(255, 255, 255))
DARK = mat("#2a2f5c", dark=0.55)
MAG = glow("#39e6ff")
WHIP = glow("#9dff6a", core="#f4ffe0")
GEMS = {
    "white": Material(ramp("#dfe6ff", 5, light=0.8), spec=(255, 255, 255), spec_power=6, spec_cut=0.35),
    "blue": Material(ramp("#2f7cf0", 5), spec=(255, 255, 255), spec_power=6, spec_cut=0.35),
    "ruby": Material(ramp("#d81f4a", 5), spec=(255, 255, 255), spec_power=6, spec_cut=0.35),
}
PACK_SIZE = {"white": 1, "blue": 3, "ruby": 5}
RARITY = {
    "common": "#d8d8e0", "magic": "#4f86ff", "rare": "#ffd23a", "legendary": "#ff8a1c", "set": "#3fe07a",
}
S = 24


def _icon() -> Sprite:
    return Sprite(S, S)


def helm() -> Sprite:
    s = _icon()
    s.paint(s.ellipse(11.5, 12.5, 8.5, 8.0), ARMOR)
    s.paint(s.polygon([(5, 7), (21, 8), (20, 10.5), (9, 10)], bevel=1.0), ARMOR, bias=0.1)
    s.paint(s.polygon([(9, 11), (19.5, 11), (19.5, 15.5), (15, 16.5), (9, 15)], bevel=1.2), VISOR)
    s.paint(s.ellipse(6, 16, 2.0, 1.6), GOLD)
    return s


def chest() -> Sprite:
    s = _icon()
    for x in (5, 19):
        s.paint(s.ellipse(x, 7, 4.5, 3.8), ARMOR, bias=-0.05)
    plate = s.paint(s.rrect(5, 4, 19, 20, radius=5, bevel=2.2), ARMOR)
    s.shift(s.mask_rect(9, 4, 10, 20) & plate, 2)
    s.shift(s.mask_rect(14, 4, 15, 20) & plate, 2)
    s.paint(s.ellipse(12, 11, 2.4, 2.4), MUZZLE)
    s.paint(s.rrect(6, 18, 18, 21, radius=1, bevel=1.0), GOLD)
    return s


def gauntlets() -> Sprite:
    s = _icon()
    for dx, bias in ((-4, -0.12), (3, 0.0)):
        s.paint(s.capsule(8 + dx, 5, 13 + dx, 19, 4.0, 3.4), ARMOR, bias=bias)
        for t in (0.25, 0.6):
            y = 5 + 14 * t
            s.paint(s.ellipse(8 + dx + 5 * t, y, 4.3, 1.4), GOLD, bias=bias)
    return s


def gloves() -> Sprite:
    s = _icon()
    s.paint(s.rrect(5, 12, 13, 21, radius=2, bevel=1.5), GOLD, bias=-0.05)
    s.paint(s.ellipse(12, 13, 6.0, 5.5), DARK)
    for x, top in ((8, 4), (11, 3), (14, 4), (17, 6)):
        s.paint(s.capsule(x, 11, x + 0.5, top, 1.7, 1.4), DARK)
        s.shift(s.mask_points([(x, top + 1)]), 2)
    s.paint(s.capsule(6.5, 14, 3.5, 10, 1.8, 1.4), DARK)
    return s


def leggings() -> Sprite:
    s = _icon()
    for x, bias in ((8, -0.1), (15, 0.0)):
        s.paint(s.capsule(x, 3, x + 0.5, 21, 3.3, 2.6), DARK, bias=bias)
        s.paint(s.capsule(x + 0.5, 13, x + 0.5, 21, 3.4, 2.8), ARMOR, bias=bias)
        s.paint(s.ellipse(x + 0.5, 12, 3.0, 2.6), GOLD, bias=bias)
    s.paint(s.rrect(4, 2, 19, 5, radius=1, bevel=1.0), GOLD)
    return s


def boots() -> Sprite:
    s = _icon()
    s.paint(s.polygon([(7, 3), (14, 3), (14, 13), (21, 16), (21, 21), (5, 21), (5, 14)], bevel=1.8), ARMOR)
    s.paint(s.rrect(4, 19, 21, 22, radius=1, bevel=0.8), STEEL, bias=-0.1)
    s.fill(s.mask_rect(6, 17, 20, 18) & s.opaque(), MAG, 2)
    s.paint(s.ellipse(10.5, 4, 4.2, 1.8), GOLD)
    return s


def ring(kind: str) -> Sprite:
    s = _icon()
    material = GOLD if kind == "band" else SILVER
    band = s.mask_ellipse(12, 13, 8.5, 7.0) & ~s.mask_ellipse(12, 13, 5.2, 4.2)
    s.paint(s.from_mask(band, bevel=1.6), material)
    if kind == "band":
        s.paint(s.polygon([(9, 6), (12, 2.5), (15, 6), (12, 9)], bevel=1.0), GEMS["ruby"])
    else:
        halo = s.mask_ellipse(12, 5, 7.5, 2.4) & ~s.mask_ellipse(12, 5, 5.5, 1.2)
        s.fill(halo, glow("#fff2a0"), 2)
    return s


def beam_bat() -> Sprite:
    s = _icon()
    s.paint(s.capsule(4, 20, 8, 16, 1.6), GRIP)
    s.paint(s.ellipse(3.5, 20.5, 2.0, 2.0), STEEL)
    s.paint(s.capsule(9, 15, 20, 4, 1.8, 3.4), BEAM)
    return s


def mitt_cannon() -> Sprite:
    s = _icon()
    s.paint(s.capsule(12, 12, 21, 12, 2.4, 2.0), STEEL)
    s.paint(s.ellipse(21.5, 12, 1.4, 2.4), MUZZLE)
    s.paint(s.ellipse(10, 12, 7.0, 7.5), LEATHER)
    s.paint(s.ellipse(5.5, 7.5, 2.6, 3.4, angle=-0.6), LEATHER, bias=0.1)
    lace = s.mask_ellipse(10, 12, 6.2, 6.7) & ~s.mask_ellipse(10, 12, 5.0, 5.5)
    s.fill(lace & ((np.floor(s.x) + np.floor(s.y)) % 3 == 0) & s.opaque(), mat("#f3dca4", 3), 1)
    return s


def plasma_whip() -> Sprite:
    s = _icon()
    points = [(12 + (8 - t * 0.45) * math.cos(t), 11 + (8 - t * 0.45) * math.sin(t) * 0.8)
              for t in np.linspace(0.3, 11.5, 40)]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        s.paint(s.capsule(x0, y0, x1, y1, 1.3), WHIP, group="whip")
    s.paint(s.capsule(3, 21, 8, 16, 1.8), GRIP)
    s.paint(s.ellipse(8.5, 15.5, 2.0, 2.0), SILVER)
    return s


def _armor_gem(s: Sprite, color: str, cx: float, cy: float, r: float) -> None:
    """Hexagonal 'shield cut' gem used to upgrade armor and rings."""
    outer = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 7)[:-1] + math.pi / 6]
    inner = [(cx + r * 0.5 * math.cos(a), cy - r * 0.08 + r * 0.5 * math.sin(a))
             for a in np.linspace(0, 2 * math.pi, 7)[:-1] + math.pi / 6]
    gem = s.paint(s.polygon(outer, bevel=r * 0.35), GEMS[color])
    s.shift(s.mask_polygon(inner) & gem, 1)
    for (x0, y0), (x1, y1) in zip(inner, outer):
        s.shift(s.mask_line([(x0, y0), (x1, y1)]) & gem, -1)


def _weapon_gem(s: Sprite, color: str, cx: float, cy: float, r: float) -> None:
    """Elongated 'blade cut' gem used to upgrade weapons."""
    points = [(cx, cy - r * 1.25), (cx + r * 0.62, cy - r * 0.1), (cx, cy + r * 1.25), (cx - r * 0.62, cy - r * 0.1)]
    gem = s.paint(s.polygon(points, bevel=r * 0.3), GEMS[color])
    s.shift(s.mask_line([(cx, cy - r * 1.1), (cx, cy + r * 1.1)]) & gem, 1)
    s.shift(s.mask_line([(cx - r * 0.55, cy - r * 0.1), (cx + r * 0.55, cy - r * 0.1)]) & gem, -1)


def gem(kind: str, color: str) -> Sprite:
    s = _icon()
    (_armor_gem if kind == "armor" else _weapon_gem)(s, color, 12, 12, 8.5)
    return s


def gem_pack(kind: str, color: str) -> Sprite:
    """A drop of 1 (white), 3 (blue), or 5 (ruby) gems of one kind."""
    s = _icon()
    count = PACK_SIZE[color]
    draw = _armor_gem if kind == "armor" else _weapon_gem
    if count == 1:
        spots, r = [(12, 12)], 7.5
    elif count == 3:
        spots, r = [(7.5, 15), (16.5, 15), (12, 7.5)], 4.8
    else:
        spots, r = [(12, 6), (5.5, 11), (18.5, 11), (8, 18), (16, 18)], 4.0
    for x, y in spots:
        draw(s, color, x, y, r)
    return s


def vetro_buck() -> Sprite:
    s = _icon()
    coin = s.paint(s.ellipse(12, 12, 8.5, 8.5), GOLD)
    s.shift(s.mask_ellipse(12, 12, 6.5, 6.5) & ~s.mask_ellipse(12, 12, 5.5, 5.5) & coin, -1)
    v = s.mask_line([(8.5, 8), (12, 16), (15.5, 8)], width=2)
    s.shift(v & coin, -2)
    return s


def spaceball_card(frame: int = 0, frames: int = 6) -> Sprite:
    """The MacGuffin: a holo-foil 1994 Bobson Dugnutt rookie card."""
    s = Sprite(24, 32)
    card = s.paint(s.rrect(2, 1, 21, 30, radius=2, bevel=1.2), GOLD)
    window = s.mask_rrect(4, 3, 19, 22, radius=1)
    sky = mat("#3a6ad0", 4)
    for i, (y0, y1) in enumerate(((3, 9), (9, 15), (15, 23))):
        s.fill(window & s.mask_rect(0, y0, 24, y1), sky, 3 - i)
    s.paint(s.polygon([(6, 22), (8, 15), (15, 15), (17, 22)], bevel=1.0), mat("#f2efe6", 4))
    s.fill(s.mask_rect(9, 15, 10, 22) | s.mask_rect(13, 15, 14, 22), mat("#3565d8", 3), 1)
    s.paint(s.ellipse(11.5, 11.5, 3.2, 3.4), mat("#e0a878", 4))
    s.paint(s.polygon([(8, 10), (15, 9.5), (17.5, 11), (15, 11.5), (8.5, 11.5)], bevel=0.8), mat("#d8243a", 4))
    s.paint(s.capsule(15, 18, 19, 6, 1.0, 1.4), mat("#c89058", 4))
    s.fill(s.mask_rect(4, 24, 20, 28), mat("#f2efe6", 3), 2)
    s.fill(s.mask_rect(6, 25, 18, 26) & (np.floor(s.x) % 3 != 0), mat("#2a2f5c", 3), 0)
    band = (s.x + s.y) - (frame / frames) * 56 + 6
    shimmer = (band > 0) & (band < 5) & card
    s.shift(shimmer, 2)
    return s


def rarity_frame(rarity: str, size: int = 28):
    """An inventory slot: dark panel, rarity-colored border, bright corner brackets."""
    from PIL import Image

    color = np.array(hexc(RARITY[rarity]))
    img = np.zeros((size, size, 4), np.uint8)
    img[..., :3] = (26, 20, 40)
    img[..., 3] = 255
    y, x = np.mgrid[0:size, 0:size]
    edge = (x == 0) | (y == 0) | (x == size - 1) | (y == size - 1)
    inner = (x == 1) | (y == 1) | (x == size - 2) | (y == size - 2)
    img[edge, :3] = (color * 0.55).astype(np.uint8)
    img[inner & ~edge, :3] = (np.array(mix(tuple(color), (26, 20, 40), 0.7))).astype(np.uint8)
    corner = ((x < 4) | (x > size - 5)) & ((y < 4) | (y > size - 5)) & (edge | inner)
    img[corner, :3] = color
    glow_mask = (x > 1) & (x < size - 2) & (y > 1) & (y < size - 2)
    depth = np.clip(1 - np.minimum.reduce([x, y, size - 1 - x, size - 1 - y]) / 6, 0, 1)
    img[glow_mask, :3] = (img[glow_mask, :3] * (1 - depth[glow_mask, None] * 0.25)
                          + color * depth[glow_mask, None] * 0.25).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


GEAR = {
    "Helm-Visor": helm, "Chest Carapace": chest, "Power Gauntlets": gauntlets, "Grip Gloves": gloves,
    "Leg Servos": leggings, "Mag-Boots": boots, "Quantum Band": lambda: ring("band"), "Halo Loop": lambda: ring("halo"),
}
WEAPONS = {"Beam Bat": beam_bat, "Mitt Cannon": mitt_cannon, "Plasma Whip": plasma_whip}


def framed(sprite: Sprite, rarity: str):
    frame = rarity_frame(rarity)
    frame.alpha_composite(sprite.render(), (2, 2))
    return frame
