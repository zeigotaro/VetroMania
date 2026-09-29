"""Interactive props, pickups, boss animations, and effect sprites."""

from __future__ import annotations

import numpy as np

from characters import chain
from pixel import Sprite, glow, mat, text_mask

STEEL = mat("#7784a3", spec=(245, 250, 255), spec_cut=0.72)
STEEL_DARK = mat("#48526d", dark=0.52)
STONE = mat("#56516b", dark=0.58, light=0.34)
COPPER = mat("#b06a3a", spec=(255, 226, 190), spec_cut=0.68)
HAZARD = mat("#f2b632", 3)
INKY = mat("#221b31", 3)
RED = glow("#ff384a", core="#fff4be")
CYAN = glow("#43e6ff", core="#edfeff")
GOLD = glow("#f4cb48", core="#fff8d0")
AMBER = glow("#ffb454", core="#fff0cc")
WHITE = glow("#f4f3ff", core="#ffffff")
ORANGE = glow("#ff8a24", core="#fff2d6")
LEATHER = mat("#98582d")
WARN = mat("#8d2a30", 4)
CHROME = mat("#a6afc8", 6, dark=0.7, light=0.8, spec=(255, 255, 255), spec_cut=0.52, spec_power=11)
PIPE_CHROME = mat("#9ca6c4", 5, dark=0.7, spec=(255, 255, 255), spec_cut=0.62)
MOSS = mat("#2f9472")
FOAM = mat("#79d4ee", 4, dark=0.45, light=0.55)


def _stencil(s: Sprite, text: str, x: int, y: int, material, *, scale: int = 1, clip: np.ndarray | None = None) -> None:
    mask = text_mask(text, scale)
    stamp = np.zeros((s.h, s.w), bool)
    y0 = y + s.oy
    x0 = x + s.ox
    y1 = min(y0 + mask.shape[0], s.h)
    x1 = min(x0 + mask.shape[1], s.w)
    if y0 >= y1 or x0 >= x1:
        return
    stamp[y0:y1, x0:x1] = mask[:y1 - y0, :x1 - x0]
    if clip is not None:
        stamp &= clip
    s.fill(stamp, material, 1, group=f"text_{text}")


def _hazard_stripes(s: Sprite, mask: np.ndarray, *, offset: int = 0) -> None:
    stripes = mask & ((np.floor(s.x + s.y + offset) % 8) < 4)
    s.fill(mask & ~stripes, INKY, 1, group="hazard_back")
    s.fill(stripes, HAZARD, 2, group="hazard")


