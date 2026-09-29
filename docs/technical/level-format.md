# Level Format

[Back to the implementation plan](../implementation-plan.md)

The playable slice is a set of **rooms**. Each room is one JSON file in
[`game/data/rooms/`](../../game/data/rooms) with its tiles drawn as ASCII, so
a level diff reads like a map diff. `game/core/level.gd` loads the files (one
that isn't valid JSON is reported and skipped), and
[`tools/level_tools.py`](../../tools/level_tools.py) validates, lints and
previews them without starting the engine. CI runs the linter.

## The grid

All rooms share **one global tile grid**. A **cell** is 40 x 23 tiles of
16 px (640 x 368 px), the same cell the [map](../design/world-and-map.md#map-grid)
screen counts. A room covers a rectangle of whole cells, so there are no door
transitions: walking across a cell edge simply continues into the next room's
tiles, and the camera clamps to the room you are in.

```json
{
  "id": "crash_3", "area": "crash", "cell": [2, 1], "size": [1, 1],
  "title": "CRASH SITE Z-0: CONDUIT YARD",
  "tiles": ["BBBB...", "... one string per row, 23 x size.y rows ..."],
  "entities": [
    {"type": "npc", "at": [8, 19], "name": "Darryl Archideld"},
    {"type": "enemy", "at": [22, 8], "id": "space_bat", "count": 2}
  ]
}
```

| Key | Meaning |
| --- | --- |
| `id` | Unique room ID. Saves, pickups and gates key off it, so never rename one after release |
| `area` | A key of `areas` in [`areas.json`](../../game/data/areas.json): it picks the tileset, background, music and enemy levels |
| `cell` | Top-left cell of the room on the global grid: `[column, row]` |
| `size` | Width and height in cells. Defaults to `[1, 1]` |
| `title` | Shown on the area banner when the player first enters |
| `tiles` | `size.y * 23` strings of exactly `size.x * 40` characters |
| `entities` | Things placed in the room (below) |

## Tiles

| Char | Tile | Notes |
| --- | --- | --- |
| `.` | Empty | |
| `#` | Ground | Draws as a floor top when open above, and as fill when covered |
| `B` | Brick | Solid wall and ceiling |
| `Z` | Hazard block | Solid, striped, decorative |
| `=` | One-way platform | Jump up through it, and drop through with Down + Jump |
| `^` | Spikes | Hurt on touch. Not solid |
| `%` | Hollow wall | Looks like brick, and breaks on the **third** hit. Hides a secret |
| `X` | Crate bulkhead | Breaks on a hit from the Beam Bat. Blocks the way until then |
| `T` | Mitt target | A bullseye. A fully charged Mitt Cannon shot lights it |
| `C` | Conduit shutter | Opens for good when a target in the same room is lit |

Decoration tiles are not solid and only paint the back layer: `w` back wall,
`-` and `|` pipes, `g` grate, `L` light panel, `v` vine, `P` pillar, `b` brick
backdrop.

A room needs **both** a `T` and a `C`, or neither. The space outside every
room is solid.

## Entities

`at` is `[column, row]` in the room's own tiles. For anything that stands, it
is the tile the **feet** are in, so the tile below must be solid or a
one-way platform. Orbs and flying enemies hover, so give them the row above
the standing row.

| `type` | Fields | What it does |
| --- | --- | --- |
| `spawn` | `id` | Where the player appears. The `start` spawn is required and unique |
| `enemy` | `id`, `count`, `level`, `elite` | Spawns from `enemies.json`. `count` fans a group out. `level` overrides the area's level. `elite` forces or forbids an elite |
| `boss` | `id` | The one boss. The fight starts when the player walks past the boss door |
| `save_pod` | | Saves, heals, and opens the upgrade bench, and it sets the respawn point |
| `vending` | | The vending machine that grants the Beam Bat |
| `statue` | | The Koozie Statue that grants the Spaceball |
| `table` | | The signing table that grants Autograph Seal 1 |
| `npc` | `name` | A hologram. The name must be in [`roster.json`](../../game/data/roster.json), which also holds the lines |
| `chest` | `level`, `secret` | Rolls the chest drop table at `level` (default 5), which is always rare or better. A `secret` chest stays hidden while a `%` wall stands in its room |
| `orb` | `ability`, `item`, `line` | Grants an ability on touch, and optionally an item and a line of dialogue |
| `door` | `open` | The boss door. There is at most one. It closes behind the player when the fight starts and reopens when the fight ends |
| `warp` | | A warp pipe. It opens the warp menu, which lists the pipes the player has visited |
| `hint` | `size`, `text` | A trigger box `size` tiles wide, centred on `at`, and as tall going up from the feet tile. It shows `text` while the player is inside |

## Rules the linter enforces

`python tools/level_tools.py lint` exits with 1 and prints one line per
problem:

- Row counts and widths match the room's `size`, and every tile is in the
  legend.
- The `area` exists. Every enemy, boss and orb ability exists in the data, and
  every NPC is a roster name with dialogue.
- Standing entities are not inside a solid tile and have ground under them.
  Ground enemies (anything that is not flagged `flying`) follow the same
  rule, and flying enemies and orbs must not start inside a solid.
- There is exactly one `start` spawn and one boss, and at most one door.
- A seam between two rooms is open on both sides or hard on both sides. A
  hard tile against an open one is a broken doorway. Gates are exempt.
- Targets and shutters come in pairs.

## Authoring constraints

The physics numbers in [Player and combat](../design/player-and-combat.md) set
the geometry:

- The player is 18 x 56 px, so passages need to be **4 tiles high**. Crouching
  and sliding need 40 px, and the Spaceball needs 24 px, so its tunnels are 2
  tiles high.
- A jump climbs 56 px, so steps are at most **3 tiles** and gaps at most **4
  tiles**. The Jetpack adds 40 px.
- A 5-tile seam passage leaves only 48 px of headroom over a 2-tile block, so
  keep obstacles at least 4 tiles away from one.

## Previews and proof

```sh
python tools/level_tools.py preview --room crash_1            # one room at 1x -> tmp/level_preview/crash_1.png
python tools/level_tools.py preview --map                     # every room, scaled down
python tools/level_tools.py preview --room hull_nave --no-markers
```

The preview draws real tiles and boxes the entities, so it is the quickest way
to review a layout in a pull request.

Lint proves a level is well formed. It doesn't prove it can be **finished**.
For that, `game/tests/test_route.gd` and `test_secrets.gd` play the real level
with real physics: a bot walks, jumps, wall-kicks and swings through every
step of the critical path, and each secret is checked both ways. It is
reachable with its ability, and not without it.
