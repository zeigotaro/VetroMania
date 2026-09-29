# Game asset exporter

`export.py` turns the procedural concept-art toolkit into deterministic, engine-ready assets under `game/assets/`.

## Run

From the repository root:

```sh
python tools/game_assets/export.py
python tools/game_assets/export.py --out game/assets
python tools/game_assets/export.py --check
```

The exporter imports `tools/concept_art` by adding that folder to `sys.path`, regenerates every asset into a temporary directory, and then either:

- copies the generated files into `--out`, or
- compares the temporary output against `--out` and exits with code 1 on any difference (`--check`). PNGs are compared by their decoded pixels, so a different zlib build (Windows and Linux Pillow wheels differ) doesn't fail the check. Everything else is compared byte for byte.

Outputs are deterministic with the pinned Pillow and NumPy versions from `tools/concept_art/requirements.txt`, and CI runs `--check` on Linux.

## Output

| Path | Contents |
| --- | --- |
| `sprites/sleve/*.png` | Full-canvas horizontal sheets for Sleve's moves and the 26x26 Spaceball sheet |
| `sprites/enemies/*.png` | Union-cropped enemy sheets plus `_mirror` palette swaps |
| `sprites/bosses/*.png` | HotCoffee, COLD BREW, and one sheet per KRATE animation state |
| `sprites/props/*.png` | Props, pickups, projectiles, and effects |
| `tiles/*.png` | Hull, Crash Site, and Outer Hull atlases, 8 columns wide |
| `backgrounds/*.png` | 1280x360 parallax layers (`_far`, `_mid`, `_near`) for `crash`, `hull`, and `outer` |
| `items/*.png` | 24x24 icon atlas, 28x28 rarity frames, and the 24x32 Spaceball card strip |
| `ui/font/*` | `vetro5x7.png` plus a BMFont text-format `vetro5x7.fnt` |
| `ui/title_bg.png` | The title screen without the PRESS START prompt |
| `manifest.json` | Runtime metadata for sprites, tiles, items, backgrounds, and UI |

## Sprite sheet sizes and pivots

| Group | Sheets | Frame size | Pivot |
| --- | --- | --- | --- |
| `sleve` | `idle`, `run`, `swing`, `jump`, `slide`, `backdash`, `hurt`, `wall_slide` | `96x100` | `(38, idle_ground)` where `idle_ground` is the bottom-most opaque row of `idle[0]` plus one |
| `sleve/spaceball` | `spaceball` | `26x26` | bottom center |
| `enemies` | `space_bat`, `astro_zombie`, `hunch_bot`, `mer_man`, `vampress`, plus `_mirror` sheets | union crop across frames, +1 px margin | center for `space_bat`; bottom center for the rest |
| `bosses` | `hot_coffee`, `cold_brew` | union crop across frames, +1 px margin | bottom center |
| `bosses` | `krate_idle`, `krate_windup`, `krate_slam`, `krate_chomp` | `144x120` | bottom center |
| `props` | `save_pod`, `door`, `vending_machine`, `koozie_statue`, `warp_pipe` | native builder canvas | bottom center |
| `props` | `nag9000`, `ability_orb`, `hit_spark`, `mitt_shot`, `mitt_shot_charged`, `enemy_bolt`, `pickup_glint` | native builder canvas | center |
| `props` | `hologram_ring` | `32x8` | bottom center |

## Manifest structure

`manifest.json` is pretty-printed, sorted, and LF-terminated. Its top-level shape is:

```json
{
  "version": 1,
  "sprites": {
    "group/name": {
      "file": "sprites/group/name.png",
      "frames": 2,
      "frame_size": [32, 48],
      "pivot": [16, 48],
      "bbox": [3, 2, 29, 47],
      "fps": 6.0,
      "loop": true
    }
  },
  "tiles": {
    "atlases": { "hull": "tiles/hull.png", "crash": "tiles/crash.png", "outer": "tiles/outer.png" },
    "tile_size": 16,
    "columns": 8,
    "index": { "floor_top": [0, 0] }
  },
  "items": {
    "icons": { "file": "items/icons.png", "icon_size": 24, "columns": 8, "index": { "helm": [0, 0] } },
    "rarity_frames": { "file": "items/rarity_frames.png", "size": 28, "order": ["common", "magic"] },
    "spaceball_card": { "file": "items/spaceball_card.png", "frames": 6, "frame_size": [24, 32] }
  },
  "backgrounds": { "hull": { "far": "backgrounds/hull_far.png", "mid": "backgrounds/hull_mid.png", "near": "backgrounds/hull_near.png" } },
  "ui": { "font": "ui/font/vetro5x7.fnt", "title_bg": "ui/title_bg.png" }
}
```

`bbox` is the tight union bounding box of opaque pixels inside one frame, in frame-local coordinates. All exported animation sheets are horizontal strips with no padding.
