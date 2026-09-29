"""Render every VetroMania concept asset into assets/concept/.

Usage, from the repository root:

    python -m pip install -r tools/concept_art/requirements.txt
    python tools/concept_art/generate.py

Every random source is seeded, so with the pinned Pillow and NumPy versions a
re-run reproduces the committed files exactly. Native-resolution files (no
suffix) are the engine-facing art; files ending in @2x/@3x/@4x are
nearest-neighbor previews for documentation.
"""

from __future__ import annotations

import argparse
import math
import time
from pathlib import Path

import numpy as np
from PIL import Image

import bosses
import characters
import enemies
import items
import scenes
import screens
import world
from pixel import Canvas, hexc, save_gif, save_png, sheet, stack, text_mask, text_width, upscale

ROOT = Path(__file__).resolve().parents[2]
BACKDROP = (26, 18, 38)
WRITTEN: list[Path] = []

# Mirror-planet (Ainamortev) variants are palette swaps: a proud 16-bit tradition.
ENEMY_NAMES = {
    "space_bat": ("SPACE BAT", "ANTI-BAT", 0.35),
    "astro_zombie": ("ASTRO-ZOMBIE", "MOONWALKER", 0.55),
    "hunch_bot": ("HUNCH-BOT", "HUNCH-BOT TURBO HD REMIX", 0.15),
    "mer_man": ("MER-MAN", "NAM-REM", 0.3),
    "vampress": ("VAMPRESS", "SSERPMAV", 0.9),
}
BOSS_TURN = 0.5
ANIMATIONS = {
    "idle": (characters.idle, 180),
    "run": (characters.run, 90),
    "swing": (characters.swing, 80),
    "jump": (characters.jump, 160),
}


def _png(image: Image.Image, path: Path, scale: int = 1) -> None:
    save_png(image, path, scale)
    WRITTEN.append(path)


def _gif(frames: list[Image.Image], path: Path, *, scale: int, duration: int) -> None:
    save_gif(frames, path, scale=scale, duration=duration, background=BACKDROP)
    WRITTEN.append(path)


def _union_crop(frames: list[Image.Image], margin: int = 1) -> list[Image.Image]:
    """Crop same-size frames to their shared bounding box, so animations stay registered."""
    boxes = [box for box in (f.getbbox() for f in frames) if box]
    x0 = max(min(b[0] for b in boxes) - margin, 0)
    y0 = max(min(b[1] for b in boxes) - margin, 0)
    x1 = min(max(b[2] for b in boxes) + margin, frames[0].width)
    y1 = min(max(b[3] for b in boxes) + margin, frames[0].height)
    return [f.crop((x0, y0, x1, y1)) for f in frames]


def _label(text: str, scale: int, color=(235, 225, 255)) -> Image.Image:
    mask = text_mask(text, scale)
    rgba = np.zeros(mask.shape + (4,), np.uint8)
    rgba[mask] = color + (255,)
    return Image.fromarray(rgba, "RGBA")


