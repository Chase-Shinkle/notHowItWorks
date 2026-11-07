# Design

## Context

Observed in the code: `LevelGen.build` assigns a material theme per cell from a `themeRng` stream (`src/LevelGen.lua`, section "boxes"), and floors and ceilings are merged by `kind|theme|z|bounds`, so any two neighbouring cells can differ. Lighting is one preset per level, picked in `BackroomsLook` from the room id (`BACKROOMS_LIGHTING_BY_ROOM_ID`, `BACKROOMS_LIGHTING_DEFAULT_POOL`), and the shader gets one ambient and fog uniform set. Rooms are only connected 2x2 blocks of one region (`LEVELGEN_ROOM_CHANCE`); other cells are corridors with an optional narrow inset. `PlayerController` exposes `grounded` and `climbing`. `Dependencies.lua` registers the hum as `sounds/backrooms_hum.ogg`, but the file added is `sounds/BackroomsHum.mp3` (so it loads as a silent stub); there is no footstep sound. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Areas that read as places: consistent materials and lighting within a zone, differing between zones.
- More room shapes without touching obstacle modules or solvability.
- Footsteps and hum wired, scoped to the backrooms.

**Non-Goals:**
- New art, music, changing seeds' meaning or the maze carve, a minimap.

## Decisions

1. **Zones are a partition of the cell graph, assigned after the layout is final.** After obstacles, rooms and loops are fixed, grow K zones by multi-source region growing over the connection graph (frontier expansion from K seed cells), so each zone is connected by construction. K scales with cell count (about one zone per 8-12 cells, at least 3). A multi-cell room is assigned as one unit so a room never straddles zones. Run on its own RNG stream (derived from the level seed), so layout and solvability are unchanged for a given seed. Alternative: per-region zones (using `c.region`), rejected because regions come from obstacles and would give very uneven zone counts.
2. **Prefer boundaries at thresholds.** Frontier expansion treats doorway edges as cheaper boundaries than 'open' edges inside rooms and hall runs; a post-pass moves a boundary to the nearest doorway if it would cut an open edge. Zone boundaries also snap to obstacle-module edges, so a module and its plot keep a single theme.
3. **Zone data drives themes and lighting.** Each zone gets `{id, theme, lighting, landmark}`; neighbours must differ in theme and in lighting preset (graph colouring over the zone adjacency with the theme/lighting pools). Boxes carry the zone's theme, so existing floor/ceiling merging by theme merges naturally within a zone. Alternative: keep per-cell themes but smooth them, rejected because it cannot guarantee a whole volume is uniform.
4. **Per-zone lighting data.** The room data gets `zones` and each cell/box/fixture a zone id. Fixture colour, intensity, flicker mix and `litEvery` come from the zone's preset; fixtures are therefore already right when seen from another zone. Ambient and fog are global shader uniforms, so they follow the **camera's** zone, blended over a short distance (~2.5 m) as the camera approaches a boundary using a camera-zone weight, avoiding a pop. Alternative: bake ambient into vertex colour per zone, which would handle the "seen from far" case exactly but needs mesh rebuilds and loses preset tuning; recorded as a fallback if the blend looks wrong.
5. **Gameplay readability stays global**: the ambient floor and unlit tints for plots, pickups, crops and the exit apply under every zone preset (existing `gameplayFloor`).
6. **Room shapes as cell-set stamps.** Replace the single 2x2 pass with a shape pass over the unclaimed, region-consistent cells: 1x2 and 2x3 rectangles, L (three of a 2x2), a 3x3 pillared hall (pillar boxes on the interior intersection points with 1.2 m clearance), crossroads atrium (plus shape with a raised ceiling), and long galleries (a straight run of 3+ corridor cells widened). Closets/alcoves are 1-cell dead ends with a smaller inset. Each shape declares which cells it needs, the walls it removes, and its ceiling; module, start and exit cells are excluded and shapes stay inside one region and elevation. Hallways and 2x2 rooms keep their current weights. Alternative: free-form BSP rooms, rejected for the reasons in `branching-maze-levels`.
7. **Shapes after solvability-critical decisions.** Shape stamping runs after critical modules and optional modules are placed, like the current 2x2 pass, so it can only remove interior walls inside a single region; the abstract obstacle graph is unchanged. Pillars are solid colliders and are included in the physics reachability checks.
8. **Dressing by zone.** `Dressing` picks the prop tag set from the zone theme; storytelling groupings stay in free cells. No change to exclusion zones.
9. **Audio module** (`src/BackroomsAudio.lua`): owns hum and footsteps, created in `BackroomsState:enter` and shut down in `exit`, so nothing plays elsewhere. Hum: register `sounds/BackroomsHum.mp3` as a looping stream (fix the registered path), start on enter, fade out on exit (fade handled in `update`, hard stop in `exit`). Footsteps: accumulate horizontal distance travelled while `grounded and not climbing` and not in a fall; one step per stride (about 1.7 m at walking speed, a constant) using a random pick of the five `Footsteps Rug` sources, never the same index twice in a row, with pitch ±6% and volume ±10%. Clone the static source per play so steps overlap cleanly. All loading goes through the existing safe `Assets` loader so missing files fall back to the silent stub.
10. **Volumes**: hum low, footsteps clearly above it; both are constants in `src/constants.lua`.
11. **Checkpoints and regions are untouched**; zones are visual only and do not feed solvability.

## Risks / Trade-offs

- [Zone boundaries cut a room or hall awkwardly] → Boundary snapping to doorways and whole-room assignment; property test that rooms are single-zone and zones are connected.
- [Ambient pop or wrong ambient when looking into another zone] → Distance blend, per-fixture zone colour; fallback to baked per-zone vertex colour.
- [New shapes break solvability or trap the player] → They only remove walls inside a region, pillars get clearance, the existing exhaustive graph check and physics reachability run over many seeds.
- [More boxes and colliders] → Greedy box merging by zone/theme; re-measure against the box and frame budget.
- [Footsteps annoying or desynced] → Distance-based cadence, tunable stride, variation, and volume constants.
- [Large audio memory] → Footsteps are short static sounds; the hum is a stream.
- [Conflicts with unarchived changes] → This change supersedes the per-room wording; reconcile at archive.

## Migration Plan

Additive on top of the current branch. Layout and solvability for a given seed are unchanged except where new shapes are stamped (shape stamping uses its own RNG stream so existing seeds keep their carve; recorded seeds that exposed bugs stay valid for the maze, the shapes change within regions). Rollback by setting the shape weights to zero and K = 1 zone.

## Open Questions

- Zone count and size per level index; tune from screenshots.
- Whether a rug footstep should change on ledge or bridge surfaces; start with one surface.