def _krate_sprite(*, body_drop: int = 0, lid_raise: int = 0, lid_tilt: float = 0.0, jaw_drop: int = 0,
                  eye_angry: int = 0, leg_splay: float = 0.0, squash: int = 0, stomp: int = 0,
                  dust: bool = False) -> Sprite:
    s = Sprite(144, 120)
    left, right = 12, 132
    top = 24 + body_drop + squash
    lid_y = top - 6 - lid_raise
    mouth_y = top + 6 + jaw_drop
    bottom = 96 + body_drop
    mouth_top = min(top + 10, mouth_y + 8)
    mouth_bottom = max(top + 10, mouth_y + 8)

    # Hydraulic legs sit exactly on the bottom row.
    for side, x in ((-1, 36), (1, 108)):
        hip = (x, bottom - 3)
        knee, ankle = chain(*hip, side * (0.1 + leg_splay), 13, -side * 0.18, 11 + stomp)
        s.paint(s.capsule(*hip, *knee, 5.2, 4.2), STEEL_DARK, group=f"leg_back{side}")
        s.paint(s.ellipse(*knee, 4.0, 3.8), CHROME, group=f"knee{side}")
        s.paint(s.capsule(*knee, *ankle, 4.6, 3.5), CHROME, group=f"shin{side}")
        foot = [(ankle[0] - 12, 118), (ankle[0] - 8, 112), (ankle[0] + 8, 112), (ankle[0] + 13, 118)]
        s.paint(s.polygon(foot, bevel=2.0), STEEL, group=f"foot{side}")
        toe = s.mask_rect(foot[0][0], 116, foot[3][0], 119)
        s.fill(toe & s.opaque(), STEEL_DARK, 0, group=f"toe{side}")

    # Main crate body.
    shell = s.paint(s.rrect(left, top, right, bottom, radius=7, bevel=4.0), STEEL, group="shell")
    for band_x in (26, 58, 90, 118):
        band = s.paint(s.rrect(band_x - 4, top + 4, band_x + 4, bottom - 4, radius=2, bevel=1.8), CHROME,
                       group=f"band{band_x}", bias=0.05)
        rivets = [(band_x, y) for y in range(top + 12, bottom - 6, 12)]
        s.shift(s.mask_points(rivets) & band, 2)
    s.paint(s.rrect(left + 7, top + 10, right - 7, top + 24, radius=3, bevel=2.0), CHROME, group="cross")
    plate = s.paint(s.rrect(left + 14, top + 30, right - 14, bottom - 18, radius=4, bevel=2.8), STEEL_DARK,
                    group="plate")
    _hazard_stripes(s, s.mask_rect(left + 14, top + 31, right - 13, top + 39) & plate, offset=2)
    _stencil(s, "FRAGILE", 49, top + 46, WARN, clip=plate)
    s.shift(s.mask_line([(left + 18, top + 58), (right - 18, top + 58)]) & plate, -1)
    for point in ((42, top + 70), (102, top + 70), (72, top + 78)):
        s.shift(s.mask_points([point]) & plate, 2)
    bat_mark = s.mask_polygon([(36, top + 67), (42, top + 61), (48, top + 66), (54, top + 62), (60, top + 68),
                               (52, top + 71), (55, top + 76), (47, top + 73), (43, top + 78), (40, top + 72)])
    s.fill(bat_mark & plate, WARN, 2, group="bat_mark")

    # Mouth cavity and jaw.
    mouth = s.mask_rrect(left + 12, mouth_top, right - 12, mouth_bottom, radius=5)
    s.fill(mouth & shell, INKY, 0, group="mouth")
    s.paint(s.rrect(left + 8, mouth_y + 2, right - 8, top + 30, radius=4, bevel=1.8), CHROME, group="jaw")
    for i, x in enumerate(range(left + 16, right - 12, 11)):
        points = [(x, mouth_y + 1), (x + 4, mouth_y + 1), (x + 2, mouth_y + 7 + (i % 2))]
        s.paint(s.polygon(points, bevel=0.6), mat("#efe6d6", 3), group=f"tooth_low{i}")

    # Lid / upper jaw.
    cx = (left + right) / 2
    lid = [(left + 2, top + 10), (left + 10, lid_y), (cx - 12, lid_y - 4 - lid_tilt), (right - 10, lid_y),
           (right - 2, top + 10), (right - 8, top + 20), (left + 8, top + 20)]
    lid_mask = s.paint(s.polygon(lid, bevel=3.0), CHROME, group="lid")
    _hazard_stripes(s, s.mask_polygon([(left + 18, top + 10), (left + 34, lid_y + 2), (right - 34, lid_y + 2),
                                       (right - 18, top + 10), (right - 26, top + 14), (left + 26, top + 14)])
                    & lid_mask, offset=1)
    for i, x in enumerate(range(left + 17, right - 11, 12)):
        points = [(x, top + 20), (x + 5, top + 20), (x + 2.5, top + 12 - (i % 2))]
        s.paint(s.polygon(points, bevel=0.6), mat("#efe6d6", 3), group=f"tooth_up{i}")

    # Eyes and brow.
    squint = 2 if eye_angry else 3
    for side, ex in ((-1, 52), (1, 92)):
        eye = s.mask_polygon([(ex - 10, top + 17 - eye_angry), (ex + 8, top + 14 + side * 1.5),
                              (ex + 6, top + 14 + squint + side), (ex - 8, top + 17 + squint - side)])
        s.fill(eye & lid_mask, RED, 3, group=f"eye{side}")
        s.fill(s.mask_ellipse(ex - 1, top + 16, 2.8, 1.4) & eye & lid_mask, WHITE, 2, group=f"eye_core{side}")
        glint = s.mask_points([(ex - 3, top + 15), (ex - 1, top + 16)])
        s.fill(glint & eye, WHITE, 3, group=f"eye_glint{side}")
    brow = s.mask_line([(44, top + 18), (62, top + 13 - eye_angry)], width=2) | s.mask_line(
        [(84, top + 13 - eye_angry), (101, top + 18)], width=2
    )
    s.fill(brow & lid_mask, STEEL_DARK, 0, group="brow")

    # Ground impact dust for the slam frame.
    if dust:
        for dx, rx in ((-22, 9), (21, 11)):
            puff = s.paint(s.ellipse(cx + dx, 114.5, rx, 3.4), mat("#b4967b", 4), group=f"dust{dx}")
            s.shift(s.mask_rect(cx + dx - rx, 114, cx + dx + rx, 119) & puff, -1)
    return s


