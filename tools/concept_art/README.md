# Concept-art toolkit

Every image under [`assets/concept/`](../../assets/concept) is rendered
procedurally by the Python scripts in this folder, from shaded geometric
primitives at native resolution. Nothing is hand-painted or produced by an
image-generation model, so the output is crisp pixel art and anyone can
regenerate it byte for byte.

These are **concept assets**: they lock in scale, palette, readability, and
tone for the production artists. They are not final game art. See
[`docs/art/art-direction.md`](../../docs/art/art-direction.md) for the rules the
final art must follow.

## Regenerate

Requires Python 3.12 or later (tested with 3.13).

```sh
python -m venv .venv
# Windows: .venv\Scripts\activate    macOS/Linux: source .venv/bin/activate
python -m pip install -r tools/concept_art/requirements.txt
python tools/concept_art/generate.py            # writes assets/concept/
python tools/concept_art/generate.py --out /tmp/concept   # or anywhere else
```

A full render takes about 4 seconds. Every random source is seeded, so with
the pinned Pillow and NumPy versions a re-run reproduces the committed files
exactly. If `git status` shows changes after a run, the art changed.

## Output

| Folder | Contents |
| --- | --- |
| `characters/` | Sleve Bonzalez: idle, run, swing, jump, and Spaceball strips, plus GIFs and a labeled 4x sheet |
| `enemies/` | Five enemy strips and GIFs, a 4x bestiary sheet, and the Ainamortev palette swaps |
| `bosses/` | HotCoffee strip, GIF, and 2x sheet, plus the COLD BREW mirror variant |
| `tiles/` | 16x16 Hull Cathedral tileset (8 columns), the gothic window prop, and a labeled 4x preview |
| `items/` | 24x24 icon atlas, the animated spaceball card, and a labeled 4x item sheet |
| `mockups/` | Gameplay, mirror planet, title, equipment, and map screens at 640x360 and 1920x1080 |
| `reference/` | Cast lineup with sprite heights, and material palette ramps |

Files without a scale suffix are native resolution with transparency; they are
what an engine would import. Files ending in `@2x`, `@3x`, or `@4x` are
nearest-neighbor previews for documentation.

## Modules

| Module | What it draws |
| --- | --- |
| `pixel.py` | The renderer: hue-shifted palette ramps, lit primitives with bevel normals, contact shadows, selective outlines, rim light, emission and bloom, a 5x7 pixel font, dithering, and export helpers |
| `characters.py` | Sleve's rig. Poses are joint angles, so every animation shares one set of parts |
| `enemies.py` | Space Bat, Astro-Zombie, Hunch-Bot, Mer-Man, and Vampress |
| `bosses.py` | HotCoffee, the evil android barista |
| `world.py` | Tiles, the gothic window, and parallax layers: nebula sky, stars, ringed planet, spires, colonnade |
| `items.py` | Gear and weapon icons, upgrade gems and gem packs, Vetro-Bucks, the spaceball card, and rarity frames |
| `ui.py` | Panels, bars, labels, counters, and the HUD minimap |
| `scenes.py` | The Hull Cathedral room, the gameplay mockup, and the flipped Ainamortev mockup |
| `screens.py` | Title, equipment, and world map screens |
| `generate.py` | Renders everything above into `assets/concept/` |

## How the renderer works

1. **Materials.** `mat()` builds a 5-step ramp around a base color. Shadows
   drift toward blue-violet and highlights toward warm yellow, the way
   hand-built pixel palettes do. `glow()` builds emissive materials that also
   feed the bloom buffer.
2. **Shapes.** Ellipses, capsules, polygons, and rounded rectangles each
   return a mask plus surface normals, so a flat shape shades like a bevelled
   solid.
3. **Lighting.** One key light from the top left. Each pixel's diffuse term is
   banded into a ramp index. Specular pixels jump to the material's highlight
   color.
4. **Contact shadows.** Where a part painted later overlaps an earlier part,
   the earlier part's pixels just below and to the right of the front part's
   edge drop one ramp step, as if in its shadow. This separates limbs the way
   a pixel artist would by hand.
5. **Outlines.** A colored outline takes each material's darkest ramp color,
   pushed toward ink. There is no pure-black outline, which keeps the
   silhouette readable without looking like 8-bit art.
6. **Scenes.** Sprites are composited onto float canvases with additive bloom.
   Backgrounds use fractal value noise quantized to a palette with 4x4 Bayer
   dithering.

## Conventions

- Angles in `characters.py` are radians measured from straight down, positive
  toward the facing direction.
- All sprites face right. Scenes mirror them with `Canvas.blit(flip=True)`.
- Mirror-planet variants are YIQ hue rotations (`scenes.hue_rotate`); the
  turns live in `generate.py` (`ENEMY_NAMES`, `BOSS_TURN`) and `scenes.mirror`.
- Keep every random generator seeded. Output must stay deterministic.
