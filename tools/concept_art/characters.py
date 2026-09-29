"""Sleve Bonzalez: space bounty hunter, spaceball fanatic, mullet enthusiast.

The sprite is rigged from a handful of angles per frame (radians measured
from straight down, positive toward the facing direction), so the idle, run,
swing, jump, and Spaceball animations share one set of parts.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from pixel import BAYER4, Material, Sprite, glow, mat, ramp

W, H = 96, 100
HIP = (38, 71)

ARMOR = mat("#3565d8", spec=(236, 244, 255), spec_cut=0.72)
UNDER = mat("#2a2f5c", dark=0.55)
GOLD = mat("#f2b632", spec=(255, 248, 214), spec_cut=0.55)
VISOR = Material(ramp("#ff8a1c", 5, light=0.7), spec=(255, 255, 255), spec_power=10, spec_cut=0.35)
HAIR = mat("#8a5230", hue=0.08)
LEATHER = mat("#a0582a")
LACE = mat("#f3dca4", 3)
STEEL = mat("#8e9ab4", spec=(255, 255, 255))
TANK = mat("#4a5170")
GRIP = mat("#3a2e3c", 4)
BEAM = glow("#ff3fb4")
MUZZLE = glow("#39e6ff")
THRUST = glow("#ff9a2a", core="#fff4c0")
STITCH = mat("#e0303c", 3)


def _dir(angle: float) -> tuple[float, float]:
    return math.sin(angle), math.cos(angle)


def chain(x, y, a1, l1, a2, l2):
    """Two-bone forward kinematics; returns (joint, end)."""
    dx, dy = _dir(a1)
    jx, jy = x + dx * l1, y + dy * l1
    dx, dy = _dir(a1 + a2)
    return (jx, jy), (jx + dx * l2, jy + dy * l2)


@dataclass(frozen=True)
class Pose:
    body: tuple[float, float] = (0.0, 0.0)     # whole-body offset (run bob)
    upper: tuple[float, float] = (0.0, 0.0)    # extra torso/head/arm offset (breathing, lean)
    near_leg: tuple[float, float] = (0.12, -0.08)
    far_leg: tuple[float, float] = (-0.14, 0.06)
    near_foot: float = 0.0
    far_foot: float = 0.0
    near_arm: tuple[float, float] = (0.15, 0.55)
    far_arm: tuple[float, float] = (-0.1, 0.5)
    hair: float = 0.0
    bat: float | None = None
    smear: tuple[float, float] | None = None
    thrust: bool = False


def _leg(s: Sprite, hip, angles, foot, bias, group):
    (kx, ky), (ax, ay) = chain(*hip, angles[0], 10, angles[1], 10)
    s.paint(s.capsule(*hip, kx, ky, 3.9, 3.2), UNDER, group=group, bias=bias)
    s.paint(s.capsule(kx, ky, ax, ay, 3.4, 2.7), ARMOR, group=group, bias=bias)
    s.paint(s.ellipse(kx + 0.5, ky, 3.2, 3.0), ARMOR, group=group, bias=bias + 0.08)
    c, sn = math.cos(foot), math.sin(foot)

    def rot(px, py):
        return ax + px * c - py * sn, ay + px * sn + py * c

    boot = [rot(-3.5, -2.5), rot(3.0, -2.5), rot(6.5, 1.5), rot(7.0, 4.5), rot(-4.0, 4.5)]
    s.paint(s.polygon(boot, bevel=1.6), ARMOR, group=group, bias=bias)
    s.paint(s.polygon([rot(-4.2, 3.2), rot(7.2, 3.2), rot(7.0, 5.2), rot(-4.2, 5.2)], bevel=0.8),
            STEEL, group=group, bias=bias - 0.1)
    s.paint(s.ellipse(ax, ay - 1.5, 3.6, 1.6), GOLD, group=group, bias=bias)
    return (ax, ay)


def _pad(s: Sprite, cx, cy, bias, group):
    s.paint(s.ellipse(cx, cy + 1.2, 6.8, 5.6), GOLD, group=group, bias=bias)
    s.paint(s.ellipse(cx, cy, 6.6, 5.2), ARMOR, group=group, bias=bias)


def _fist(s: Sprite, x, y, bias, group):
    s.paint(s.ellipse(x, y, 2.9, 2.7), UNDER, group=group, bias=bias + 0.1)


def _mitt_cannon(s: Sprite, elbow, wrist, group):
    ex, ey = elbow
    wx, wy = wrist
    angle = math.atan2(wy - ey, wx - ex)
    ux, uy = math.cos(angle), math.sin(angle)
    cx, cy = ex + (wx - ex) * 0.75, ey + (wy - ey) * 0.75
    # Barrel first, so the mitt's cuff overlaps its base.
    tip = (cx + ux * 9.5, cy + uy * 9.5)
    s.paint(s.capsule(cx + ux * 3, cy + uy * 3, *tip, 2.4, 2.1), STEEL, group=group)
    s.paint(s.ellipse(*tip, 1.5, 2.5, angle=angle), MUZZLE, group=group)
    s.paint(s.ellipse(cx, cy, 6.4, 7.0, angle=angle), LEATHER, group=group)
    s.paint(s.ellipse(cx - uy * 4.6 - ux * 1.5, cy + ux * 4.6 - uy * 1.5, 2.6, 3.4, angle=angle),
            LEATHER, group=group, bias=0.1)
    lace = s.mask_ellipse(cx, cy, 5.6, 6.2) & ~s.mask_ellipse(cx, cy, 4.6, 5.2)
    dots = (np.floor(s.x) + np.floor(s.y)) % 3 == 0
    s.fill(lace & dots & s.opaque(), LACE, 1, group=group)
    s.paint(s.ellipse(ex + (wx - ex) * 0.35, ey + (wy - ey) * 0.35, 3.2, 3.2), GOLD, group=group)


def _bat(s: Sprite, grip, angle, group):
    ux, uy = _dir(angle)
    gx, gy = grip
    s.paint(s.capsule(gx - ux * 2, gy - uy * 2, gx + ux * 4, gy + uy * 4, 1.6), GRIP, group=group)
    s.paint(s.ellipse(gx - ux * 2.5, gy - uy * 2.5, 2.2, 2.2), STEEL, group=group)
    tape = s.mask_line([(gx - ux * 1, gy - uy * 1), (gx + ux * 3, gy + uy * 3)])
    s.shift(tape & ((np.floor(s.x) + np.floor(s.y)) % 2 == 0), 2)
    s.paint(s.capsule(gx + ux * 5, gy + uy * 5, gx + ux * 26, gy + uy * 26, 1.7, 3.4), BEAM, group=group)


def _smear(s: Sprite, pivot, start, end, group):
    """Crescent swing trail that fades out with ordered dithering."""
    px, py = pivot
    steps = 18
    outer = [(px + 28 * math.sin(a), py + 28 * math.cos(a)) for a in np.linspace(start, end, steps)]
    inner = [(px + 11 * math.sin(a), py + 11 * math.cos(a)) for a in np.linspace(end, start, steps)]
    mask = s.mask_polygon(outer + inner) & ~s.opaque()
    theta = np.arctan2(s.x - px, s.y - py)
    t = np.clip((theta - start) / (end - start) if end != start else 0, 0, 1)
    threshold = np.tile(BAYER4, (s.h // 4 + 1, s.w // 4 + 1))[:s.h, :s.w]
    keep = mask & (t > threshold * 0.55)
    level = np.clip((t * 4).astype(int), 0, 3)
    for i in range(4):
        s.fill(keep & (level == i), BEAM, i, group=group)


def build(pose: Pose) -> Sprite:
    s = Sprite(W, H)
    bx, by = pose.body
    ux, uy = pose.upper
    hx, hy = HIP[0] + bx, HIP[1] + by
    tx, ty = hx + ux, hy + uy
    near_shoulder = (tx + 7, ty - 20)
    far_shoulder = (tx - 4, ty - 21)
    attacking = pose.bat is not None

    # Far side, pushed into shadow.
    far_elbow, far_hand = chain(*far_shoulder, pose.far_arm[0], 8, pose.far_arm[1], 8)
    if not attacking:
        s.paint(s.capsule(*far_shoulder, *far_elbow, 3.0, 2.8), ARMOR, group="far_arm", bias=-0.12)
        s.paint(s.capsule(*far_elbow, *far_hand, 2.8, 2.5), UNDER, group="far_arm", bias=-0.12)
        _fist(s, *far_hand, -0.12, "far_arm")
    _pad(s, *far_shoulder, -0.14, "far_pad")
    s.paint(s.capsule(tx - 8, ty - 20, tx - 9, ty - 9, 3.6, 3.2), TANK, group="tank")
    s.paint(s.ellipse(tx - 9, ty - 8, 2.6, 1.8), STEEL, group="tank")
    if pose.thrust:
        s.paint(s.capsule(tx - 9, ty - 6, tx - 10, ty + 1, 2.8, 0.9), THRUST, group="thrust")
    _leg(s, (hx - 2, hy + 1), pose.far_leg, pose.far_foot, -0.14, "far_leg")
    _leg(s, (hx + 2, hy + 1), pose.near_leg, pose.near_foot, 0.0, "near_leg")

    # Torso: undersuit, pinstriped chest plate, belt with the card holster.
    s.paint(s.capsule(tx + 0.5, ty - 4, tx + 1, ty - 12, 6.2, 5.8), UNDER, group="torso")
    abs_lines = s.mask_line([(tx - 5, ty - 7), (tx + 6, ty - 7)]) | s.mask_line([(tx - 5, ty - 10), (tx + 6, ty - 10)])
    s.shift(abs_lines & s.opaque(), -1)
    chest = s.paint(s.rrect(tx - 7, ty - 23, tx + 9, ty - 11, radius=5, bevel=2.5), ARMOR, group="torso")
    stripes = s.mask_rect(tx - 3, ty - 23, tx - 2, ty - 11) | s.mask_rect(tx + 2, ty - 23, tx + 3, ty - 11)
    s.shift(stripes & chest, 2)
    s.paint(s.polygon([(tx + 1, ty - 20), (tx + 3.5, ty - 16), (tx + 6, ty - 20), (tx + 4.5, ty - 20),
                       (tx + 3.5, ty - 18), (tx + 2.5, ty - 20)], bevel=0.6), GOLD, group="torso")
    s.paint(s.rrect(hx - 7, hy - 5, hx + 8, hy - 1, radius=1, bevel=1), GOLD, group="belt")
    s.paint(s.rrect(hx + 1, hy - 5, hx + 5, hy - 1, radius=1, bevel=1), STEEL, group="belt")
    s.paint(s.rrect(hx - 7, hy - 3, hx - 2, hy + 4, radius=1, bevel=1.2), LEATHER, group="holster")

    # Helmet with a cap brim, mullet port, and amber shades.
    s.paint(s.capsule(tx + 2, ty - 22, tx + 3, ty - 25, 3.4), UNDER, group="neck")
    hc = (tx + 3, ty - 31)
    for dx, dy, r0, r1, spread in ((-4, 4, 3.2, 1.6, 0.0), (-6, 2, 2.7, 1.2, 0.35), (-2, 5, 2.6, 1.4, -0.3)):
        base = (hc[0] + dx, hc[1] + dy)
        angle = -0.35 - spread * 0.5 - pose.hair
        end = (base[0] + 9 * math.sin(angle), base[1] + 9 * math.cos(angle))
        lock = s.paint(s.capsule(*base, *end, r0, r1), HAIR, group="hair")
        s.shift(lock & s.mask_line([base, end]), 1)
    s.paint(s.ellipse(*hc, 8.6, 8.4), ARMOR, group="helmet")
    s.paint(s.polygon([(hc[0] - 6, hc[1] - 6), (hc[0] + 12.5, hc[1] - 5), (hc[0] + 11.5, hc[1] - 2.5),
                       (hc[0] + 2, hc[1] - 3)], bevel=1.0), ARMOR, group="brim", bias=0.1)
    s.paint(s.polygon([(hc[0] + 1, hc[1] - 2), (hc[0] + 10, hc[1] - 2), (hc[0] + 10, hc[1] + 2.5),
                       (hc[0] + 7, hc[1] + 3.5), (hc[0] + 4, hc[1] + 2.5), (hc[0] + 1, hc[1] + 2.5)], bevel=1.2),
            VISOR, group="visor")
    s.paint(s.ellipse(hc[0] - 3, hc[1] + 3, 2.2, 1.6), GOLD, group="port")

    # Near side: shoulder pad and the Mitt Cannon arm.
    _pad(s, *near_shoulder, 0.0, "near_pad")
    elbow, hand = chain(*near_shoulder, pose.near_arm[0], 8, pose.near_arm[1], 8)
    s.paint(s.capsule(*near_shoulder, *elbow, 3.2, 3.0), ARMOR, group="near_arm")
    _mitt_cannon(s, elbow, hand, "near_arm")

    if attacking:
        if pose.smear is not None:
            _smear(s, far_shoulder, *pose.smear, "smear")
        far_elbow, far_hand = chain(*far_shoulder, pose.far_arm[0], 8, pose.far_arm[1], 8)
        _bat(s, far_hand, pose.bat, "bat")
        s.paint(s.capsule(*far_shoulder, *far_elbow, 3.0, 2.8), ARMOR, group="bat_arm")
        s.paint(s.capsule(*far_elbow, *far_hand, 2.8, 2.5), UNDER, group="bat_arm")
        _fist(s, *far_hand, 0.0, "bat_arm")
    return s


def idle() -> list[Pose]:
    breath = [(0, 0), (0, 0), (0, 1), (0, 1)]
    sway = [0.0, 0.06, 0.12, 0.06]
    return [Pose(upper=b, hair=h) for b, h in zip(breath, sway)]


def run() -> list[Pose]:
    poses = []
    for i in range(8):
        phase = 2 * math.pi * i / 8
        swing, lift = math.sin(phase), math.cos(phase)
        near = (0.6 * swing, -(0.15 + 1.1 * max(0.0, lift)))
        far = (-0.6 * swing, -(0.15 + 1.1 * max(0.0, -lift)))
        bob = round(2 * abs(swing) - 1)
        poses.append(Pose(
            body=(0, bob), upper=(1, 0), near_leg=near, far_leg=far,
            near_foot=0.5 * (near[0] + near[1]) if lift > 0 else 0.0,
            far_foot=0.5 * (far[0] + far[1]) if lift < 0 else 0.0,
            near_arm=(-0.5 * swing + 0.35, 1.0), far_arm=(0.5 * swing, 1.0),
            hair=0.25 + 0.12 * math.sin(2 * phase)))
    return poses


def swing() -> list[Pose]:
    lunge = dict(near_leg=(0.45, -0.1), far_leg=(-0.4, -0.25), far_foot=-0.2)
    return [
        Pose(upper=(-1, 0), far_arm=(math.pi - 0.7, -0.4), bat=math.pi + 0.5, near_arm=(0.5, 0.9)),
        Pose(upper=(0, -1), far_arm=(math.pi - 0.15, 0.2), bat=math.pi - 0.1, near_arm=(0.4, 0.9)),
        Pose(upper=(2, 0), far_arm=(math.pi / 2 - 0.2, 0.15), bat=math.pi / 2,
             smear=(math.pi - 0.1, math.pi / 2 + 0.05), near_arm=(0.1, 0.8), **lunge),
        Pose(upper=(2, 1), far_arm=(0.75, -0.1), bat=0.55, smear=(math.pi / 2 + 0.3, 0.6), near_arm=(0.0, 0.8),
             **lunge),
        Pose(upper=(1, 0), far_arm=(0.35, 0.1), bat=0.3, near_arm=(0.1, 0.7), near_leg=(0.3, -0.1),
             far_leg=(-0.25, -0.1)),
    ]


def jump() -> list[Pose]:
    return [
        Pose(near_leg=(0.7, -1.3), far_leg=(-0.1, -0.9), near_foot=-0.3, far_foot=-0.5, near_arm=(1.2, 0.6),
             far_arm=(2.4, 0.4), hair=-0.3, thrust=True),
        Pose(body=(0, -1), near_leg=(0.5, -1.0), far_leg=(-0.2, -0.6), near_foot=-0.2, far_foot=-0.3,
             near_arm=(0.9, 0.7), far_arm=(-0.6, 0.6), hair=-0.1),
    ]


def spaceball(frames: int = 4) -> list[Sprite]:
    """Spaceball mode: Sleve curls into a stitched, armored ball that rolls."""
    sprites = []
    for i in range(frames):
        s = Sprite(26, 26)
        s.paint(s.ellipse(13, 13, 10.5, 10.5), ARMOR)
        spin = 2 * math.pi * i / frames
        for side in (-1, 1):
            points = []
            for t in np.linspace(-1.25, 1.25, 16):
                u = side * (7.0 - 3.4 * math.cos(t))
                x = 13 + u * math.cos(spin * 0.5) + 2.5 * t * math.sin(spin * 0.5)
                y = 13 + 8.6 * math.sin(t)
                points.append((x, y))
            ball = s.opaque()
            s.fill(s.mask_line(points) & ball, LACE, 2)
            ticks = []
            for (x0, y0), (x1, y1) in zip(points[::2], points[1::2]):
                nx, ny = -(y1 - y0), x1 - x0
                length = math.hypot(nx, ny) or 1.0
                nx, ny = nx / length, ny / length
                ticks += [(x0 + nx * 1.4, y0 + ny * 1.4), (x0 - nx * 1.4, y0 - ny * 1.4)]
            s.fill(s.mask_points(ticks) & ball, STITCH, 2)
        s.paint(s.ellipse(9, 8.5, 2.2, 1.5), GOLD, bias=0.15)
        sprites.append(s)
    return sprites