KRATE_ANIMS = {
    "idle": [
        _krate_sprite(body_drop=0, lid_raise=0, jaw_drop=0, eye_angry=0, leg_splay=0.0),
        _krate_sprite(body_drop=1, lid_raise=1, jaw_drop=1, eye_angry=1, leg_splay=0.03),
    ],
    "windup": [
        _krate_sprite(body_drop=-1, lid_raise=10, lid_tilt=1.5, jaw_drop=3, eye_angry=1, leg_splay=0.08),
        _krate_sprite(body_drop=-4, lid_raise=18, lid_tilt=3.0, jaw_drop=7, eye_angry=1, leg_splay=0.14),
    ],
    "slam": [
        _krate_sprite(body_drop=4, lid_raise=7, jaw_drop=-3, eye_angry=1, leg_splay=0.05, stomp=2, squash=3),
        _krate_sprite(body_drop=6, lid_raise=0, jaw_drop=-6, eye_angry=1, leg_splay=0.0, stomp=1, squash=6, dust=True),
    ],
    "chomp": [
        _krate_sprite(body_drop=-1, lid_raise=14, lid_tilt=1.5, jaw_drop=7, eye_angry=1, leg_splay=0.06),
        _krate_sprite(body_drop=1, lid_raise=2, jaw_drop=-2, eye_angry=1, leg_splay=-0.02, squash=2),
    ],
}


def save_pod() -> list[Sprite]:
    frames = []
    for lit in (False, True):
        s = Sprite(32, 48)
        s.paint(s.rrect(7, 7, 25, 46, radius=8, bevel=2.5), CHROME, group="body")
        glass = s.paint(s.rrect(10, 11, 22, 37, radius=5, bevel=1.6), mat("#5a2031", 4), group="glass")
        s.paint(s.rrect(8, 39, 24, 45, radius=2, bevel=1.0), STEEL_DARK, group="base")
        band = s.mask_rect(9, 27, 24, 30) & glass
        s.fill(band, WARN, 1, group="band")
        s.paint(s.capsule(16, 3, 16, 10, 1.7), STEEL_DARK, group="mast")
        s.paint(s.ellipse(16, 4, 3.5, 3.5), RED if lit else mat("#6b2330", 3), group="beacon")
        if lit:
            s.paint(s.ellipse(16, 23, 4.5, 7.5), RED, group="core")
            s.paint(s.ellipse(16, 17, 2.5, 4.0), WHITE, group="shine")
        frames.append(s)
    return frames


def door() -> list[Sprite]:
    frames = []
    for opened in (False, True):
        s = Sprite(16, 48)
        s.paint(s.rrect(1, 0, 15, 47, radius=1, bevel=2.0), STEEL_DARK, group="frame")
        s.paint(s.rrect(3, 3, 13, 44, radius=1, bevel=1.4), CHROME, group="panel")
        slot = s.mask_rect(6, 6, 10, 40)
        s.fill(slot & s.opaque(), CYAN, 2 if opened else 1, group="slot")
        s.fill(s.mask_rect(4, 22, 12, 26) & s.opaque(), WARN, 1, group="warn")
        if opened:
            s.erase(s.mask_rect(4, 2, 12, 46))
            s.paint(s.rrect(11, 3, 15, 44, radius=1, bevel=1.4), CHROME, group="slide")
            spill = s.mask_polygon([(0, 6), (10, 12), (10, 36), (0, 42)])
            s.fill(spill, CYAN, 2, group="spill")
            s.fill(s.mask_polygon([(0, 10), (7, 14), (7, 34), (0, 38)]), WHITE, 2, group="spill_core")
        frames.append(s)
    return frames


