# Exocraft

A sci-fi / cyberpunk sandbox inspired by Terraria, built in **Godot 4.6**. Dig
and build across an **endless, procedurally generated alien world** with multiple
biomes, mine ores, craft gear, and fight off alien crawlers and sentry drones.

All art is **pixel art generated at runtime** (see `scripts/autoload/Art.gd`) — the
project ships with zero binary image assets, so it is fully deterministic and easy
to restyle. Drop in hand-drawn PNGs later without touching gameplay code.

![Exocraft at dusk](docs/screenshot.png)
![Exocraft at night](docs/night.png)

## Running

1. Open the project folder in Godot 4.6 (`Import` → select `project.godot`).
2. Press **F5** (Play).

Or from the command line:

```bash
godot --path .
```

## Controls

| Action            | Key                              |
| ----------------- | -------------------------------- |
| Move              | `A` / `D` or `←` / `→`           |
| Jump / swim up    | `Space` / `W` / `↑`              |
| Use selected item | **Left click**                   |
| Mine / drain water| **Right click**                  |
| Select hotbar     | `1` – `0` or **mouse wheel**     |
| Inventory + craft | `E` or `Tab`                     |
| Peaceful mode     | `P` (toggle enemies on/off)      |
| Sprint            | hold `Shift`                     |
| Pause menu        | `Esc`                            |
| Fullscreen        | `F11`                            |

"Use selected item" depends on what is in the active hotbar slot:

- **Plasma Drill** (tool) – mine the tile under the cursor
- **Hydro Cell** (tool) – pour liquid into the cell under the cursor
- **Ion Blaster** (weapon) – fire an energy bolt toward the cursor
- **Kinetic Rifle** (weapon) – a real ballistic gun: hold to auto-fire fast,
  slightly-scattered tracer bullets
- **Plasma Saber** (weapon) – a lightsaber-style melee blade: click to swing a
  glowing arc that cleaves every creature in front of you and slices apart
  incoming enemy bolts
- **Block** – place it under the cursor (needs an adjacent solid tile)
- **Med-Cell** (consumable) – restore health

## Features

- **Endless world** streamed in 16×16-tile chunks around the player. Edits persist
  in memory; generation is deterministic per world seed.
- **Four surface biomes** chosen by low-frequency noise — Neon Wastes, Cryo Tundra,
  Glass Dunes, Toxic Jungle — plus an underground Slate layer that turns into the
  Obsidite biome at depth, threaded with ore veins.
- **Sculpted caves**: the underground is carved by **winding worm tunnels** (the
  intersection of two noise iso-surfaces traces long connected corridors) plus
  **open caverns** that grow larger and more frequent with depth — so digging
  down opens into real explorable chambers, not random blobs. Caves are dressed
  with **bioluminescent flora**: glowing mushrooms and magenta crystal clusters
  (each casts a soft light), stalagmites, stalactites and rocks.
- **Per-biome surface life**: harvestable **alien trees**, each **procedurally
  unique** (curved, tapering, bark-textured trunks that lean and branch, with
  randomized canopies — glowing neon, crystalline ice, glass succulents, toxic
  spore-trees) that drop wood when cut with the particle gun, plus **non-solid
  decorations** (biome grass tufts,
  rocks, flowers, mushrooms) the player walks straight through. Harvested trees
  stay gone; everything else regenerates with the chunk.
- **Ores**: Ferralite (metal), Vyrite (crystal), Ion ore (energy, glowing) and
  deep Exotic veins — each embedded as **visible faceted crystals** in the stone
  so you can spot a vein at a glance, and dropped **only** by its own ore block.
  Ore **improves with depth** (Ferralite near the surface → Vyrite → Ion →
  Exotic in the depths) but also grows **rarer** the deeper you dig, so deep
  mining is higher-risk, higher-reward.
- **Mining & building** with reach limits, hardness-based dig times, placement
  support checks, and item drops that fall and magnetise to the player. You can
  only mine **exposed** blocks (one block deep at a time), so no reaching through
  solid rock.
- **Physics-based liquid** (Terraria-style cellular-automaton water): each cell
  holds a fill level that **flows down into open space and spreads sideways**
  toward a flat surface, so it pools in basins, pours through gaps and cascades
  down shafts, rendered as **transparent** cyan (drawn in front of the player so
  you look submerged) with a bright surface line only along the top. Still
  pools cost nothing (settled cells drop out of the sim) and only liquid within
  range of the player simulates. **Natural springs** seed pools in cave pockets.
  Craft a **Hydro Cell** to pour liquid anywhere, and **drain it back** by aiming
  the particle gun at a water cell. Placing a block in liquid **displaces** it
  into neighbouring cells; mining a wall lets a pool flood through. The player
  is **buoyant** while submerged — slowed and sinking gently, hold **Jump** to
  swim upward.
- **Particle-gun mining**: a beam from the gun dissolves the target block
  pixel-by-pixel as you mine, and the dissolved bits stream back into the gun as
  glowing particles, with a light at the impact point. The gun has a flickering
  muzzle flash and the player kicks back from the recoil (a steady shudder while
  mining, a sharp kick when firing the blaster, each with its own flash).
