from __future__ import annotations

import argparse
import filecmp
import importlib
import json
import math
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
CONCEPT_ROOT = ROOT / "tools" / "concept_art"
if str(CONCEPT_ROOT) not in sys.path:
    sys.path.insert(0, str(CONCEPT_ROOT))

bosses = importlib.import_module("bosses")
characters = importlib.import_module("characters")
enemies = importlib.import_module("enemies")
generate = importlib.import_module("generate")
items = importlib.import_module("items")
pixel = importlib.import_module("pixel")
props = importlib.import_module("props")
scenes = importlib.import_module("scenes")
screens = importlib.import_module("screens")
world = importlib.import_module("world")


def _mkdir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _save_png(path: Path, image: Image.Image) -> None:
    _mkdir(path)
    image.save(path, optimize=True)


def _transparent(size: tuple[int, int] = (1, 1)) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0))


def _sheet(frames: list[Image.Image]) -> Image.Image:
    width = sum(frame.width for frame in frames)
    height = frames[0].height
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = 0
    for frame in frames:
        out.alpha_composite(frame.convert("RGBA"), (x, 0))
        x += frame.width
    return out


def _union_box(frames: list[Image.Image], margin: int = 0) -> tuple[int, int, int, int]:
    boxes = [frame.getbbox() for frame in frames if frame.getbbox()]
    if not boxes:
        return 0, 0, frames[0].width, frames[0].height
    x0 = max(min(box[0] for box in boxes) - margin, 0)
    y0 = max(min(box[1] for box in boxes) - margin, 0)
    x1 = min(max(box[2] for box in boxes) + margin, frames[0].width)
    y1 = min(max(box[3] for box in boxes) + margin, frames[0].height)
    return x0, y0, x1, y1


def _crop_frames(frames: list[Image.Image], box: tuple[int, int, int, int]) -> list[Image.Image]:
    return [frame.crop(box) for frame in frames]


def _bbox(frames: list[Image.Image]) -> list[int]:
    box = _union_box(frames)
    return [box[0], box[1], box[2], box[3]]


def _bottom_opaque(image: Image.Image) -> int:
    alpha = np.asarray(image.convert("RGBA"))[..., 3]
    rows = np.where(alpha.any(axis=1))[0]
    return int(rows.max()) if rows.size else image.height - 1


def _render_frames(builds: list[pixel.Sprite], *, outline: bool = True, contact: bool = True) -> list[Image.Image]:
    return [sprite.render(outline=outline, contact=contact) for sprite in builds]


def _emission_frames(builds: list[pixel.Sprite]) -> list[np.ndarray]:
    return [sprite.emission() for sprite in builds]


def _sprite_entry(out_dir: Path, manifest: dict, group: str, name: str, frames: list[Image.Image], *,
                  pivot: tuple[int, int], fps: float, loop: bool) -> None:
    key = f"{group}/{name}"
    rel = Path("sprites") / group / f"{name}.png"
    _save_png(out_dir / rel, _sheet(frames))
    manifest["sprites"][key] = {
        "bbox": _bbox(frames),
        "file": rel.as_posix(),
        "fps": fps,
        "frame_size": [frames[0].width, frames[0].height],
        "frames": len(frames),
        "loop": loop,
        "pivot": [pivot[0], pivot[1]],
    }


def _variant_image(image: Image.Image, emission: np.ndarray, *, turn: float, brightness: float = 1.0,
                   tint: tuple[int, int, int] | None = None, tint_strength: float = 0.0,
                   emissive_turn: float | None = None, emissive_boost: float = 1.0) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), np.float64) / 255.0
    rgb = scenes.hue_rotate(rgba[..., :3], turn)
    if tint is not None and tint_strength:
        tint_rgb = np.array(tint, np.float64) / 255.0
        rgb = rgb * (1 - tint_strength) + tint_rgb * tint_strength
    rgb = np.clip(rgb * brightness, 0, 1)
    if emission.size:
        mask = np.clip(emission.max(axis=2, keepdims=True) * 1.25, 0, 1)
        emissive_rgb = scenes.hue_rotate(rgba[..., :3], emissive_turn if emissive_turn is not None else turn)
        emissive_rgb = np.clip(emissive_rgb * emissive_boost, 0, 1)
        rgb = rgb * (1 - mask) + emissive_rgb * mask
    rgba[..., :3] = rgb
    return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")