def vending_machine() -> list[Sprite]:
    frames = []
    for blink in (0, 1):
        s = Sprite(32, 48)
        s.paint(s.rrect(3, 2, 29, 47, radius=3, bevel=2.2), CHROME, group="shell")
        s.paint(s.rrect(6, 5, 26, 20, radius=2, bevel=1.4), mat("#47204f", 4), group="screen")
        msg = s.mask_rect(8, 7, 24, 18)
        s.fill(msg, CYAN if blink else mat("#6190b5", 4), 2 if blink else 1, group="msg")
        _stencil(s, "TAKE", 9, 8, INKY, clip=msg)
        _stencil(s, "THIS", 9, 14, INKY, clip=msg)
        s.paint(s.rrect(9, 24, 23, 29, radius=2, bevel=1.1), LEATHER, group="slot")
        s.paint(s.rrect(8, 34, 24, 41, radius=2, bevel=1.0), STEEL_DARK, group="drawer")
        s.paint(s.ellipse(16, 27, 2.8, 2.2), ORANGE if blink else CYAN, group="glow")
        frames.append(s)
    return frames


def koozie_statue() -> list[Sprite]:
    frames = []
    for active in (False, True):
        s = Sprite(32, 56)
        s.paint(s.rrect(6, 45, 26, 55, radius=2, bevel=2.0), STONE, group="base")
        s.paint(s.capsule(16, 44, 16, 17, 7.0, 7.8), STONE, group="body")
        s.paint(s.capsule(10, 28, 7, 41, 2.7), STONE, group="arm_left")
        s.paint(s.capsule(22, 28, 24, 16, 2.7), STONE, group="arm_right")
        s.paint(s.capsule(13, 44, 11, 54, 3.0, 2.4), STONE, group="leg_left")
        s.paint(s.capsule(19, 44, 21, 54, 3.0, 2.4), STONE, group="leg_right")
        s.paint(s.ellipse(16, 15, 6.5, 7.0), STONE, group="head")
        s.paint(s.rrect(12, 18, 20, 26, radius=2, bevel=1.4), FOAM, group="koozie")
        ball = s.paint(s.ellipse(24, 13, 4.0, 4.0), GOLD if active else mat("#8890b4", 4), group="ball")
        seam = s.mask_line([(21, 13), (27, 13)]) | s.mask_line([(24, 10), (24, 16)])
        s.fill(seam & ball, INKY, 0, group="ball_seam")
        if active:
            s.paint(s.ellipse(24, 13, 2.0, 2.0), WHITE, group="ball_core")
        frames.append(s)
    return frames


def warp_pipe() -> list[Sprite]:
    s = Sprite(32, 48)
    s.paint(s.rrect(5, 9, 27, 47, radius=3, bevel=2.2), PIPE_CHROME, group="body")
    s.paint(s.rrect(2, 4, 30, 14, radius=4, bevel=2.6), HAZARD, group="rim")
    s.paint(s.rrect(5, 7, 27, 12, radius=2, bevel=1.2), PIPE_CHROME, group="lip")
    s.shift(s.mask_line([(10, 17), (10, 44)]) & s.opaque(), 1)
    s.shift(s.mask_line([(22, 17), (22, 44)]) & s.opaque(), -1)
    return [s]


def nag9000() -> list[Sprite]:
    frames = []
    wing_sets = [((-5, -1), (5, -1)), ((-5, -4), (5, -4))]
    for wing_left, wing_right in wing_sets:
        s = Sprite(16, 16)
        s.paint(s.ellipse(8, 8, 4.4, 4.4), CHROME, group="body")
        s.paint(s.ellipse(8, 8, 2.5, 2.5), CYAN, group="core")
        s.paint(s.polygon([(8, 8), (8 + wing_left[0], 8 + wing_left[1]), (4, 8)], bevel=1.0), STEEL,
                          group="wing_left")
        s.paint(s.polygon([(8, 8), (8 + wing_right[0], 8 + wing_right[1]), (12, 8)], bevel=1.0), STEEL,
                          group="wing_right")
        s.fill(s.mask_points([(7, 11), (9, 11)]), RED, 2, group="beeps")
        frames.append(s)
    return frames


def ability_orb() -> list[Sprite]:
    frames = []
    for frame in range(4):
        s = Sprite(16, 16)
        ring = 5.0 + frame * 0.5
        s.paint(s.ellipse(8, 8, ring, ring), CYAN if frame % 2 else GOLD, group="aura")
        s.paint(s.ellipse(8, 8, 4.2, 4.2), GOLD if frame % 2 else CYAN, group="core")
        s.paint(s.ellipse(6.5, 6.5, 1.5, 1.5), WHITE, group="shine")
        frames.append(s)
    return frames