- **Data-driven crafting & economy**: the *engine* is in code, all *content* is
  in editable `.tres` assets under `res://data/` — add or rebalance items and
  recipes in the inspector with **no code changes**.
  - `Item` / `Recipe` / `RecipeInput` are `Resource` classes (`scripts/items/`).
  - `ItemDB` scans `res://data/items` + `res://data/recipes` at startup, exposes
    lookups + crafting rules, and runs a **validation pass** (flags orphan items
    that are never an input/end-item, and balance smells where a recipe needs an
    input of a *higher* tier than its output).
  - A tiered tree (tier 0→3): raw drops → refined → components → gear, gated by
    **stations** (Workbench → Fabricator → Synthesizer) and **unlock conditions**
    (`tier>=N`, `crafted:<id>`). Costs/values rise with tier, and the fabricator
    lists recipes **sorted by tier** so it reads as a progression.
  - **Building set** — craft structures from the materials that make sense:
    **walls** (Slate Brick, Metal Wall, Obsidite Brick, plus Bio-Timber / Hull
    Plating / Neon Glass), **windows** (Glass + Reinforced — solid but
    transparent, so light passes through them), and **functional doors** (Timber,
    Metal, Blast). Doors are **two tiles tall** and **open/close when you click
    them** (an open door is a passable doorway you can walk through; a closed one
    is a solid, light-blocking wall). They're built from **sub-parts** — a Hinge
    and a Metal Frame — that the recipes require.
  - **Upgraded particle guns** that harvest faster: Particle Gun (1×) → **Pulse
    Drill** (1.8×) → Plasma Cutter (3×) → **Singularity Bore** (4.5×), each a
    real jump in mining speed against tougher blocks.
  - The fabricator is a **Minecraft-style recipe grid** of output icons; hovering
    a cell shows the name, ingredients (have/need) and status. Three states are
    read at a glance from the icon — **craftable** (bright, clickable), **available**
    (faded, missing materials) and **locked** (dark, with the reason in the tip) —
    so the locked→craftable transition is the reward loop.
  - **Deployable stations**: craft a **Workbench**, **Fabricator** or
    **Synthesizer** and place it in the world (it builds up from a seed-pod with
    an animation); you must stand near the right station to craft its recipes.
    **Aim the particle gun at a station/pod to dismantle it** and recover the
    item (a pod returns its contents too).
  - **Storage pods**: deploy containers (press `F` near one to open it,
    click to move stacks in/out). Stations **synthesize using items in nearby
    storage pods** as well as your inventory.
  - 40-slot cargo, 10-slot hotbar, scrollable fabricator. Re-author content with
    `godot --headless --script res://tools/generate_data.gd`.
- **Alien fauna** (data-driven `Creature` system, two AI modes):
  - **Passive** animals wander and flee when hurt — biome-tinted **Grazers**,
    skittish **Hoppers**, and drifting **Floaters** (drop biomass / energy).
  - **Territorial** animals roam but only attack once you enter their range —
    **Crawlers**, night **Stalkers**, ranged **Spitters**, and flying **Drones**
    (drop scrap / ores). Peaceful mode (`P`) clears these but leaves the passive
    animals roaming.
  - Spawned in a ring just off-screen up to a cap; you can hunt any of them.
- **Two factions** sharing the world, with their own turf and AI:
  - **Corp** — a high-tech corporate robot army that **garrisons fixed surface
    bases**, each **built out of real in-world blocks** (Hull Plating walls and
    Neon Glass-lit windows around a control tower and antenna beacon, on
    foundation pillars that follow the ground) — so a base is part of the terrain
    and **can be mined**. Bases sit at deterministic, spaced-out sites and
    reinforce a **patrol of robots and
    drones** — melee bruisers, ranged sentries and flying attack drones — that
    **hold the ground around their base and only give chase if you come close**,
    breaking off to return home if you lead them too far. They don't dig. Drop
    scrap, ingots and components. Peaceful mode (`P`) stands them down.
  - **The Kin** — an underground alien race that lives in the caves and **mines
    the rock** (slowly carving the stone around them, never your ores). They
    **never strike first**: spend peaceful time near them and their **trust grows
    until they turn allied for good** (a HUD readout tracks it) — but **attack one
    and they fight back and remember the betrayal**. Drop crystal, biomass and the
    occasional exotic matter.
- **Animated player**: idle breathing bob, a 4-frame run cycle, and jump / fall
  poses, all built from runtime-generated frames driven by an `AnimatedSprite2D`.
- **Animated fauna**: every creature has runtime-generated frames too — walk
  cycles for the legged animals, a hop for hoppers, swaying tentacles for
  floaters, and a scanning eye/thrusters for drones.
- **Combat**: ranged energy bolts + ballistic bullets, a melee saber that cleaves
  and deflects bolts, player health, invuln frames, death + respawn.
- **Hunger & food**: a hunger bar that drains over time (faster while sprinting);
  staying fed lets health regenerate, while an empty stomach starves you (down to
  a floor). Eat craftable food — **Protein Ration** and **Nutrient Stew** (which
  also heals) — to refill it.
