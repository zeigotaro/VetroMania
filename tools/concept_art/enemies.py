"""VetroMania bestiary sprites: fantasy monsters, lazily transposed to space.

All enemies face right; scenes flip them to face the player.
"""

from __future__ import annotations

import math

import numpy as np

from characters import chain
from pixel import Sprite, glow, mat

FUR = mat("#4b2a78")
WING = mat("#6d3a9c", dark=0.6)
GLASS = mat("#7ad7f0", 4)
RED_EYE = glow("#ff2a3a")
BONE = mat("#f1ece0", 3)
TANK = mat("#707a94", spec=(255, 255, 255))

SUIT = mat("#d8d2c2")
PATCH = mat("#e0652a")
SKIN = mat("#86a46a")
YELLOW_EYE = glow("#ffe14a")
STEEL = mat("#8e9ab4", spec=(255, 255, 255))

RUST = mat("#b4652f", spec=(255, 228, 196), spec_cut=0.7)
GUNMETAL = mat("#4e4a62")
DISH = mat("#c3c9d6", spec=(255, 255, 255))
AMBER_EYE = glow("#ffb020")
BEACON = glow("#ff3030")

SCALES = mat("#2f9d86")
BELLY = mat("#c3e2a4")
FIN = mat("#e25a78")
WATER = mat("#2f78c8", 4)
BUBBLE = glow("#cfefff")
LASER = glow("#ff6a2a", core="#fff2c0")
EYEBALL = mat("#f4f4ea", 3)

PALE = mat("#cdb6de")
HAIR = mat("#2e2140", dark=0.5)
CAPE = mat("#7a1234")
LINING = mat("#d23a7a")
GOWN = mat("#3a2458")
SILVER = mat("#b8c0d8", spec=(255, 255, 255))
JET = glow("#6ae8ff")
ORB = glow("#ff4fd8")


def _bowl(s: Sprite, cx, cy, r, *, fill_material, fill_index, group):
    """A glass helmet around whatever is already painted inside it."""
    outer = s.mask_ellipse(cx, cy, r + 0.9, r + 0.7)
    inner = s.mask_ellipse(cx, cy, r - 0.1, r - 0.3)
    s.fill(inner & ~s.opaque(), fill_material, fill_index, group=group + "_in")
    rim = outer & ~inner
    s.fill(rim, GLASS, 2, group=group)
    s.fill(rim & (s.x < cx - 1) & (s.y < cy - 1), GLASS, 3, group=group)
    s.fill(s.mask_points([(cx - r * 0.55, cy - r * 0.45), (cx - r * 0.45, cy - r * 0.6),
                          (cx - r * 0.65, cy - r * 0.25)]) & inner, GLASS, 3, group=group)


def space_bat(frame: int) -> Sprite:
    s = Sprite(52, 40)
    cx = 26
    bob = [0, 1, 2, 1][frame % 4]
    wings = [
        [(21, -14), (15, -16), (8, -12)],
        [(23, -5), (17, -8), (10, -8)],
        [(20, 9), (15, 6), (9, 4)],
        [(23, -5), (17, -8), (10, -8)],
    ][frame % 4]
    sy = 18 + bob
    s.paint(s.capsule(cx + 4, sy - 3, cx + 5, sy + 4, 2.1), TANK, group="tank")
    for side in (-1, 1):
        sx = cx + side * 3
        points = [(sx, sy - 1)]
        for k, (tx, ty) in enumerate(wings):
            points.append((sx + side * tx, sy + ty))
            nx, ny = wings[k + 1] if k + 1 < len(wings) else (2, 7)
            points.append((sx + side * (tx + nx) / 2 * 0.72, sy + (ty + ny) / 2 * 0.72 + 3))
        points.append((sx + side * 1, sy + 7))
        membrane = s.paint(s.polygon(points, bevel=1.3), WING, group=f"wing{side}")
        for tx, ty in wings:
            s.shift(s.mask_line([(sx, sy), (sx + side * tx, sy + ty)]) & membrane, 1)
    s.paint(s.ellipse(cx, sy + 3, 5.2, 6.6), FUR, group="body")
    s.shift(s.mask_ellipse(cx + 1, sy + 5, 2.4, 3.4) & s.opaque(), 1)
    s.paint(s.capsule(cx - 2, sy + 9, cx - 3, sy + 12, 1.2), FUR, group="feet")
    s.paint(s.capsule(cx + 2, sy + 9, cx + 3, sy + 12, 1.2), FUR, group="feet")
    head = (cx, sy - 7)
    for side in (-1, 1):
        s.paint(s.polygon([(cx + side * 4.5, head[1] - 1), (cx + side * 5.5, head[1] - 7.5),
                           (cx + side * 1.5, head[1] - 2)], bevel=0.8), FUR, group="ears")
    s.paint(s.ellipse(*head, 4.6, 4.2), FUR, group="head")
    s.fill(s.mask_points([(cx - 2, head[1]), (cx + 1.6, head[1])]), RED_EYE, 3, group="eyes")
    s.fill(s.mask_points([(cx - 1, head[1] + 3), (cx + 1, head[1] + 3)]), BONE, 2, group="fangs")
    _bowl(s, head[0], head[1] - 1, 7.4, fill_material=GLASS, fill_index=0, group="bowl")
    return s