def hologram_ring() -> list[Sprite]:
    frames = []
    for phase in (0, 1):
        s = Sprite(32, 8)
        ring = s.mask_ellipse(16, 4, 13.5, 2.5) & ~s.mask_ellipse(16, 4, 10.5, 1.3)
        s.fill(ring, CYAN, 2, group="ring")
        if phase:
            ticks = s.mask_points([(8, 4), (12, 2), (16, 1), (20, 2), (24, 4)])
            s.fill(ticks & ring, WHITE, 2, group="ticks")
        else:
            s.fill(s.mask_points([(10, 4), (16, 2), (22, 4)]) & ring, WHITE, 2, group="ticks")
        frames.append(s)
    return frames


def hit_spark() -> list[Sprite]:
    frames = []
    sizes = [3.0, 5.0, 4.0]
    for i, radius in enumerate(sizes):
        s = Sprite(16, 16)
        for dx, dy in ((0, -radius), (radius, 0), (0, radius), (-radius, 0),
                       (radius * 0.6, radius * 0.6), (-radius * 0.6, radius * 0.6),
                       (radius * 0.6, -radius * 0.6), (-radius * 0.6, -radius * 0.6)):
            s.paint(s.capsule(8, 8, 8 + dx, 8 + dy, 1.4 if i == 0 else 1.0), WHITE, group=f"ray{dx}_{dy}")
        s.paint(s.ellipse(8, 8, 2.2 + i * 0.4, 2.2 + i * 0.4), AMBER if i else WHITE, group="core")
        frames.append(s)
    return frames


def mitt_shot() -> list[Sprite]:
    frames = []
    for stretch in (0, 1):
        s = Sprite(20, 12)
        s.paint(s.capsule(3, 6, 14 + stretch * 2, 6, 2.2, 3.0), CYAN, group="trail")
        s.paint(s.ellipse(15 + stretch * 2, 6, 3.2 + stretch, 3.2), WHITE, group="head")
        frames.append(s)
    return frames


def mitt_shot_charged() -> list[Sprite]:
    frames = []
    for frame in (0, 1):
        s = Sprite(32, 20)
        s.paint(s.capsule(3, 10, 23 + frame * 3, 10, 3.3, 5.0), CYAN, group="trail")
        s.paint(s.ellipse(24 + frame * 3, 10, 6.0, 6.0), WHITE, group="head")
        halo = s.mask_ellipse(24 + frame * 3, 10, 9.0, 9.0) & ~s.mask_ellipse(24 + frame * 3, 10, 6.5, 6.5)
        s.fill(halo, CYAN, 2, group="halo")
        frames.append(s)
    return frames


def enemy_bolt() -> list[Sprite]:
    frames = []
    for frame in (0, 1):
        s = Sprite(10, 10)
        s.paint(s.capsule(2, 5, 8, 5, 1.4, 2.0), ORANGE if frame else RED, group="beam")
        s.paint(s.ellipse(8, 5, 1.8 + frame * 0.5, 1.8 + frame * 0.2), WHITE, group="head")
        frames.append(s)
    return frames


def pickup_glint() -> list[Sprite]:
    frames = []
    for size in (1, 2, 1):
        s = Sprite(8, 8)
        for d in range(-size, size + 1):
            s.fill(s.mask_points([(4 + d, 4), (4, 4 + d)]), WHITE, 2, group="star")
        s.paint(s.ellipse(4, 4, 1.2 + size * 0.4, 1.2 + size * 0.4), GOLD, group="core")
        frames.append(s)
    return frames


def crate_tile() -> Sprite:
    s = Sprite(16, 16)
    crate = s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=2.0), mat("#795238", 5), group="crate")
    for y in (5, 10):
        s.fill(s.mask_rect(0, y, 16, y + 2) & crate, CHROME, 2, group=f"band{y}")
    for x in (5, 10):
        s.fill(s.mask_rect(x, 0, x + 2, 16) & crate, CHROME, 2, group=f"band{x}")
    decal = s.mask_polygon([(5, 6), (7, 4), (9, 6), (11, 5), (12, 7), (10, 9), (11, 11), (8, 10), (6, 12), (5, 9)])
    s.fill(decal & crate, CYAN, 2, group="decal")
    return s