- **Peaceful mode**: press `P` to toggle enemy spawning off (and clear current
  enemies) for relaxed building.
- **Settings menu** (pause → Settings): graphics (fullscreen, VSync, window
  size, anti-aliasing, bloom, scanlines), audio (master / music / SFX volume,
  music on/off), and **rebindable controls**, plus a **Reset to Default** —
  persisted to `user://settings.cfg`.
- **Procedural SFX**: short blips (mine, shoot, craft, deploy, hit, pickup)
  synthesised into clips at startup (no audio files) on their own SFX bus.
- **Quality-of-life**: a pause menu (`Esc`), out-of-combat health regeneration,
  `Shift` to sprint, an `F11` fullscreen toggle, `M` music toggle, a held-item
  name label above the hotbar, hover tooltips in the cargo grid, and a
  low-health red vignette.
- **Procedural 16-bit music**: an atmospheric chiptune (chord pad + triangle
  bass + soft square arpeggio) synthesised live with an `AudioStreamGenerator`
  through a reverb/low-pass bus — no audio files. The progression shifts between
  a brighter day set and a moodier night set. Toggle with `M`.
- **Fog of war**: a corner **minimap** and a toggleable **fullscreen map** (`M`)
  that reveal as you explore (unexplored areas stay dark), with biome-coloured
  terrain, a player marker and deployed station/pod markers — plus an in-world
  **black fog** that hides unexplored underground (above ground stays clear).
  The fog **fades softly** at its edges (graded opacity levels) rather than a hard
  cut, both at the explored frontier and as it fades in below the surface.
- **Responsive UI**: a fully anchored HUD that lays out correctly on any
  resolution / aspect ratio (1080p, 1440p, 4K, ultrawide), with a large
  zoomed-in view and chunky pixel UI.
- **Day/night cycle + dynamic lighting** (high-end):
  - A timed sun and moon arc across a **shader sky** that transitions
    dawn → day → dusk → night, with a cyberpunk-magenta twilight glow and stars
    that fade in at night. **Nights are genuinely dark** — bring a light.
  - A `CanvasModulate` ambient floor plus `DirectionalLight2D` sun/moon that
    **cast real shadows** off the terrain — surfaces are sunlit while caves stay
    dark.
  - Streamed **point lights**: a **toggleable torch** (`T`) — a warm,
    shadow-casting glow ~4 blocks across that softly fades out — glowing ore /
    neon blocks (lit per chunk near the player), blaster bolts and drone eyes.
  - Neon **bloom** via a `WorldEnvironment` + HDR 2D (Forward+/Mobile).
- **Dynamic weather** (`Weather.gd`): a clear → cloudy → storm state machine.
  Drifting, wind-blown **clouds** that thicken and darken as a storm builds,
  **rain** (particles, shown only while you're near the surface), and alien
  **green lightning** — a jagged bolt + double-flicker screen flash + thunder.
  The current weather shows in the HUD clock readout.

## Project layout

```
project.godot              Autoloads, input defaults, pixel-perfect render settings
scenes/Main.tscn           Tiny root scene; everything else is built in code
scripts/
  Main.gd                  Bootstraps world, player, spawner, HUD, parallax bg
  autoload/
    Tiles.gd               Tile id registry: visuals + material data
    ItemDB.gd              Item definitions + crafting recipes
    Art.gd                 Runtime pixel-art: tile atlas/TileSet, sprites, icons
    Game.gd                Global refs, signals, health, input map setup
  world/
    World.gd               Endless chunk streaming + procedural generation + block lights
    EnemySpawner.gd        Off-screen ring spawner (respects peaceful mode)
    DayNight.gd            Time of day, sun/moon lights + shadows, shader sky
  player/Player.gd         Movement, mine/build/shoot, reach, drops
  entities/                Projectile, ItemPickup, Crawler, Drone
  inventory/Inventory.gd   Slot/stack model + crafting
  ui/HUD.gd                Health, hotbar, inventory grid, fabricator
```

## Extending

- **New tile**: add an id + entry in `Tiles.gd` `DEFS`; `Art.gd` draws it and the
  TileSet picks it up automatically.
- **New item / recipe**: add to `ItemDB.ITEMS` / `ItemDB.RECIPES`.
- **New biome**: extend the `biome_at()` bands and `_surface_tile()` /
  `_soil_tile()` in `World.gd`.
- **New enemy**: copy `Crawler.gd`, add it to the `"enemies"` group, and spawn it
  from `EnemySpawner.gd`.
- **Tune lighting / day length**: the constants at the top of `DayNight.gd`
  (`DAY_LENGTH`, ambient/sky palette, `SUN_MAX`, `SUN_SHADOWS`). Glowing block
  light colours live in `Tiles.gd` (`light` / `light_energy`).

## Tech notes

- Tiles are data in `World.chunks` (chunk-coord → `PackedInt32Array`); a single
  `TileMapLayer` is used purely for rendering + collision and is streamed.
- `Game.world` / `Game.player` are intentionally untyped to avoid a GDScript
  autoload⇄class parse cycle; call sites annotate their own locals.