def astro_zombie(frame: int) -> Sprite:
    s = Sprite(52, 80)
    phase = 2 * math.pi * frame / 4
    step = math.sin(phase)
    bob = round(abs(step))
    hx, hy = 22, 52 + bob
    near_leg = (0.25 * step + 0.1, -0.25 - 0.3 * max(0.0, math.cos(phase)))
    far_leg = (-0.35 - 0.15 * step, -0.05)
    for leg, bias, group in ((far_leg, -0.14, "far_leg"), (near_leg, 0.0, "near_leg")):
        (kx, ky), (ax, ay) = chain(hx, hy, *leg[:1], 11, leg[1], 11)
        s.paint(s.capsule(hx, hy, kx, ky, 4.2, 3.6), SUIT, group=group, bias=bias)
        s.paint(s.capsule(kx, ky, ax, ay, 3.6, 3.0), SUIT, group=group, bias=bias)
        s.paint(s.rrect(ax - 4, ay - 2, ax + 6, ay + 4, radius=2, bevel=1.4), PATCH, group=group, bias=bias - 0.05)
    s.paint(s.polygon([(hx + 3, hy + 6), (hx + 6, hy + 9), (hx + 3, hy + 11)], bevel=0.6), SKIN, group="tear1")
    lean = 1 + bob
    arm_y = hy - 22
    for side, bias in ((-1, -0.14), (1, 0.0)):
        if side == 1:
            s.paint(s.capsule(hx, hy - 3, hx + 4, hy - 20, 7.2, 8.0), SUIT, group="torso")
            s.paint(s.ellipse(hx + 5, hy - 15, 2.6, 2.6), mat("#3a6ad0", 4), group="patch")
            s.paint(s.polygon([(hx - 3, hy - 10), (hx + 1, hy - 13), (hx + 2, hy - 7), (hx - 1, hy - 6)], bevel=0.8),
                    SKIN, group="tear2")
            s.paint(s.rrect(hx - 6, hy - 25, hx + 2, hy - 18, radius=2, bevel=1.2), PATCH, group="shoulder")
        shoulder = (hx + 4 + side * 3 + lean, arm_y + (0 if side == 1 else -1))
        droop = 1.42 + 0.06 * math.sin(phase + (0 if side == 1 else 1.4))
        elbow, hand = chain(*shoulder, droop, 9, 0.12, 8)
        s.paint(s.capsule(*shoulder, *elbow, 3.2, 2.9), SUIT, group=f"arm{side}", bias=bias)
        s.paint(s.capsule(*elbow, *hand, 2.9, 2.4), SKIN, group=f"arm{side}", bias=bias)
        s.paint(s.ellipse(hand[0] + 1, hand[1], 2.7, 2.3), SKIN, group=f"arm{side}", bias=bias)
        claws = [(hand[0] + 4, hand[1] - 1), (hand[0] + 4, hand[1] + 1)]
        s.fill(s.mask_points(claws), BONE, 1, group=f"claw{side}")
    neck = (hx + 7 + lean, hy - 27)
    s.paint(s.ellipse(*neck, 7.2, 3.0), STEEL, group="collar")
    head = (neck[0] + 2, neck[1] - 6)
    s.paint(s.ellipse(*head, 5.8, 6.2), SKIN, group="head")
    s.shift(s.mask_ellipse(head[0] + 2.5, head[1] - 1, 1.8, 1.5), -2)
    s.fill(s.mask_points([(head[0] + 3, head[1] - 1)]), YELLOW_EYE, 3, group="eye")
    s.fill(s.mask_line([(head[0] + 1, head[1] + 3), (head[0] + 5, head[1] + 2)]), mat("#3a1a24", 3), 0, group="mouth")
    s.fill(s.mask_points([(head[0] + 2, head[1] + 2), (head[0] + 4, head[1] + 2)]), BONE, 2, group="teeth")
    for tri in ([(head[0] - 7, neck[1] - 1), (head[0] - 5, head[1] - 7), (head[0] - 3, neck[1] - 2)],
                [(head[0] + 6, neck[1] - 1), (head[0] + 9, head[1] - 3), (head[0] + 7, neck[1] - 2)]):
        s.paint(s.polygon(tri, bevel=0.6), GLASS, group="shard")
    return s