def mitt_target(frame: int) -> Sprite:
    s = Sprite(16, 16)
    base = s.paint(s.rrect(0, 0, 15, 15, radius=1, bevel=1.8), STEEL_DARK, group="base")
    ring = s.mask_ellipse(8, 8, 6.0, 6.0) & ~s.mask_ellipse(8, 8, 3.5, 3.5)
    s.fill(ring & base, CYAN, 2, group="ring")
    palm = s.mask_ellipse(8, 8, 2.5, 2.5)
    s.fill(palm & base, GOLD if frame else WHITE, 2, group="palm")
    thumb = s.mask_ellipse(4.6, 8.3, 1.8, 3.0) | s.mask_ellipse(10.6, 3.9, 2.2, 1.6)
    s.fill(thumb & base, CYAN, 2, group="thumb")
    return s


def spike_tile() -> Sprite:
    s = Sprite(16, 16)
    s.paint(s.rrect(0, 12, 15, 15, radius=0, bevel=1.0), STEEL_DARK, group="base")
    for x in (2, 8, 14):
        s.paint(s.polygon([(x - 2, 12), (x, 3), (x + 2, 12)], bevel=0.9), CHROME, group=f"spike{x}")
    return s


def _item_icon() -> Sprite:
    return Sprite(24, 24)


def mega_mallet() -> Sprite:
    s = _item_icon()
    s.paint(s.capsule(6, 19, 13, 12, 1.8, 2.1), LEATHER, group="handle")
    s.paint(s.ellipse(5.5, 19.5, 2.0, 2.0), CHROME, group="pommel")
    head = s.paint(s.rrect(10, 5, 21, 13, radius=2, bevel=1.8), mat("#d84a62", 5), group="head")
    s.paint(s.rrect(12, 7, 19, 11, radius=1, bevel=1.0), mat("#ff9ab0", 4), group="head_gloss")
    for x in (10, 20):
        s.paint(s.ellipse(x, 9, 2.3, 4.0), CHROME, group=f"cap{x}")
    star = s.mask_polygon([(16, 6.6), (17.2, 8.4), (19.1, 8.9), (17.6, 10.1), (17.9, 12.1), (16, 11.2),
                           (14.1, 12.1), (14.4, 10.1), (12.9, 8.9), (14.8, 8.4)])
    s.fill(star & head, GOLD, 2, group="star")
    return s


def box_cutter() -> Sprite:
    s = _item_icon()
    body = s.paint(s.polygon([(4, 16), (11, 6), (19, 8), (17, 17), (8, 19)], bevel=1.8), HAZARD, group="body")
    s.paint(s.polygon([(8, 17), (12, 8.5), (17.6, 10), (16.2, 16.6), (10.3, 17.8)], bevel=1.2), STEEL_DARK,
            group="grip")
    blade = s.paint(s.polygon([(11, 6), (17, 2.8), (20, 4.3), (14.3, 8.4)], bevel=1.0), CHROME, group="blade")
    notch = s.mask_line([(14.2, 5.6), (17.6, 4.0)], width=1)
    s.fill(notch & blade, STEEL_DARK, 0, group="snap_line")
    segment = s.paint(s.polygon([(17.7, 2.5), (20.7, 0.9), (21.9, 2.2), (19.0, 3.9)], bevel=0.8), CHROME,
                      group="snap_piece")
    s.shift(s.mask_line([(18.4, 3.2), (20.4, 2.2)]) & segment, -1)
    slider = s.paint(s.rrect(10, 11, 13, 14, radius=1, bevel=0.9), WARN, group="slider")
    s.shift(s.mask_points([(11, 12)]) & slider, 2)
    return s


def spread_gun() -> Sprite:
    s = _item_icon()
    s.paint(s.rrect(4, 9, 17, 18, radius=3, bevel=1.8), CHROME, group="body")
    s.paint(s.rrect(7, 11, 14, 16, radius=2, bevel=1.0), STEEL_DARK, group="core")
    s.paint(s.polygon([(8, 17), (11, 18), (11, 22), (7, 21)], bevel=1.0), LEATHER, group="grip")
    for y in (8, 11.5, 15):
        s.paint(s.capsule(14, y, 21, y, 1.5, 2.0), STEEL, group=f"barrel{y}")
        s.paint(s.ellipse(21.0, y, 1.4, 2.0), CYAN, group=f"muzzle{y}")
    s.paint(s.ellipse(9, 13.5, 1.8, 1.8), ORANGE, group="power")
    return s


