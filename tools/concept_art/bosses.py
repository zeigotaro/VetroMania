"""HotCoffee: the evil android who stole Sleve's favorite spaceball card.

A chrome chassis in a barista apron, with a glass coffee-carafe head (red eyes
glowing in the coffee), a warming-plate core, and a giant Mug Cannon.
"""

from __future__ import annotations

import numpy as np

from characters import chain
from pixel import Material, Sprite, glow, mat, ramp, text_mask

CHROME = Material(ramp("#95a1bd", 6, dark=0.72, light=0.85), spec=(255, 255, 255), spec_power=12, spec_cut=0.5)
JOINT = mat("#343a52")
PLASTIC = mat("#262434", dark=0.5, light=0.35)
GLASS = mat("#9fe0f2", 4)
AIR = mat("#1f2c46", 3)
COFFEE = mat("#5a2c14", 4)
CREMA = mat("#c08a4a", 3)
APRON = mat("#1f7a4a")
TAG = mat("#efe6d2", 3)
CERAMIC = mat("#ece8f2", spec=(255, 255, 255))
CORE = glow("#ff5a1f", core="#fff0b0")
EYES = glow("#ff1f3a")
STEAM = glow("#d9d2ec", core="#ffffff", steps=3)

W, H = 156, 200


def hot_coffee(frame: int) -> Sprite:
    s = Sprite(W, H, origin=(0, 24))
    cx = 78
    breathe = [0, 0, 1, 1][frame % 4]
    slosh = [0, -1, 0, 1][frame % 4]

    # Legs and pelvis.
    for side in (-1, 1):
        hip = (cx + side * 12, 118)
        knee, ankle = chain(*hip, side * 0.12, 20, -side * 0.1, 20)
        s.paint(s.capsule(*hip, *knee, 6.5, 5.5), CHROME, group=f"thigh{side}", bias=-0.05 if side < 0 else 0)
        s.paint(s.ellipse(*knee, 5.5, 5.0), JOINT, group=f"knee{side}")
        s.paint(s.capsule(*knee, *ankle, 5.5, 4.5), CHROME, group=f"shin{side}")
        foot = [(ankle[0] - 9, ankle[1] + 7), (ankle[0] - 6, ankle[1] - 2), (ankle[0] + 6, ankle[1] - 2),
                (ankle[0] + 10, ankle[1] + 7)]
        s.paint(s.polygon(foot, bevel=2.0), CHROME, group=f"foot{side}")
    s.paint(s.rrect(cx - 18, 106, cx + 18, 122, radius=5, bevel=3), CHROME, group="pelvis")

    top = 60 + breathe
    # Claw arm (viewer's left).
    shoulder = (cx - 30, top + 6)
    elbow, hand = chain(*shoulder, -0.35, 22, 0.25, 20)
    s.paint(s.capsule(*shoulder, *elbow, 6.0, 5.2), CHROME, group="arm_l")
    s.paint(s.ellipse(*elbow, 5.2, 5.2), JOINT, group="arm_l")
    s.paint(s.capsule(*elbow, *hand, 5.2, 4.4), CHROME, group="arm_l")
    for dx, dy in ((-5, 9), (0, 11), (5, 8)):
        s.paint(s.capsule(hand[0], hand[1] + 2, hand[0] + dx, hand[1] + dy, 2.4, 1.2), JOINT, group="claw")

    # Torso, warming-plate core, and apron.
    s.paint(s.rrect(cx - 26, top, cx + 26, top + 44, radius=12, bevel=5), CHROME, group="torso")
    s.shift(s.mask_line([(cx, top + 22), (cx, top + 44)]) & s.opaque(), -1)
    s.paint(s.ellipse(cx, top + 15, 10, 10), JOINT, group="core_ring")
    s.paint(s.ellipse(cx, top + 15, 7.5, 7.5), CORE, group="core", bias=-0.1 * (frame % 2))
    rings = s.mask_ellipse(cx, top + 15, 5.5, 5.5) & ~s.mask_ellipse(cx, top + 15, 4.5, 4.5)
    s.shift(rings, -1)
    apron = [(cx - 20, top + 26), (cx + 20, top + 26), (cx + 24, 140), (cx - 24, 140)]
    s.paint(s.polygon(apron, bevel=2.5), APRON, group="apron")
    s.shift(s.mask_rect(cx - 20, top + 26, cx + 21, top + 28) & s.opaque(), 1)
    s.paint(s.rrect(cx - 11, 112, cx + 11, 126, radius=2, bevel=1.5), APRON, group="pocket", bias=-0.08)
    tag = s.paint(s.rrect(cx + 3, top + 30, cx + 29, top + 42, radius=2, bevel=1.0), TAG, group="tag")
    letters = text_mask("EVIL")
    mask = np.zeros((H, W), bool)
    ty0 = top + 33 + s.oy
    mask[ty0:ty0 + letters.shape[0], cx + 5:cx + 5 + letters.shape[1]] = letters
    s.fill(mask & tag, mat("#8a1a2a", 3), 0, group="tag_text")
    for side in (-1, 1):
        s.paint(s.ellipse(cx + side * 30, top + 6, 12, 11), CHROME, group=f"shoulder{side}")

    # Mug Cannon arm (viewer's right).
    shoulder = (cx + 30, top + 6)
    elbow, hand = chain(*shoulder, 0.55, 20, 0.85, 16)
    s.paint(s.capsule(*shoulder, *elbow, 6.0, 5.2), CHROME, group="arm_r")
    s.paint(s.ellipse(*elbow, 5.2, 5.2), JOINT, group="arm_r")
    s.paint(s.capsule(*elbow, *hand, 5.2, 4.6), CHROME, group="arm_r")
    mx, my = hand[0] + 6, hand[1] + 2
    s.paint(s.ellipse(mx + 14, my + 1, 6.5, 8.0), CERAMIC, group="mug_handle")
    s.erase(s.mask_ellipse(mx + 14, my + 1, 3.2, 4.6))
    s.paint(s.rrect(mx - 12, my - 12, mx + 12, my + 14, radius=4, bevel=3.5), CERAMIC, group="mug")
    heart = s.mask_polygon([(mx - 4, my - 1), (mx, my + 4), (mx + 4, my - 1), (mx + 2, my - 3), (mx, my - 1.5),
                            (mx - 2, my - 3)])
    s.fill(heart & s.opaque(), mat("#d8243a", 3), 1, group="mug_heart")
    s.paint(s.ellipse(mx, my - 12, 11.5, 3.0), COFFEE, group="mug_coffee")
    s.paint(s.ellipse(mx - 1, my - 12, 7, 1.5), CORE, group="mug_glow")

    # Neck cables and the carafe head.
    for dx in (-5, 0, 5):
        s.paint(s.capsule(cx + dx, top + 2, cx + dx * 0.6, top - 8, 2.4), JOINT, group="cables")
    hy = 38
    carafe = s.mask_ellipse(cx, hy, 21, 18) | s.mask_rrect(cx - 11, hy - 26, cx + 11, hy - 8, radius=3)
    s.paint(s.from_mask(carafe, bevel=3.5), AIR, group="glass_air")
    level = hy - 3 + slosh
    liquid = carafe & (s.y > level + (s.x - cx) * 0.06 * slosh)
    s.paint((liquid, s.from_mask(liquid, bevel=3.0)[1]), COFFEE, group="coffee")
    crema = liquid & ~(np.roll(liquid, 2, axis=0) & np.roll(liquid, 1, axis=0))
    s.fill(crema & (s.y < level + 3), CREMA, 1, group="crema")
    squint = 1.2 if frame % 4 == 2 else 2.2
    for side in (-1, 1):
        ex = cx + side * 8
        eye = s.mask_polygon([(ex - 5, hy + 3 - side * 1.5), (ex + 5, hy + 3 + side * 1.5),
                              (ex + 4, hy + 3 + squint + side * 1.5), (ex - 4, hy + 3 + squint - side * 1.5)])
        s.fill(eye & liquid, EYES, 1, group="eyes")
    rim = s.mask_ellipse(cx, hy, 22, 19) | s.mask_rrect(cx - 12, hy - 27, cx + 12, hy - 8, radius=3)
    s.fill(rim & ~carafe, GLASS, 1, group="rim")
    streaks = (s.mask_line([(cx - 15, hy - 8), (cx - 17, hy + 6)])
               | s.mask_line([(cx - 12, hy - 9), (cx - 13, hy + 2)]))
    s.fill(streaks & carafe, GLASS, 3, group="streaks")
    handle = s.mask_ellipse(cx - 24, hy - 2, 7, 10) & ~s.mask_ellipse(cx - 24, hy - 2, 3.5, 6.5) & (s.x < cx - 20)
    s.paint(s.from_mask(handle, bevel=1.5), PLASTIC, group="handle")
    s.paint(s.rrect(cx - 15, hy - 33, cx + 15, hy - 24, radius=3, bevel=2.0), PLASTIC, group="lid")
    s.paint(s.polygon([(cx + 13, hy - 31), (cx + 22, hy - 29), (cx + 13, hy - 25)], bevel=1.0), PLASTIC, group="spout")
    s.paint(s.ellipse(cx, hy - 35, 5, 2.2), PLASTIC, group="knob", bias=0.15)

    # Steam: puffs that rise and shrink over the loop.
    for i, (px, base) in enumerate(((cx - 6, 0), (cx + 4, 6), (cx - 1, 12))):
        rise = (frame * 5 + base) % 20
        radius = 4.5 - rise * 0.15
        s.paint(s.ellipse(px + np.sin(rise * 0.4) * 2, hy - 40 - rise, radius, radius * 0.85), STEAM,
                group=f"steam{i}")
    return s
