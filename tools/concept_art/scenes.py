"""Mockup compositions at the native 640x360 resolution.

`gameplay()` builds a Hull Cathedral room on VetroMania; `mirror()` flips the
same room upside down with a hue-rotated palette, the way the planet "flips"
into Ainamortev after the true ending.
"""

from __future__ import annotations

import math

import numpy as np

import bosses
import characters
import enemies
import items
import ui
import world
from pixel import INK, Canvas, Sprite, glow, mix, text_width

W, H = 640, 360
FLOOR = 304
WINDOWS = [(112, 208), (272, 368), (432, 528)]
SPRING, SILL = 140, 268


def _place(c: Canvas, tiles, name: str, tx: int, ty: int) -> None:
    image, emission = tiles[name]
    c.blit(image, tx * 16, ty * 16, emission=emission)


def _dilate(mask: np.ndarray, steps: int) -> np.ndarray:
    out = mask.copy()
    for _ in range(steps):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out


def hue_rotate(rgb: np.ndarray, turn: float) -> np.ndarray:
    """Rotate hue in YIQ space (vectorized), keeping luminance."""
    to_yiq = np.array([[0.299, 0.587, 0.114], [0.596, -0.274, -0.322], [0.211, -0.523, 0.312]])
    angle = turn * 2 * math.pi
    c, s = math.cos(angle), math.sin(angle)
    rotate = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    matrix = np.linalg.inv(to_yiq) @ rotate @ to_yiq
    return np.clip(rgb @ matrix.T, 0, 1)


def sky_layer(seed: int = 3) -> Canvas:
    sky = Canvas(W, H)
    world.sky(sky, seed)
    world.stars(sky, seed + 2)
    world.planet(sky, 500, 92, 42)
    world.spires(sky, seed=21, base_y=292, color="#1b1231", window="#ffcf6a", heights=(50, 150), count=26, lit=0.22)
    world.spires(sky, seed=33, base_y=300, color="#120b22", window="#ff8ad8", heights=(20, 80), count=14,
                 widths=(14, 30), lit=0.15, rim="#2a1f45")
    return sky


def _poster(c: Canvas, x: int, y: int, lines: list[str]) -> None:
    width = max(text_width(line) for line in lines) + 10
    height = len(lines) * 10 + 8
    c.rect(x, y, x + width, y + height, (150, 32, 48))
    c.rect(x, y, x + width, y + 2, (196, 60, 72))
    c.rect(x + width - 6, y + height - 6, x + width, y + height, (36, 26, 52))
    for i, line in enumerate(lines):
        c.text(x + 5, y + 5 + i * 10, line, (246, 226, 190), shadow=(70, 12, 24))