def throwable() -> Sprite:
    s = _item_icon()
    disc = s.mask_ellipse(12, 12, 8.5, 5.5) & ~s.mask_ellipse(12, 12, 5.0, 2.6)
    s.paint(s.from_mask(disc, bevel=1.4), CHROME, group="disc")
    inner = s.paint(s.ellipse(12, 12, 4.7, 2.4), mat("#4f5d8a", 4), group="core")
    star = s.mask_polygon([(12, 8.2), (13.4, 10.5), (16.1, 10.8), (14.2, 12.3), (14.8, 14.9), (12, 13.5),
                           (9.2, 14.9), (9.8, 12.3), (7.9, 10.8), (10.6, 10.5)])
    s.fill(star & inner, GOLD, 2, group="star")
    arc = s.mask_line([(6, 12), (18, 12)], width=1)
    s.fill(arc & disc, CYAN, 2, group="arc")
    return s


def space_burrito() -> Sprite:
    s = _item_icon()
    wrap = s.paint(s.polygon([(4, 14), (9, 7), (16, 6), (20, 11), (18, 17), (10, 19)], bevel=2.0),
                   mat("#d7dde8", 5, dark=0.68, light=0.5), group="wrap")
    seams = s.mask_line([(7, 15), (13, 8)]) | s.mask_line([(11, 18), (18, 11)])
    s.fill(seams & wrap, STEEL_DARK, 0, group="seams")
    s.paint(s.polygon([(6, 15), (9, 17), (11, 16), (8, 13)], bevel=0.8), mat("#6ac26c", 4), group="filling")
    s.paint(s.polygon([(8, 14), (11, 15), (13, 13), (10, 12)], bevel=0.8), mat("#d35a42", 4), group="filling")
    shine = s.mask_line([(9, 9), (14, 7)]) | s.mask_line([(12, 11), (17, 9)])
    s.fill(shine & wrap, WHITE, 2, group="shine")
    return s


def energy_drink() -> Sprite:
    s = _item_icon()
    can = s.paint(s.rrect(7, 4, 17, 21, radius=3, bevel=2.0), CHROME, group="can")
    s.paint(s.ellipse(12, 4.5, 4.0, 1.5), STEEL, group="lid")
    s.paint(s.ellipse(12.5, 4.4, 1.7, 0.8), STEEL_DARK, group="tab")
    band = s.paint(s.rrect(8, 7, 16, 19, radius=2, bevel=1.0), mat("#29a1d8", 4), group="label")
    bolt = s.mask_polygon([(12.2, 8), (10.1, 12.2), (12.0, 12.2), (10.3, 17.8), (14.2, 11.8), (12.4, 11.8),
                           (14.0, 8)])
    s.fill(bolt & band, GOLD, 2, group="bolt")
    return s


def signing_table() -> list[Sprite]:
    frames = []
    for sparkle in (False, True):
        s = Sprite(32, 24)
        s.paint(s.polygon([(3, 9), (29, 9), (26, 17), (6, 17)], bevel=1.8), mat("#8e6340", 5), group="top")
        s.paint(s.polygon([(6, 17), (11, 17), (10, 23), (6, 23)], bevel=1.1), CHROME, group="leg_left")
        s.paint(s.polygon([(22, 17), (26, 17), (25, 23), (21, 23)], bevel=1.1), CHROME, group="leg_right")
        s.paint(s.polygon([(13, 17), (17, 17), (16, 23), (12, 23)], bevel=1.0), STEEL_DARK, group="brace")

        sign = s.paint(s.polygon([(7, 15), (18, 15), (17, 20), (8, 20)], bevel=0.7), mat("#efe6d2", 3), group="sign")
        squiggles = (
            s.mask_line([(9, 17), (12, 16)], width=1)
            | s.mask_line([(12, 16), (14, 17)], width=1)
            | s.mask_line([(10, 18), (13, 19)], width=1)
        )
        s.fill(squiggles & sign, WARN, 1, group="sign_text")

        cards = s.paint(s.rrect(11, 10, 18, 13, radius=1, bevel=0.8), mat("#f0eef7", 3), group="cards")
        s.shift(s.mask_line([(12, 11), (17, 11)]) & cards, -1)
        s.fill(s.mask_points([(16, 12)]), CYAN, 2, group="card_stamp")

        pen = s.paint(s.capsule(19, 10, 25, 7, 0.9, 1.1), CHROME, group="pen")
        s.fill(s.mask_line([(19.6, 9.8), (24.0, 7.6)]) & pen, CYAN, 2, group="pen_line")
        s.paint(s.polygon([(25, 7), (27.2, 5.8), (26.1, 7.9)], bevel=0.5), GOLD, group="nib")
        if sparkle:
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                s.fill(s.mask_points([(27 + dx, 5 + dy)]), WHITE, 2, group="spark")
            s.fill(s.mask_points([(27, 5)]), GOLD, 2, group="spark_core")
        frames.append(s)
    return frames