def _sprite_variants(builds: list[pixel.Sprite], *, turn: float) -> list[Image.Image]:
    return [scenes._sprite(sprite, turn)[0] for sprite in builds]


def _transparent_from_canvas(canvas: pixel.Canvas) -> Image.Image:
    rgb = np.clip(canvas.rgb, 0, 1)
    mask = rgb.max(axis=2) > 0
    rgba = np.zeros((canvas.h, canvas.w, 4), np.uint8)
    rgba[..., :3] = (rgb * 255 + 0.5).astype(np.uint8)
    rgba[..., 3] = mask.astype(np.uint8) * 255
    return Image.fromarray(rgba, "RGBA")


def _export_sleve(out_dir: Path, manifest: dict) -> None:
    rig_anims = {
        "idle": (characters.idle, 5.5, True),
        "run": (characters.run, 11.0, True),
        "swing": (characters.swing, 12.0, False),
        "jump": (characters.jump, 6.0, False),
        "slide": (characters.slide, 1.0, False),
        "backdash": (characters.backdash, 1.0, False),
        "hurt": (characters.hurt, 1.0, False),
        "wall_slide": (characters.wall_slide, 1.0, False),
    }
    idle_frame = characters.build(characters.idle()[0]).render()
    ground = _bottom_opaque(idle_frame) + 1
    rig_pivot = (characters.HIP[0], ground)
    for name, (build, fps, loop) in rig_anims.items():
        frames = [characters.build(pose).render() for pose in build()]
        _sprite_entry(out_dir, manifest, "sleve", name, frames, pivot=rig_pivot, fps=fps, loop=loop)
    ball = [sprite.render() for sprite in characters.spaceball()]
    _sprite_entry(out_dir, manifest, "sleve", "spaceball", ball, pivot=(ball[0].width // 2, ball[0].height),
                  fps=14.0, loop=True)


def _export_enemies(out_dir: Path, manifest: dict) -> None:
    for name, (build, count) in enemies.ENEMIES.items():
        sprites = [build(i) for i in range(count)]
        frames = [sprite.render() for sprite in sprites]
        box = _union_box(frames, margin=1)
        cropped = _crop_frames(frames, box)
        if name == "space_bat":
            pivot = (cropped[0].width // 2, cropped[0].height // 2)
        else:
            pivot = (cropped[0].width // 2, cropped[0].height)
        _sprite_entry(out_dir, manifest, "enemies", name, cropped, pivot=pivot, fps=7.0, loop=True)

        turn = generate.ENEMY_NAMES[name][2]
        mirror = _crop_frames(_sprite_variants(sprites, turn=turn), box)
        _sprite_entry(out_dir, manifest, "enemies", f"{name}_mirror", mirror, pivot=pivot, fps=7.0, loop=True)


def _export_bosses(out_dir: Path, manifest: dict) -> None:
    coffee_builds = [bosses.hot_coffee(i) for i in range(4)]
    coffee_frames = [sprite.render() for sprite in coffee_builds]
    coffee_box = _union_box(coffee_frames, margin=1)
    cropped = _crop_frames(coffee_frames, coffee_box)
    pivot = (cropped[0].width // 2, cropped[0].height)
    _sprite_entry(out_dir, manifest, "bosses", "hot_coffee", cropped, pivot=pivot, fps=5.5, loop=True)
    cold = _crop_frames(_sprite_variants(coffee_builds, turn=generate.BOSS_TURN), coffee_box)
    _sprite_entry(out_dir, manifest, "bosses", "cold_brew", cold, pivot=pivot, fps=5.5, loop=True)
    for state, fps, loop in (("idle", 3.0, True), ("windup", 8.0, False), ("slam", 8.0, False),
                             ("chomp", 8.0, False)):
        frames = [sprite.render() for sprite in props.KRATE_ANIMS[state]]
        pivot = (frames[0].width // 2, frames[0].height)
        _sprite_entry(out_dir, manifest, "bosses", f"krate_{state}", frames, pivot=pivot, fps=fps, loop=loop)


def _export_props(out_dir: Path, manifest: dict) -> None:
    metadata = {
        "chest": (2.0, False, "ground"),
        "save_pod": (6.0, True, "ground"),
        "door": (4.0, False, "ground"),
        "vending_machine": (5.0, True, "ground"),
        "koozie_statue": (4.0, True, "ground"),
        "warp_pipe": (1.0, False, "ground"),
        "signing_table": (4.0, True, "ground"),
        "nag9000": (8.0, True, "center"),
        "ability_orb": (10.0, True, "center"),
        "hologram_ring": (7.0, True, "ground"),
        "hit_spark": (16.0, False, "center"),
        "mitt_shot": (16.0, False, "center"),
        "mitt_shot_charged": (14.0, False, "center"),
        "enemy_bolt": (14.0, False, "center"),
        "pickup_glint": (18.0, False, "center"),
    }
    for source in (props.PROPS, props.RUNTIME_PROPS, props.EFFECTS):
        for name, build in source.items():
            sprites = build()
            frames = [sprite.render() for sprite in sprites]
            mode = metadata[name][2]
            pivot = (frames[0].width // 2, frames[0].height if mode == "ground" else frames[0].height // 2)
            _sprite_entry(out_dir, manifest, "props", name, frames, pivot=pivot, fps=metadata[name][0],
                          loop=metadata[name][1])


def _render_tile_entries() -> list[tuple[str, Image.Image, np.ndarray]]:
    entries: list[tuple[str, Image.Image, np.ndarray]] = []
    for name, (image, emission) in world.render_tiles().items():
        entries.append((name, image, emission))
    for name, build in props.TILES.items():
        sprite = build()
        entries.append((name, sprite.render(outline=False, contact=False), sprite.emission()))
    return entries


def _tile_variant(image: Image.Image, emission: np.ndarray, flavor: str) -> Image.Image:
    if flavor == "crash":
        return _variant_image(image, emission, turn=-0.08, brightness=1.0, tint=(238, 152, 92), tint_strength=0.12,
                              emissive_turn=0.0, emissive_boost=1.12)
    if flavor == "outer":
        return _variant_image(image, emission, turn=0.24, brightness=0.76, tint=(84, 120, 184), tint_strength=0.1,
                              emissive_turn=0.12, emissive_boost=1.08)
    return image


def _tile_atlas(entries: list[tuple[str, Image.Image]], columns: int = 8) -> Image.Image:
    tile = 16
    rows = math.ceil(len(entries) / columns)
    atlas = Image.new("RGBA", (columns * tile, rows * tile), (0, 0, 0, 0))
    for index, (_, image) in enumerate(entries):
        atlas.alpha_composite(image.convert("RGBA"), ((index % columns) * tile, (index // columns) * tile))
    return atlas


def _export_tiles(out_dir: Path, manifest: dict) -> None:
    rendered = _render_tile_entries()
    hull = [(name, image) for name, image, _ in rendered]
    crash = [(name, _tile_variant(image, emission, "crash")) for name, image, emission in rendered]
    outer = [(name, _tile_variant(image, emission, "outer")) for name, image, emission in rendered]
    atlases = {"hull": hull, "crash": crash, "outer": outer}
    for flavor, entries in atlases.items():
        _save_png(out_dir / "tiles" / f"{flavor}.png", _tile_atlas(entries))
    manifest["tiles"] = {
        "atlases": {name: f"tiles/{name}.png" for name in ("hull", "crash", "outer")},
        "columns": 8,
        "index": {name: [idx % 8, idx // 8] for idx, (name, _) in enumerate(hull)},
        "tile_size": 16,
    }


def _far_layer(area: str) -> Image.Image:
    c = pixel.Canvas(1280, 360)
    if area == "crash":
        palette = ["#130615", "#2c1028", "#57213e", "#8a3653", "#c4575d", "#f08c5f", "#ffc685", "#ffd7b8"]
        world.sky(c, seed=31, palette=palette)
        world.stars(c, seed=43, count=190)
        world.planet(c, 280, 315, 230, seed=17, ring=False,
                     palette=("#52212a", "#8d3a40", "#c55b48", "#f08b56", "#ffc779", "#fff0bb"))
        world.planet(c, 1040, 112, 54, seed=22, ring=False,
                     palette=("#2b1740", "#5d296d", "#8c3f8d", "#d07ba2", "#ffd2d0", "#fff4e6"))
    elif area == "outer":
        palette = ["#040715", "#08112a", "#102149", "#17315f", "#1f4777", "#255b8b", "#25708f", "#2d8c98"]
        world.sky(c, seed=52, palette=palette)
        world.stars(c, seed=61, count=420)
        world.planet(c, 980, 116, 100, seed=29, ring=True,
                     palette=("#081427", "#12304f", "#1a4a6b", "#276e8a", "#4ea0b8", "#b6ecff"))
    else:
        world.sky(c, seed=8)
        world.stars(c, seed=12, count=340)
        world.planet(c, 980, 118, 96, seed=5, ring=True, palette=screens.VETRO_PLANET)
    return c.image().convert("RGBA")


def _mid_layer(area: str) -> Image.Image:
    c = pixel.Canvas(1280, 360, (0, 0, 0))
    if area == "crash":
        world.spires(c, seed=77, base_y=316, color="#170a12", window="#ffb46d", heights=(40, 120), count=18, lit=0.12,
                     rim="#311622")
        world.spires(c, seed=79, base_y=328, color="#10050e", window="#ff7e58", heights=(24, 72), count=10,
                     widths=(18, 34), lit=0.08, rim="#241017")
    elif area == "outer":
        world.spires(c, seed=84, base_y=316, color="#08101c", window="#67d4ff", heights=(46, 132), count=20, lit=0.16,
                     rim="#173452")
        world.spires(c, seed=87, base_y=330, color="#05090f", window="#7cf4ff", heights=(24, 70), count=12,
                     widths=(16, 28), lit=0.11, rim="#10253a")
    else:
        world.spires(c, seed=44, base_y=316, color="#100917", window="#ffcf6a", heights=(44, 124), count=20, lit=0.18,
                     rim="#261939")
        world.spires(c, seed=46, base_y=326, color="#0a0612", window="#ff84d8", heights=(24, 74), count=12,
                     widths=(16, 30), lit=0.12, rim="#1b1030")
    return _transparent_from_canvas(c)


def _draw_wreckage() -> Image.Image:
    image = Image.new("RGBA", (1280, 360), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    layers = [
        ((12, 12, 20, 230), (38, 24, 34, 255)),
        ((18, 18, 28, 255), (18, 10, 17, 255)),
    ]
    for color, accent in layers:
        pieces = [
            [(0, 300), (110, 242), (210, 260), (330, 210), (390, 222), (470, 184), (560, 220), (640, 196),
             (720, 230), (860, 212), (980, 250), (1110, 220), (1280, 264), (1280, 360), (0, 360)],
            [(120, 360), (160, 300), (226, 300), (240, 360)],
            [(522, 360), (566, 280), (626, 280), (648, 360)],
            [(968, 360), (1016, 292), (1088, 292), (1114, 360)],
        ]
        for piece in pieces:
            draw.polygon(piece, fill=color)
        for x in (124, 526, 974):
            draw.rectangle((x + 10, 302, x + 16, 348), fill=accent)
        draw.rectangle((706, 248, 744, 262), fill=accent)
        draw.rectangle((714, 226, 736, 244), fill=accent)
    return image


def _draw_truss() -> Image.Image:
    image = Image.new("RGBA", (1280, 360), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    base = (8, 12, 22, 255)
    edge = (20, 38, 58, 255)
    top = 234
    draw.rectangle((0, top, 1280, 254), fill=base)
    draw.rectangle((0, top, 1280, top + 3), fill=edge)
    for left in range(-30, 1280, 90):
        draw.rectangle((left + 14, top - 76, left + 24, 360), fill=base)
        draw.rectangle((left + 14, top - 76, left + 24, top - 72), fill=edge)
        draw.polygon([(left + 24, top - 64), (left + 82, top + 2), (left + 74, top + 2), (left + 14, top - 54)],
                     fill=edge)
        draw.polygon([(left + 14, top + 2), (left + 74, top - 62), (left + 82, top - 62), (left + 24, top + 2)],
                     fill=edge)
    return image


def _near_layer(area: str) -> Image.Image:
    if area == "crash":
        return _draw_wreckage()
    if area == "outer":
        return _draw_truss()
    c = pixel.Canvas(1280, 360, (0, 0, 0))
    world.colonnade(c, top=116, bottom=360, spacing=152, color="#060610", light="#16162a", offset=22)
    return _transparent_from_canvas(c)


def _export_backgrounds(out_dir: Path, manifest: dict) -> None:
    data = {}
    for area in ("crash", "hull", "outer"):
        far = _far_layer(area)
        mid = _mid_layer(area)
        near = _near_layer(area)
        _save_png(out_dir / "backgrounds" / f"{area}_far.png", far)
        _save_png(out_dir / "backgrounds" / f"{area}_mid.png", mid)
        _save_png(out_dir / "backgrounds" / f"{area}_near.png", near)
        data[area] = {
            "far": f"backgrounds/{area}_far.png",
            "mid": f"backgrounds/{area}_mid.png",
            "near": f"backgrounds/{area}_near.png",
        }
    manifest["backgrounds"] = data


def _icon_frames() -> tuple[Image.Image, dict]:
    order = [
        ("helm", items.helm),
        ("chest", items.chest),
        ("gauntlets", items.gauntlets),
        ("gloves", items.gloves),
        ("leggings", items.leggings),
        ("boots", items.boots),
        ("ring_band", lambda: items.ring("band")),
        ("ring_halo", lambda: items.ring("halo")),
        ("beam_bat", items.beam_bat),
        ("mitt_cannon", items.mitt_cannon),
        ("plasma_whip", items.plasma_whip),
        ("vetro_buck", items.vetro_buck),
        ("gem_armor_white", lambda: items.gem_pack("armor", "white")),
        ("gem_armor_blue", lambda: items.gem_pack("armor", "blue")),
        ("gem_armor_ruby", lambda: items.gem_pack("armor", "ruby")),
        ("gem_weapon_white", lambda: items.gem_pack("weapon", "white")),
        ("gem_weapon_blue", lambda: items.gem_pack("weapon", "blue")),
        ("gem_weapon_ruby", lambda: items.gem_pack("weapon", "ruby")),
        ("mega_mallet", props.mega_mallet),
        ("box_cutter", props.box_cutter),
        ("spread_gun", props.spread_gun),
        ("throwable", props.throwable),
        ("space_burrito", props.space_burrito),
        ("energy_drink", props.energy_drink),
    ]
    columns = 8
    size = 24
    rows = math.ceil(len(order) / columns)
    atlas = Image.new("RGBA", (columns * size, rows * size), (0, 0, 0, 0))
    index = {}
    for i, (name, build) in enumerate(order):
        atlas.alpha_composite(build().render(), ((i % columns) * size, (i // columns) * size))
        index[name] = [i % columns, i // columns]
    return atlas, {"file": "items/icons.png", "icon_size": 24, "columns": 8, "index": index}


def _rarity_frames() -> tuple[Image.Image, dict]:
    order = ["common", "magic", "rare", "legendary", "set"]
    frames = [items.rarity_frame(name) for name in order]
    return _sheet(frames), {"file": "items/rarity_frames.png", "size": 28, "order": order}


def _spaceball_card() -> tuple[Image.Image, dict]:
    frames = [items.spaceball_card(i).render() for i in range(6)]
    return _sheet(frames), {"file": "items/spaceball_card.png", "frames": 6, "frame_size": [24, 32]}


def _export_items(out_dir: Path, manifest: dict) -> None:
    icons, icon_meta = _icon_frames()
    rarity, rarity_meta = _rarity_frames()
    card, card_meta = _spaceball_card()
    _save_png(out_dir / "items" / "icons.png", icons)
    _save_png(out_dir / "items" / "rarity_frames.png", rarity)
    _save_png(out_dir / "items" / "spaceball_card.png", card)
    manifest["items"] = {"icons": icon_meta, "rarity_frames": rarity_meta, "spaceball_card": card_meta}


def _font_assets() -> tuple[Image.Image, str]:
    glyphs = list(pixel.FONT.keys())
    columns = 8
    cell_w, cell_h = 6, 9
    rows = math.ceil(len(glyphs) / columns)
    atlas = Image.new("RGBA", (columns * cell_w, rows * cell_h), (0, 0, 0, 0))
    chars: dict[str, tuple[int, int, int, int]] = {}
    for i, ch in enumerate(glyphs):
        x = (i % columns) * cell_w
        y = (i // columns) * cell_h
        mask = pixel.FONT[ch]
        glyph = np.zeros((mask.shape[0], mask.shape[1], 4), np.uint8)
        glyph[mask] = (255, 255, 255, 255)
        atlas.alpha_composite(Image.fromarray(glyph, "RGBA"), (x, y))
        chars[ch] = (x, y, pixel.GLYPH_W, pixel.GLYPH_H)
    for ch in "abcdefghijklmnopqrstuvwxyz":
        chars[ch] = chars[ch.upper()]
    lines = [
        'info face="vetro5x7" size=7 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=1,1',
        f"common lineHeight=9 base=7 scaleW={atlas.width} scaleH={atlas.height} pages=1 packed=0",
        'page id=0 file="vetro5x7.png"',
        f"chars count={len(chars)}",
    ]
    for ch, (x, y, w, h) in chars.items():
        lines.append(
            f"char id={ord(ch)} x={x} y={y} width={w} height={h} xoffset=0 yoffset=0 xadvance=6 page=0 chnl=15"
        )
    lines.append("kernings count=0")
    return atlas, "\n".join(lines) + "\n"


def _export_ui(out_dir: Path, manifest: dict) -> None:
    title = screens.title(start=False).image().convert("RGBA")
    _save_png(out_dir / "ui" / "title_bg.png", title)
    atlas, fnt = _font_assets()
    _save_png(out_dir / "ui" / "font" / "vetro5x7.png", atlas)
    font_path = out_dir / "ui" / "font" / "vetro5x7.fnt"
    _mkdir(font_path)
    font_path.write_text(fnt, encoding="utf-8", newline="\n")
    manifest["ui"] = {"font": "ui/font/vetro5x7.fnt", "title_bg": "ui/title_bg.png"}


def _build_manifest(out_dir: Path) -> dict:
    manifest = {"version": 1, "sprites": {}}
    _export_sleve(out_dir, manifest)
    _export_enemies(out_dir, manifest)
    _export_bosses(out_dir, manifest)
    _export_props(out_dir, manifest)
    _export_tiles(out_dir, manifest)
    _export_items(out_dir, manifest)
    _export_backgrounds(out_dir, manifest)
    _export_ui(out_dir, manifest)
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return manifest


GENERATED_ROOTS = ["backgrounds", "items", "manifest.json", "sprites", "tiles", "ui"]


def _generated_files(root: Path) -> list[str]:
    files: list[str] = []
    for name in GENERATED_ROOTS:
        path = root / name
        if path.is_file():
            if path.suffix != ".import":
                files.append(name)
        elif path.exists():
            for child in path.rglob("*"):
                if child.is_file() and child.suffix != ".import":
                    files.append(child.relative_to(root).as_posix())
    return sorted(files)


def _same_file(expected: Path, actual: Path) -> bool:
    """PNGs are compared by decoded pixels, so a different zlib build does not fail the check."""
    if expected.suffix == ".png":
        with Image.open(expected) as left, Image.open(actual) as right:
            return left.mode == right.mode and left.size == right.size and left.tobytes() == right.tobytes()
    return filecmp.cmp(expected, actual, shallow=False)


def _compare_trees(expected: Path, actual: Path) -> list[str]:
    messages: list[str] = []
    left = set(_generated_files(expected))
    right = set(_generated_files(actual))
    for rel in sorted(left - right):
        messages.append(f"missing: {rel}")
    for rel in sorted(right - left):
        messages.append(f"extra: {rel}")
    for rel in sorted(left & right):
        if not _same_file(expected / rel, actual / rel):
            messages.append(f"different: {rel}")
    return messages


def _sync_tree(src: Path, dst: Path) -> None:
    expected = set(_generated_files(src))
    existing = set(_generated_files(dst))
    for rel in sorted(existing - expected, reverse=True):
        path = dst / rel
        if path.exists():
            path.unlink()
    for rel in sorted(expected):
        target = dst / rel
        _mkdir(target)
        shutil.copyfile(src / rel, target)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Export deterministic game-ready VetroMania assets.")
    parser.add_argument("--out", type=Path, default=ROOT / "game" / "assets")
    parser.add_argument("--check", action="store_true", help="fail if regenerated output differs from --out")
    args = parser.parse_args(argv)

    with tempfile.TemporaryDirectory(prefix="vm_export_") as temp_dir:
        temp_out = Path(temp_dir)
        manifest = _build_manifest(temp_out)
        files = _generated_files(temp_out)
        if args.check:
            diffs = _compare_trees(temp_out, args.out)
            if diffs:
                print("asset check failed:")
                for diff in diffs[:50]:
                    print(f"  {diff}")
                if len(diffs) > 50:
                    print(f"  ... {len(diffs) - 50} more")
                return 1
            print(f"check passed: {len(files)} files match {args.out}")
            return 0

        args.out.mkdir(parents=True, exist_ok=True)
        _sync_tree(temp_out, args.out)
        print(
            f"exported {len(files)} files, {len(manifest['sprites'])} sprite sheets, "
            f"{len(manifest['tiles']['index'])} tiles, {len(manifest['items']['icons']['index'])} icons "
            f"to {args.out}"
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