def environment(seed: int = 3) -> Canvas:
    tiles = world.render_tiles()
    sky = sky_layer(seed)
    env = Canvas(W, H)
    for ty in range(H // 16 + 1):
        for tx in range(W // 16):
            _place(env, tiles, "back_wall", tx, ty)
    y, x = np.mgrid[0:H, 0:W] + 0.5
    openings = np.zeros((H, W), bool)
    for x0, x1 in WINDOWS:
        span = x1 - x0
        body = (x >= x0) & (x < x1) & (y >= SPRING) & (y < SILL)
        cap = ((y < SPRING) & ((x - x0) ** 2 + (y - SPRING) ** 2 < span ** 2)
               & ((x - x1) ** 2 + (y - SPRING) ** 2 < span ** 2))
        openings |= body | cap
    env.rgb[openings] = sky.rgb[openings]
    env.glow[openings] = sky.glow[openings]
    stone = [np.array(c) / 255.0 for c in world.STONE.colors]
    frame = _dilate(openings, 6) & ~openings
    reveal = _dilate(openings, 2) & ~openings
    for x0, x1 in WINDOWS:
        mid = (x0 + x1) / 2
        side = frame & (np.abs(x - mid) < (x1 - x0))
        env.rgb[side & (x < mid)] = stone[3]
        env.rgb[side & (x >= mid)] = stone[2]
        env.rgb[reveal & (np.abs(x - mid) < (x1 - x0)) & (x >= mid)] = stone[1]
        mullion = openings & (np.abs(x - mid) < 1.5)
        transom = openings & (np.abs(y - (SPRING + 36)) < 1.5)
        env.rgb[mullion | transom] = stone[1]
        env.rgb[(mullion | transom) & (x < mid - 0.5)] = stone[3]
    outline = _dilate(frame, 1) & ~frame & ~openings
    env.rgb[outline] = np.array(INK) / 255.0

    for tx in range(W // 16):
        _place(env, tiles, "brick", tx, 0)
        _place(env, tiles, "brick", tx, 1)
        _place(env, tiles, "brick_conduit", tx, 2)
        _place(env, tiles, "pipe_h", tx, 16)
        _place(env, tiles, "brick", tx, 17)
        _place(env, tiles, "floor_top", tx, FLOOR // 16)
        for ty in range(FLOOR // 16 + 1, H // 16 + 1):
            _place(env, tiles, "floor_fill", tx, ty)
    for ty in range(3, 16):
        _place(env, tiles, "pillar", 0, ty)
        _place(env, tiles, "pillar", W // 16 - 1, ty)
    for tx in (5, 21, 34):
        _place(env, tiles, "vine", tx, 3)
    for tx, ty in ((15, 6), (24, 6)):
        _place(env, tiles, "light_panel", tx, ty)
    for tx in range(30, 36):
        _place(env, tiles, "platform", tx, 13)
    _poster(env, 217, 136, ["ALL", "YOUR", "BASE", "ARE", "BELONG", "TO US"])
    return env


def _floor_y(image, floor: int) -> int:
    return floor - image.getbbox()[3]


def _sprite(sprite, turn: float | None = None):
    """Render a Sprite, optionally hue-rotating it into its mirror-planet variant."""
    image = sprite.render()
    emission = sprite.emission()
    if turn is None:
        return image, emission
    rgba = np.asarray(image, np.float64) / 255.0
    rgba[..., :3] = hue_rotate(rgba[..., :3], turn)
    from PIL import Image

    return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA"), hue_rotate(emission, turn)


def _spark(c: Canvas, x: int, y: int, size: int = 7, color=(255, 246, 200)) -> None:
    arms = np.zeros((size * 2 + 1, size * 2 + 1), bool)
    arms[size, :] = True
    arms[:, size] = True
    for d in range(-size // 2, size // 2 + 1):
        arms[size + d, size + d] = True
        arms[size + d, size - d] = True
    c.fill(arms, color, x - size, y - size)
    c.add_glow(arms, color, x - size, y - size, strength=1.2)


def _loot_beam(c: Canvas, x: int, top: int, bottom: int, color) -> None:
    from pixel import bayer

    height = bottom - top
    fade = np.linspace(0, 1, height)[:, None] * np.ones((1, 7))
    keep = fade > bayer(7, height) * 0.9
    core = keep & (np.abs(np.arange(7) - 3) <= 1)[None, :]
    c.fill(keep, color, x - 3, top, alpha=0.55)
    c.fill(core, mix(color, (255, 255, 255), 0.6), x - 3, top)
    c.add_glow(keep, color, x - 3, top, strength=0.5)


def _hud(c: Canvas, *, level: int, hp: tuple[int, int], ep: tuple[int, int], xp: float) -> None:
    ui.panel(c, 6, 6, 42, 42)
    c.blit(items.helm().render(), 12, 12)
    ui.label(c, 9, 46, f"LV {level}", (255, 214, 64))
    ui.label(c, 48, 10, "HP")
    ui.bar(c, 64, 11, 104, 6, hp[0] / hp[1], (230, 60, 76))
    ui.label(c, 174, 10, f"{hp[0]}/{hp[1]}")
    ui.label(c, 48, 22, "EP")
    ui.bar(c, 64, 23, 104, 5, ep[0] / ep[1], (57, 200, 255))
    ui.label(c, 174, 22, f"{ep[0]}/{ep[1]}")
    ui.bar(c, 48, 33, 150, 2, xp, (255, 214, 64), glow=False)
    ui.minimap(c, 560, 12)
    c.blit(items.framed(items.beam_bat(), "legendary"), 8, 324)
    c.blit(items.framed(items.mitt_cannon(), "rare"), 40, 324)
    x = 452
    x += ui.counter(c, x, 340, ui.mini_gem("armor", "blue"), "X23") + 10
    x += ui.counter(c, x, 340, ui.mini_gem("weapon", "ruby"), "X11") + 10
    ui.counter(c, x, 340, ui.mini_coin(), "4096")


def gameplay() -> Canvas:
    c = environment()
    ground = FLOOR

    boots = items.boots().render()
    _loot_beam(c, 452, 150, ground - 4, (255, 214, 64))
    c.blit(boots, 440, ground - 22)
    drop = "OVERCLOCKED MAG-BOOTS"
    ui.label(c, 452 - text_width(drop) // 2, 138, drop, (255, 214, 64), backing=True)
    c.blit(items.gem_pack("weapon", "blue").render(), 300, ground - 22)

    hunch, glow_h = _sprite(enemies.hunch_bot(0))
    c.blit(hunch, 490, _floor_y(hunch, 208), emission=glow_h, flip=True)
    zombie, glow_z = _sprite(enemies.astro_zombie(1))
    c.blit(zombie, 328, _floor_y(zombie, ground), emission=glow_z, flip=True)

    sleve = characters.build(characters.swing()[2])
    image, emission = _sprite(sleve)
    sy = _floor_y(image, ground)
    c.blit(image, 152, sy, emission=emission)
    bat, glow_b = _sprite(enemies.space_bat(2))
    c.blit(bat, 216, sy + 32, emission=glow_b, flip=True)
    bat2, glow_b2 = _sprite(enemies.space_bat(0))
    c.blit(bat2, 360, 96, emission=glow_b2, flip=True)
    _spark(c, 231, sy + 52)
    c.text(222, sy + 8, "37", (255, 236, 150), scale=2, glow=(255, 180, 60))
    c.text(254, sy + 12, "CRIT!", (255, 138, 28))

    drone = Sprite(12, 12)
    drone.paint(drone.ellipse(6, 6, 4, 4), glow("#8ff0ff"))
    drone.paint(drone.ellipse(2, 4, 2.2, 1.2), items.SILVER)
    drone.paint(drone.ellipse(10, 4, 2.2, 1.2), items.SILVER)
    c.blit(drone.render(), 132, sy + 6, emission=drone.emission())
    bubble = "HEY! LISTEN!"
    ui.panel(c, 88, sy - 14, 94 + text_width(bubble) + 6, sy - 1, edge=(143, 240, 255))
    c.text(94, sy - 10, bubble, (220, 250, 255))

    ui.panel(c, 226, 6, 414, 42)
    ui.label(c, 234, 11, "SPACE BAT TALLY", (216, 216, 224))
    ui.label(c, 352, 11, "187/200", (255, 214, 64))
    ui.bar(c, 234, 22, 172, 4, 187 / 200, (178, 110, 255))
    ui.label(c, 234, 31, "13 MORE: ECHOLOCATION PING", (150, 140, 180))
    _hud(c, level=18, hp=(262, 334), ep=(47, 82), xp=0.62)
    name = "HULL CATHEDRAL"
    ui.label(c, (W - text_width(name)) // 2, 340, name, (236, 230, 255), backing=True)
    c.bloom()
    return c


def mirror() -> Canvas:
    """Ainamortev: the flipped planet. Same room, upside down, hue-rotated."""
    env = environment()
    c = Canvas(W, H)
    c.rgb = hue_rotate(env.rgb[::-1].copy(), 0.42) * 0.92
    c.glow = hue_rotate(env.glow[::-1].copy(), 0.42)
    ground = H - 48

    boss, glow_boss = _sprite(bosses.hot_coffee(1), turn=0.5)
    c.blit(boss, 430, _floor_y(boss, ground), emission=glow_boss, flip=True)
    for (bx, by), frame in (((300, 70), 1), ((540, 150), 3)):
        bat, glow_b = _sprite(enemies.space_bat(frame), turn=0.35)
        c.blit(bat, bx, by, emission=glow_b, flip=True)

    sleve = characters.build(characters.jump()[0])
    image, emission = _sprite(sleve)
    c.blit(image, 120, _floor_y(image, ground - 44), emission=emission)
    shot = Sprite(20, 12)
    shot.paint(shot.capsule(2, 6, 12, 6, 1.5, 3.2), glow("#39e6ff"))
    shot.paint(shot.ellipse(14, 6, 4.2, 4.2), glow("#bff6ff"))
    c.blit(shot.render(), 236, ground - 104, emission=shot.emission())

    ui.panel(c, 128, 326, 512, 354, edge=(255, 84, 120))
    ui.label(c, 136, 331, "COLD BREW", (160, 230, 255))
    ui.label(c, 136 + text_width("COLD BREW") + 8, 331, "HOTCOFFEE'S DECAF DOPPELGANGER", (150, 140, 180))
    ui.bar(c, 136, 343, 368, 5, 0.71, (255, 84, 120))
    _hud(c, level=44, hp=(583, 742), ep=(97, 142), xp=0.18)
    banner = "AINAMORTEV  -  MAP 142.7%"
    ui.panel(c, (W - text_width(banner)) // 2 - 8, 8, (W + text_width(banner)) // 2 + 8, 24, edge=(96, 232, 120))
    ui.label(c, (W - text_width(banner)) // 2, 13, banner, (180, 255, 190))
    c.bloom()
    return c