def chest() -> list[Sprite]:
    frames = []
    for opened in (False, True):
        s = Sprite(28, 24)
        base = s.paint(s.rrect(2, 9, 26, 23, radius=4, bevel=2.2), STEEL, group="base")
        panel = s.paint(s.rrect(4, 12, 24, 21, radius=2, bevel=1.4), STEEL_DARK, group="panel")
        _hazard_stripes(s, s.mask_rect(5, 13, 24, 16) & panel, offset=1)
        s.fill(s.mask_line([(5, 12), (23, 12)]) & panel, CYAN, 2, group="seam")
        latch = s.paint(s.rrect(12, 14, 16, 19, radius=1, bevel=0.9), GOLD if opened else mat("#c69542", 4),
                        group="latch")
        s.shift(s.mask_points([(13, 15)]) & latch, 2)
        s.paint(s.polygon([(5, 23), (8, 23), (7, 24), (4, 24)], bevel=0.5), STEEL_DARK, group="foot_left")
        s.paint(s.polygon([(20, 23), (23, 23), (24, 24), (21, 24)], bevel=0.5), STEEL_DARK, group="foot_right")

        if opened:
            spill = s.mask_polygon([(6, 9), (22, 9), (25, 13), (3, 13)])
            s.fill(spill, AMBER, 2, group="spill")
            s.fill(s.mask_polygon([(8, 9), (20, 9), (22, 12), (6, 12)]), WHITE, 2, group="spill_core")
            lid = [(2, 10), (6, 2), (21, 0), (26, 6), (24, 11), (18, 8), (8, 9)]
            lid_mask = s.paint(s.polygon(lid, bevel=2.0), STEEL, group="lid")
            _hazard_stripes(s, s.mask_polygon([(8, 6), (22, 4), (23, 7), (10, 9)]) & lid_mask, offset=2)
            s.fill(s.mask_line([(9, 8), (20, 5)]) & lid_mask, CYAN, 2, group="lid_seam")
        else:
            lid_mask = s.paint(s.rrect(2, 3, 26, 12, radius=4, bevel=2.0), STEEL, group="lid")
            _hazard_stripes(s, s.mask_rect(5, 6, 24, 9) & lid_mask, offset=2)
            s.fill(s.mask_line([(5, 9), (23, 9)]) & lid_mask, CYAN, 2, group="lid_seam")
        frames.append(s)
    return frames


PROPS = {
    "save_pod": save_pod,
    "door": door,
    "vending_machine": vending_machine,
    "koozie_statue": koozie_statue,
    "warp_pipe": warp_pipe,
    "nag9000": nag9000,
    "ability_orb": ability_orb,
    "hologram_ring": hologram_ring,
}

EFFECTS = {
    "hit_spark": hit_spark,
    "mitt_shot": mitt_shot,
    "mitt_shot_charged": mitt_shot_charged,
    "enemy_bolt": enemy_bolt,
    "pickup_glint": pickup_glint,
}

TILES = {
    "crate": crate_tile,
    "mitt_target_0": lambda: mitt_target(0),
    "mitt_target_1": lambda: mitt_target(1),
    "spike": spike_tile,
}

RUNTIME_ITEM_ICONS = {
    "mega_mallet": mega_mallet,
    "box_cutter": box_cutter,
    "spread_gun": spread_gun,
    "throwable": throwable,
    "space_burrito": space_burrito,
    "energy_drink": energy_drink,
}

RUNTIME_PROPS = {
    "chest": chest,
    "signing_table": signing_table,
}