def hunch_bot(frame: int) -> Sprite:
    s = Sprite(60, 60)
    lift, squash = [(0, 3), (-7, -1), (-3, 1)][frame % 3]
    gy = 56
    body_y = 30 + lift + squash
    for x0, x1 in ((18, 15), (27, 28)):
        s.paint(s.capsule(x0, body_y + 9, x1, gy - 4 + min(lift, 0) // 2, 3.4, 3.0), GUNMETAL, group=f"leg{x0}")
        s.paint(s.ellipse(x1 + 1.5, gy - 2.5 + min(lift, 0) // 2, 4.4, 2.4), RUST, group=f"foot{x0}")
    s.paint(s.ellipse(22, body_y - 3, 15.5, 13.5), RUST, group="hump")
    rivets = [(12 + 4 * i, body_y - 10 + abs(i - 2)) for i in range(5)]
    s.shift(s.mask_points(rivets) & s.opaque(), 2)
    s.shift(s.mask_line([(8, body_y + 2), (34, body_y - 1)]) & s.opaque(), -1)
    s.paint(s.capsule(18, body_y - 15, 17, body_y - 21, 1.3), DISH, group="mast")
    s.paint(s.ellipse(15, body_y - 22, 7.5, 3.0, angle=-0.35), DISH, group="dish")
    s.fill(s.mask_line([(15, body_y - 22), (21, body_y - 30)]), DISH, 3, group="antenna")
    blink = frame % 3 != 1
    s.paint(s.ellipse(21.5, body_y - 30.5, 1.6, 1.6), BEACON if blink else GUNMETAL, group="beacon")
    shoulder = (33, body_y + 1)
    elbow, hand = chain(*shoulder, 0.55 + (0.5 if lift < -4 else 0.0), 10, -0.35, 10)
    s.paint(s.capsule(*shoulder, *elbow, 3.4, 3.0), GUNMETAL, group="arm")
    s.paint(s.capsule(*elbow, *hand, 3.0, 2.6), RUST, group="arm")
    for dx in (-2.5, 0.0, 2.5):
        s.paint(s.capsule(hand[0] + dx * 0.4, hand[1], hand[0] + dx + 1.5, hand[1] + 3.5, 1.3, 0.8), DISH, group="claw")
    head = s.paint(s.rrect(33, body_y - 6, 45, body_y + 5, radius=3, bevel=1.6), GUNMETAL, group="head")
    grill = (np.floor(s.y) % 2 == 0) & s.mask_rect(36, body_y + 1, 44, body_y + 4)
    s.shift(grill & head, -1)
    s.paint(s.ellipse(41, body_y - 1.5, 2.7, 2.5), AMBER_EYE, group="eye")
    return s


def mer_man(frame: int) -> Sprite:
    s = Sprite(56, 84)
    bob = [0, 1, 1][frame % 3]
    hx, hy = 24, 55 + bob
    for leg, bias, group in (((-0.25, 0.3), -0.14, "far_leg"), ((0.2, -0.2), 0.0, "near_leg")):
        (kx, ky), (ax, ay) = chain(hx, hy, leg[0], 11, leg[1], 11 - bob)
        s.paint(s.capsule(hx, hy, kx, ky, 4.0, 3.3), SCALES, group=group, bias=bias)
        s.paint(s.capsule(kx, ky, ax, ay, 3.3, 2.6), SCALES, group=group, bias=bias)
        s.paint(s.polygon([(ax - 2, ay - 1), (ax + 8, ay + 2), (ax + 6, ay + 4), (ax - 3, ay + 4)], bevel=1.0),
                FIN, group=group, bias=bias)
    s.paint(s.rrect(hx - 11, hy - 26, hx - 4, hy - 12, radius=3, bevel=1.4), STEEL, group="tank")
    torso = s.paint(s.capsule(hx, hy - 3, hx + 2, hy - 20, 7.0, 7.6), SCALES, group="torso")
    scales = ((np.floor(s.x) + 2 * np.floor(s.y)) % 4 == 0) & torso
    s.shift(scales, 1)
    s.paint(s.ellipse(hx + 4, hy - 11, 4.0, 7.5), BELLY, group="belly")
    head = (hx + 5, hy - 32)
    s.paint(s.polygon([(head[0] - 6, head[1] - 2), (head[0] - 2, head[1] - 12), (head[0] + 1, head[1] - 4)],
                      bevel=1.0), FIN, group="crest")
    s.paint(s.ellipse(head[0] + 1, head[1], 7.5, 6.2), SCALES, group="head")
    s.paint(s.ellipse(head[0] + 4, head[1] - 1.5, 2.4, 2.4), EYEBALL, group="eye")
    s.fill(s.mask_points([(head[0] + 5, head[1] - 1)]), GUNMETAL, 0, group="pupil")
    s.fill(s.mask_line([(head[0] + 2, head[1] + 3), (head[0] + 8, head[1] + 2)]), mat("#3a1a24", 3), 0, group="mouth")
    _bowl(s, head[0] + 1, head[1] - 1, 10.5, fill_material=WATER, fill_index=1, group="bowl")
    surface = s.mask_line([(head[0] - 8, head[1] - 7 + bob), (head[0] + 9, head[1] - 7 - bob)])
    s.shift(surface & s.mask_ellipse(head[0] + 1, head[1] - 1, 10.4, 10.2), 2)
    for i, (bx, by) in enumerate(((head[0] - 5, head[1] + 4), (head[0] - 3, head[1] - 2), (head[0] + 7, head[1] + 6))):
        s.paint(s.ellipse(bx, by - ((frame + i) % 3) * 2, 1.2, 1.2), BUBBLE, group=f"bubble{i}")
    shoulder = (hx + 5, hy - 19)
    elbow, hand = chain(*shoulder, 0.9, 8, -1.4, 7)
    s.paint(s.capsule(hand[0] + 1, hand[1] + 14, hand[0] + 3, hand[1] - 34, 1.3), STEEL, group="shaft")
    top = (hand[0] + 3, hand[1] - 34)
    for dx, h in ((-4, 6), (0, 9), (4, 6)):
        s.paint(s.capsule(top[0] + dx, top[1], top[0] + dx, top[1] - h, 1.1), STEEL, group="prong")
        s.paint(s.ellipse(top[0] + dx, top[1] - h - 1.5, 1.3, 2.2 + (frame % 2)), LASER, group="prong_tip")
    s.paint(s.capsule(top[0] - 4, top[1], top[0] + 4, top[1], 1.2), STEEL, group="prong_bar")
    s.paint(s.capsule(*shoulder, *elbow, 3.2, 2.9), SCALES, group="arm")
    s.paint(s.capsule(*elbow, *hand, 2.9, 2.5), SCALES, group="arm")
    s.paint(s.ellipse(hand[0] + 1, hand[1], 2.6, 2.4), BELLY, group="arm")
    return s


def vampress(frame: int) -> Sprite:
    s = Sprite(64, 92)
    bob = [0, -1, -2, -1][frame % 4]
    flutter = [0, 2, 3, 1][frame % 4]
    cx, top = 30, 16 + bob
    hem = top + 58
    cape = [(cx - 5, top + 9), (cx - 18 - flutter, hem - 2), (cx - 10, hem + 2 + flutter // 2),
            (cx - 2, hem - 1), (cx + 7, hem + 1), (cx + 5, top + 12)]
    s.paint(s.polygon(cape, bevel=2.0), CAPE, group="cape")
    for side in (-1, 1):
        s.paint(s.polygon([(cx + side * 3, top + 10), (cx + side * 11, top - 2), (cx + side * 8, top + 12)],
                          bevel=1.0), CAPE if side < 0 else LINING, group=f"collar{side}")
    skirt = [(cx - 5, top + 24), (cx + 6, top + 24), (cx + 11, hem - 2), (cx - 11, hem - 2)]
    s.paint(s.polygon(skirt, bevel=2.0), GOWN, group="gown")
    for i, jx in enumerate((cx - 7, cx, cx + 7)):
        length = 4 + (frame + i) % 3
        s.paint(s.capsule(jx, hem, jx, hem + length, 1.9, 0.7), JET, group=f"jet{i}")
    s.paint(s.capsule(cx, top + 24, cx + 1, top + 12, 5.4, 6.0), GOWN, group="torso")
    s.paint(s.polygon([(cx - 1, top + 15), (cx + 2, top + 18), (cx + 5, top + 15), (cx + 4, top + 19),
                       (cx + 2, top + 21), (cx, top + 19)], bevel=0.6), SILVER, group="emblem")
    s.paint(s.rrect(cx - 5, top + 22, cx + 7, top + 25, radius=1, bevel=1.0), SILVER, group="belt")
    s.paint(s.capsule(cx + 1, top + 11, cx + 2, top + 7, 2.6), PALE, group="neck")
    head = (cx + 3, top + 1)
    s.paint(s.ellipse(head[0] - 3, head[1] - 7, 4.6, 4.2), HAIR, group="bun")
    for side in (-1, 1):
        s.paint(s.polygon([(head[0] - 3 + side * 2, head[1] - 9), (head[0] - 3 + side * 7, head[1] - 15),
                           (head[0] - 3 + side * 4, head[1] - 8)], bevel=0.8), SILVER, group=f"ornament{side}")
    s.paint(s.ellipse(head[0], head[1], 5.0, 5.8), PALE, group="face")
    s.paint(s.polygon([(head[0] - 6, head[1] - 5), (head[0] + 3, head[1] - 6.5), (head[0] + 1, head[1] - 4),
                       (head[0] - 3, head[1] - 3), (head[0] - 4, head[1] + 6), (head[0] - 6.5, head[1] + 4)],
                      bevel=1.0), HAIR, group="hair")
    s.fill(s.mask_points([(head[0] + 3, head[1] - 1), (head[0] + 1, head[1] - 1)]), RED_EYE, 3, group="eyes")
    s.fill(s.mask_points([(head[0] + 3, head[1] + 3)]), CAPE, 3, group="lips")
    shoulder = (cx + 5, top + 13)
    elbow, hand = chain(*shoulder, 1.9, 8, 0.5, 7)
    s.paint(s.capsule(*shoulder, *elbow, 2.6, 2.3), GOWN, group="arm")
    s.paint(s.capsule(*elbow, *hand, 2.3, 1.9), PALE, group="arm")
    s.paint(s.ellipse(hand[0] + 3, hand[1] - 3, 3.2 + (frame % 2) * 0.5, 3.2 + (frame % 2) * 0.5), ORB, group="orb")
    return s


ENEMIES = {
    "space_bat": (space_bat, 4),
    "astro_zombie": (astro_zombie, 4),
    "hunch_bot": (hunch_bot, 3),
    "mer_man": (mer_man, 3),
    "vampress": (vampress, 4),
}
