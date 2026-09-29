# Technical Architecture

[Back to the implementation plan](../implementation-plan.md)

## Engine

**Godot 4 with GDScript.** The decision is revisited at the end of Phase 0,
once the movement prototype has been profiled.

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| **Godot 4** | 2D-first tools, pixel-perfect integer scaling, source access, and no royalties | Consoles ship through third-party porting partners | **Chosen.** Engage a porting partner in Phase 0 |
| Unity 6 | Mature and well-supported on consoles | Heavier 2D workflow and licensing churn | Fallback |
| GameMaker | Excellent for 2D | Weaker data tooling for a loot game at this scale | Rejected |
| Custom C++ with SDL | Full control | Costs tools time we should spend on content | Rejected |

GDScript covers gameplay. If profiling demands it, hot spots (the loot
simulator's inner loop, say) can move to a GDExtension written in C++.

## Rendering

- **Native resolution is 640x360**, rendered in a SubViewport and
  integer-scaled to the window with nearest-neighbor filtering: 1280x720 (2x),
  1920x1080 (3x), 2560x1440 (4x), and 3840x2160 (6x). Other sizes get the
  largest integer scale and letterboxing. On Steam Deck (1280x800), that's 2x
  with 40 px bars.
- **The camera** follows in whole native pixels, with a small look-ahead and
  room-bounded clamping. No sub-pixel sprite jitter.
- **Bloom** runs on the native-resolution emission buffer, then upscales with
  the frame, so glow stays chunky and pixel-aligned. The concept toolkit's
  `Canvas.bloom` is the reference look.
- **Mirror palettes.** Area art is authored once. Ainamortev colors come from
  a per-area color lookup texture, the runtime version of the concept
  toolkit's hue rotation, so there are no duplicate sprite sheets.
- **Parallax** uses 3–5 layers per area: sky, stars, planet, spires, and
  colonnade, as in the concept backgrounds.

## Project layout

```text
VetroMania/
├── assets/concept/          procedural concept art (this repository today)
├── docs/                    design and planning documents
├── game/                    Godot project (created in Phase 0)
│   ├── autoload/            GameState, SaveService, LootService, MapService, AudioService
│   ├── actors/player/       player scene, state machine, abilities
│   ├── actors/enemies/      enemy scenes and behavior scripts
│   ├── actors/bosses/       boss scenes, phase timelines, seal finishers
│   ├── combat/              Hitbox, Hurtbox, DamagePipeline, StatusEffects
│   ├── world/rooms/a/       Planet VetroMania rooms, one scene per room
│   ├── world/rooms/b/       Ainamortev patch layers (flipped rooms are generated)
│   ├── ui/                  HUD, menus, map, equipment, tallies
│   ├── data/                .tres resources: enemies, items, affixes, perks, areas
│   └── tools/               editor plugins, loot simulator, world-graph exporter
├── tools/
│   ├── concept_art/         concept-art generator
│   ├── solver/              reachability solver (Python)
│   └── data_lint/           schema checks for exported data
└── .github/workflows/       CI
```

## Runtime architecture

- **Autoload services.** GameState (flags, abilities, seals, tallies),
  SaveService, LootService, MapService, AudioService, and Settings. Scenes
  talk to services through signals, never to each other directly.
- **World streaming.** One room is active, and its door neighbors are
  preloaded. A room transition swaps scenes in under 0.5 s behind a
  2-frame fade.
- **Player.** A `CharacterBody2D` driven by a hierarchical state machine:
  Grounded (idle, run, crouch, slide), Air (jump, fall, double jump, wall
  kick, screwball), Special (spaceball, grapple, blast, ceiling walk, swim),
  and Reactions (hurt, dead, seal finish). Abilities are components that add
  or unlock transitions, so a missing ability is simply a missing
  transition.
- **Fixed timestep.** Gameplay runs at 60 Hz in `_physics_process`, with
  input sampled once per tick. Together with seeded RNG, that makes input
  replays deterministic.
- **Combat.** `Hitbox` and `Hurtbox` areas with a team mask feed a single
  `DamagePipeline`: base ATK, move multiplier, DEF, element, crit, status
  application, then hit-stop and damage numbers. The formulas are in
  [Player and combat](../design/player-and-combat.md#damage-model).
- **Enemies** are data-driven: an `EnemyDef` names a behavior script (for
  example, sine-flyer, lunger, hopper, or turret) plus tuning values. Bosses
  use phase timelines with explicit telegraph windows, so the "at least 12
  frames of wind-up" rule can be checked.

## Data model

Content is authored as Godot resources (`.tres`) in `game/data/`, and
exported to JSON for the Python tools. CI validates both.

| Resource | Key fields |
| --- | --- |
| `AreaDef` | Code, name, map color, level range, music, palette lookup, hub-scaling flag |
| `RoomDef` | Area, cell rectangle(s), doors (cell edge and direction), regions and internal gates, spawn list, pickups |
| `EnemyDef` | ID, tier, HP base, attacks, weaknesses and resistances, behavior script, tally threshold, perk ID, drop table, `mirror_of` |
| `BossDef` | ID, level, HP multiplier, phases, seal required, first-kill drops |
| `BaseItemDef` | Slot or weapon class, tier, variant, slot or class weight, level range, icon |
| `AffixDef` | Prefix or suffix, exclusivity group, allowed slots, tier level thresholds, value ranges, weight, `grants_traversal` (must be false) |
| `LegendaryDef` / `SetDef` | Base, fixed affixes, power script; set pieces and bonus thresholds |
| `PerkDef` | Trait or Knack, stat modifiers or power script, EX upgrade |
| `DropTableDef` | Weights for nothing, currency, consumable, gear, and gem pack; rarity weights |

Invariants are enforced by the data linter:

- No affix, perk, or legendary may set `grants_traversal`.
- Every enemy has a perk, and every perk has an EX version.
- Every boss lists a seal that the solver can prove is reachable first.

## Loot generator and simulator

**Generation**, in `LootService`, happens in fixed steps, each using its own
seeded RNG stream. The seed combines the save seed, the room, the spawn, and
the kill counter, so any drop can be replayed from a bug report.

1. Roll the drop category from the source's `DropTableDef`.
2. For gear, pick the slot. If the player is below Lv 20, a ring result
   becomes armor.
3. Pick a base item for the item level and slot.
4. Roll rarity. Apply Loot Luck with diminishing returns, then apply
   bad-luck protection. A common ring is promoted to magic.
5. Roll affixes from the pools filtered by slot, item level, and exclusivity
   group, then roll values within each affix tier's range.
6. Build the name. A rare takes its top prefix and top suffix.
7. Mark legendary and set items unidentified.

**The simulator** (`game/tools/loot_sim.gd`) runs the real `LootService` in
headless Godot. It never reimplements it, so the two can't drift. It plays
scripted kill schedules for each milestone (for example, "Normal, thorough,
end of Planet VetroMania") and checks:

- The [target outcomes](../design/progression-and-loot.md#target-outcomes) for
  drops, rarities, legendaries, set pieces, and gems, within ±15%.
- Invariants over a million rolls: no ring below Lv 20, no duplicate
  exclusivity groups, no traversal affixes, and upgrade caps respected.
- **Time-to-kill** for each boss using simulated on-level gear. On Normal it
  must fall within the 60–150 second window, which catches loot that
  trivializes bosses.

## Map system

- Each planet has a discovery bitset of its cells. A cell is marked when
  Sleve's center enters it.
- The percentage is visited cells divided by total cells for each planet,
  plus 0.1% for each Minus World cell, **truncated** to one decimal place.
- The minimap draws the 9 x 6 cells around Sleve from the same data. Map pins,
  save, warp, boss, and secret markers are overlays.

## The Flip pipeline

Ainamortev rooms are **generated, then patched**. Hand edits live only in the
patches.

1. For each Planet VetroMania room, a build step writes an Ainamortev room.
   It flips the tile layers vertically, using a tile-mapping table for tiles
   that aren't symmetric (a floor edge becomes a ceiling edge). It also
   mirrors entity positions, swaps up and down doors, flips the room's cell
   rectangle (`y` becomes `H - 1 - y`), and strips planet-specific entities.
2. The room's **patch layer** (`world/rooms/b/<room>.patch.tscn`) adds and
   removes tiles, platforms, gates, secrets, and spawns.
3. The palette lookup and Ainamortev spawn tables are applied.
4. The reachability solver validates the combined world graph.

Regenerating is cheap and deterministic. A change to a Planet VetroMania room
flows into its twin automatically, and the solver flags any patch that no
longer fits.

## Reachability solver

A Python tool in `tools/solver/`. It reads `world_graph.json`, which an
editor plugin exports from the room data.

- **Graph.** Nodes are room regions. Edges are traversals, each with a
  requirement expression over abilities, seals, and flags, such as
  `JETPACK or (WALL_KICK and SPACEBALL)`. One-way edges are marked. Pickups
  sit on nodes. A boss node needs its seal to finish, and without it the
  arena is exitable but the boss isn't beaten.
- **Algorithm.** Expand the reachable set from the start to a fixed point,
  collecting every pickup reached, then repeat until nothing changes. Run the
  whole search for both planets.
- **Checks** (any failure blocks the merge):
  1. **Completable.** Both endings, COLD BREW, and the secret boss can be
     reached and finished.
  2. **No softlocks.** Every reachable node can get back to a save pod with
     the abilities held at that point.
  3. **Intended breaks.** Each listed sequence break (see
     [World and map](../design/world-and-map.md#intended-sequence-breaks))
     still reaches a completable state. Any break that isn't listed is
     reported for triage.
  4. **Perk independence.** No edge mentions a perk, legendary, or affix.
  5. **200.6% is possible.** Every cell, including the six Minus World cells,
     is reachable.
- **Output.** A text report, plus a PNG map overlay that highlights
  unreachable cells in red. The overlay uses the concept toolkit's map
  renderer.

## Save system

- **Format.** Versioned JSON (`"schema": N`). Each schema bump ships a
  migration function from N-1 to N, and CI loads a fixture save from every
  earlier schema.
- **Contents:**
  - Player: level, XP, and Montage allocations.
  - Inventory and equipment. Each item stores its base ID, item level,
    rarity, rolled affix values, upgrade level, and seed.
  - Abilities, seals, and story and boss flags.
  - Tally counts, per-planet discovery bitsets, and opened chests.
  - Loot pity counters and RNG stream state.
  - Play time, difficulty, and language mode.

  Settings are stored separately, per machine.
- **Slots.** Three manual slots, plus an autosave made on entering each area.
  Iron Mullet uses a single slot that is deleted on death.
- **Safety.** Writes are atomic (write a temporary file, then rename). The
  last 3 versions of each slot are kept.

## Content pipeline

| Content | Authoring tool | Into the game |
| --- | --- | --- |
| Sprites and animation | Aseprite, with one file per character and tagged animations | Aseprite command-line export to sheets plus JSON, then an import plugin that builds `SpriteFrames` with pivots and hitbox markers |
| Palettes | `.gpl` palette files for each area and character | Linted: every sprite pixel must be in its palette |
| Tiles and rooms | Godot `TileMapLayer` scenes, with a world-map editor dock showing the cell grid | Native. LDtk is evaluated in Phase 0 week 2; the decision is made by the end of Phase 0 |
| Items, enemies, and perks | Godot resources, with spreadsheet import for bulk tuning | Native, plus JSON export for the tools |
| Audio | DAW stems (area tracks are layered for boss phases) | Godot audio buses; adaptive layers are driven by game state |
| Concept art | [`tools/concept_art/`](../../tools/concept_art) | Reference only; never shipped |

## Continuous integration

GitHub Actions runs on every pull request:

1. `gdlint` and `gdformat --check` on the GDScript.
2. Unit tests (GdUnit4) in headless Godot.
3. Data linting, covering both the resources and the exported JSON.
4. The reachability solver, on both planets.
5. The loot simulator in short mode (100,000 rolls per profile). The full run
   happens nightly.
6. Export smoke builds for Windows and Linux.
7. A concept-art determinism check: regenerate `assets/concept/` and fail if
   `git diff` isn't empty.

## Testing strategy

| Layer | What | How |
| --- | --- | --- |
| Unit | Damage, stat growth, the XP curve, upgrade caps, ring gating, save migrations | GdUnit4 |
| Property | Loot invariants over a million seeded rolls | Headless loot simulator |
| Replay | Movement feel and regressions: jump height must stay 56 ±1 px, and dash distances must hold | Recorded inputs replayed on the fixed timestep |
| World | Completability, softlocks, and 200.6% | Reachability solver |
| Balance | Drop targets and boss time-to-kill | Loot simulator |
| Performance | Frame time on the weakest supported device | Weekly Steam Deck captures |
| Humans | Fun, funny, and cringe | Milestone playtests with a standard survey |

## Performance targets

- A locked **60 fps** on Steam Deck: CPU under 8 ms and GPU under 6 ms per
  frame.
- Under 1.5 GB of memory.
- Room transitions under 0.5 s, and area loads under 1.5 s.
- Input-to-screen latency of 3 frames or less, with vsync on.

## Localization

- All strings live in CSV tables through Godot's translation server. The
  pixel font gets extended Latin glyphs at launch.
- **EFIGS** at launch (English, French, Italian, German, and Spanish). UI
  allows 30% extra length.
- Every pun and reference carries a localization note with its intent and a
  pointer to the [reference ledger](../design/reference-ledger.md).
  Translators may swap in a local equivalent.

## Telemetry

Telemetry is opt-in and in playtest builds only. It records deaths (room
and cause), time per area, the map percentage over time, drops, and
upgrades. It collects no personal data, and it's removed from release
builds.