def _grid(entries: list[tuple[str, Image.Image]], columns: int, *, scale: int = 4, title: str | None = None,
          gap: int = 12) -> Image.Image:
    """Documentation grid: images upscaled, bottom-aligned, and labeled underneath."""
    arts = [upscale(image.convert("RGBA"), scale) for _, image in entries]
    labels = [_label(name.upper(), 2) for name, _ in entries]
    cell_w = max(max(a.width for a in arts), max(lbl.width for lbl in labels)) + gap
    rows = math.ceil(len(entries) / columns)
    art_h = [max(a.height for a in arts[r * columns:(r + 1) * columns]) for r in range(rows)]
    label_h = labels[0].height + 6 + gap
    head = _label(title, 3, (255, 214, 64)) if title else None
    top = gap + (head.height + gap if head else 0)
    out = Image.new("RGBA", (gap + columns * cell_w, top + sum(art_h) + rows * label_h), BACKDROP + (255,))
    if head:
        out.alpha_composite(head, (gap, gap))
    inner = cell_w - gap
    for i, (art, label) in enumerate(zip(arts, labels)):
        r = i // columns
        x = gap + (i % columns) * cell_w
        y = top + sum(art_h[:r]) + r * label_h
        out.alpha_composite(art, (x + (inner - art.width) // 2, y + art_h[r] - art.height))
        out.alpha_composite(label, (x + (inner - label.width) // 2, y + art_h[r] + 6))
    return out


def _strip(frames: list[Image.Image], label: str) -> Image.Image:
    return sheet(frames, len(frames), pad=4, label=label, background=BACKDROP)


# Characters, enemies, and bosses ------------------------------------------------------

def build_characters(out: Path) -> None:
    folder = out / "characters"
    strips = []
    for name, (poses, duration) in ANIMATIONS.items():
        frames = _union_crop([characters.build(pose).render() for pose in poses()])
        _png(sheet(frames, len(frames), pad=0), folder / f"sleve_{name}.png")
        if len(frames) > 2:
            _gif(frames, folder / f"sleve_{name}.gif", scale=4, duration=duration)
        strips.append(_strip(frames, name.upper()))
    ball = _union_crop([sprite.render() for sprite in characters.spaceball()])
    _png(sheet(ball, len(ball), pad=0), folder / "sleve_spaceball.png")
    _gif(ball, folder / "sleve_spaceball.gif", scale=4, duration=70)
    strips.append(_strip(ball, "SPACEBALL"))
    _png(stack(strips, gap=0, background=BACKDROP), folder / "sleve_sheet@4x.png", scale=4)


def build_enemies(out: Path) -> None:
    folder = out / "enemies"
    normal, mirror = [], []
    for key, (build, count) in enemies.ENEMIES.items():
        name, mirror_name, turn = ENEMY_NAMES[key]
        sprites = [build(i) for i in range(count)]
        frames = _union_crop([sprite.render() for sprite in sprites])
        _png(sheet(frames, count, pad=0), folder / f"{key}.png")
        _gif(frames, folder / f"{key}.gif", scale=4, duration=140)
        normal.append(_strip(frames, name))
        swapped = _union_crop([scenes._sprite(sprite, turn)[0] for sprite in sprites])
        mirror.append(_strip(swapped, mirror_name))
    _png(stack(normal, gap=0, background=BACKDROP), folder / "bestiary_sheet@4x.png", scale=4)
    _png(stack(mirror, gap=0, background=BACKDROP), folder / "ainamortev_swaps@4x.png", scale=4)


def build_bosses(out: Path) -> None:
    folder = out / "bosses"
    sprites = [bosses.hot_coffee(i) for i in range(4)]
    frames = _union_crop([sprite.render() for sprite in sprites])
    cold = _union_crop([scenes._sprite(sprite, BOSS_TURN)[0] for sprite in sprites])
    _png(sheet(frames, len(frames), pad=0), folder / "hot_coffee.png")
    _gif(frames, folder / "hot_coffee.gif", scale=3, duration=180)
    _gif(cold, folder / "cold_brew.gif", scale=3, duration=180)
    strips = [_strip(frames, "HOTCOFFEE"), _strip(cold, "COLD BREW - AINAMORTEV")]
    _png(stack(strips, gap=0, background=BACKDROP), folder / "boss_sheet@2x.png", scale=2)


def lineup() -> Image.Image:
    """Scale reference: the cast standing on one ground line, with sprite heights."""
    cast = [("SLEVE", characters.build(characters.idle()[0]), 0), ("SPACE BAT", enemies.space_bat(0), 36),
            ("ASTRO-ZOMBIE", enemies.astro_zombie(0), 0), ("HUNCH-BOT", enemies.hunch_bot(0), 0),
            ("MER-MAN", enemies.mer_man(0), 0), ("VAMPRESS", enemies.vampress(0), 6),
            ("HOTCOFFEE", bosses.hot_coffee(0), 0)]
    rendered = []
    for name, sprite, hover in cast:
        image, emission = scenes._sprite(sprite)
        x0, y0, x1, y1 = image.getbbox()
        rendered.append((name, image.crop((x0, y0, x1, y1)), emission[y0:y1, x0:x1], hover))
    gap, margin = 18, 16
    ground = margin + max(image.height + hover for _, image, _, hover in rendered)
    cells = [max(image.width, text_width(name)) for name, image, _, _ in rendered]
    c = Canvas(margin * 2 + sum(cells) + gap * (len(cells) - 1), ground + 30, BACKDROP)
    c.rect(0, ground, c.w, ground + 1, (92, 78, 140))
    x = margin
    for (name, image, emission, hover), cell in zip(rendered, cells):
        c.blit(image, x + (cell - image.width) // 2, ground - hover - image.height, emission=emission)
        c.text(x + (cell - text_width(name)) // 2, ground + 6, name, (235, 225, 255))
        size = f"{image.height} PX"
        c.text(x + (cell - text_width(size)) // 2, ground + 17, size, (150, 140, 180))
        x += cell + gap
    c.bloom(radius=3, strength=0.5)
    return c.image()


def palettes() -> Image.Image:
    """Material ramps (dark to light, then the specular color) for each asset family."""
    families = [
        ("SLEVE", [characters.ARMOR, characters.UNDER, characters.GOLD, characters.VISOR, characters.HAIR,
                   characters.LEATHER, characters.BEAM, characters.MUZZLE, characters.THRUST]),
        ("HOTCOFFEE", [bosses.CHROME, bosses.COFFEE, bosses.CREMA, bosses.APRON, bosses.CERAMIC, bosses.CORE,
                       bosses.EYES]),
        ("BESTIARY", [enemies.FUR, enemies.SUIT, enemies.SKIN, enemies.RUST, enemies.SCALES, enemies.FIN,
                      enemies.CAPE, enemies.GOWN]),
        ("HULL CATHEDRAL", [world.STEEL, world.STONE, world.BACK, world.COPPER, world.HAZARD, world.VINE,
                            world.CONDUIT]),
    ]
    rows = [(name, [list(m.colors) + ([m.spec] if m.spec else []) for m in mats]) for name, mats in families]
    flipped = []
    for colors in rows[-1][1]:
        rgb = scenes.hue_rotate(np.array(colors, np.float64) / 255.0, 0.42) * 0.92
        flipped.append([tuple(int(v) for v in np.clip(rgb_row * 255 + 0.5, 0, 255)) for rgb_row in rgb])
    rows.append(("AINAMORTEV", flipped))
    rows.append(("NEBULA SKY", [[hexc(color) for color in world.NEBULA]]))
    rows.append(("RARITY", [[hexc(color) for color in items.RARITY.values()]]))
    left = max(text_width(name) for name, _ in rows) + 14
    width = left + max(sum(len(ramp) * 8 + 5 for ramp in ramps) for _, ramps in rows) + 4
    c = Canvas(width, 8 + len(rows) * 14, BACKDROP)
    for r, (name, ramps) in enumerate(rows):
        y = 6 + r * 14
        c.text(6, y + 1, name, (235, 225, 255))
        x = left
        for ramp in ramps:
            for color in ramp:
                c.rect(x, y, x + 8, y + 9, color)
                x += 8
            x += 5
    return c.image()


# World, items, and mockups ------------------------------------------------------------

def build_tiles(out: Path) -> None:
    folder = out / "tiles"
    tiles = world.render_tiles()
    _png(sheet([image for image, _ in tiles.values()], 8, pad=0), folder / "tileset.png")
    window, _ = world.gothic_window()
    _png(window, folder / "gothic_window.png")
    entries = [(name.replace("_", " "), image) for name, (image, _) in tiles.items()]
    _png(_grid(entries + [("gothic window", window)], 7, title="HULL CATHEDRAL TILES"),
         folder / "tileset_preview@4x.png")


def build_items(out: Path) -> None:
    folder = out / "items"
    gear = {name: build() for name, build in items.GEAR.items()}
    weapons = {name: build() for name, build in items.WEAPONS.items()}
    packs = {f"{kind} x{items.PACK_SIZE[color]} {color}": items.gem_pack(kind, color)
             for kind in ("armor", "weapon") for color in items.PACK_SIZE}
    icons = [s.render() for s in [*gear.values(), *weapons.values(), *packs.values(), items.vetro_buck()]]
    _png(sheet(icons, 6, pad=0), folder / "icons.png")
    card = [items.spaceball_card(i).render() for i in range(6)]
    _png(sheet(card, len(card), pad=0), folder / "spaceball_card.png")
    _gif(card, folder / "spaceball_card.gif", scale=6, duration=90)

    gear_rarity = ["magic", "rare", "common", "set", "magic", "rare", "legendary", "rare"]
    sections = [
        _grid([(n, items.framed(s, r)) for (n, s), r in zip(gear.items(), gear_rarity)], 4, title="ARMOR"),
        _grid([(n, items.framed(s, r)) for (n, s), r in zip(weapons.items(), ["legendary", "rare", "magic"])], 4,
              title="WEAPONS"),
        _grid([(n, s.render()) for n, s in packs.items()], 3, title="UPGRADE GEM PACKS"),
        _grid([(r, items.rarity_frame(r)) for r in items.RARITY], 5, title="RARITY"),
        _grid([("vetro-buck", items.vetro_buck().render()), ("spaceball card", card[0])], 4, title="MISC"),
    ]
    _png(stack(sections, gap=0, background=BACKDROP), folder / "items_sheet@4x.png")


MOCKUPS = {
    "gameplay": scenes.gameplay,
    "mirror": scenes.mirror,
    "title": screens.title,
    "equipment": screens.equipment,
    "world_map": screens.world_map,
}


def build_mockups(out: Path) -> None:
    folder = out / "mockups"
    for name, build in MOCKUPS.items():
        image = build().image()
        _png(image, folder / f"{name}.png")
        _png(image, folder / f"{name}@3x.png", scale=3)


def build_reference(out: Path) -> None:
    folder = out / "reference"
    _png(lineup(), folder / "lineup@2x.png", scale=2)
    _png(palettes(), folder / "palettes@4x.png", scale=4)


JOBS = [build_characters, build_enemies, build_bosses, build_tiles, build_items, build_mockups, build_reference]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Render the VetroMania concept assets.")
    parser.add_argument("--out", type=Path, default=ROOT / "assets" / "concept",
                        help="output directory (default: assets/concept in the repository)")
    args = parser.parse_args(argv)
    start = time.perf_counter()
    for job in JOBS:
        job(args.out)
        print(f"{job.__name__:<18} {len(WRITTEN):>3} files so far")
    size = sum(path.stat().st_size for path in WRITTEN) / 1e6
    print(f"wrote {len(WRITTEN)} files ({size:.1f} MB) to {args.out} in {time.perf_counter() - start:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
