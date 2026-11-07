# Tasks

## 1. Audio

- [ ] 1.1 Register `sounds/BackroomsHum.mp3` as the looping hum and the five `Footsteps Rug` wavs as static sounds in `src/Dependencies.lua` through the safe loader; test that a missing file yields a silent stub and the game still loads.
- [ ] 1.2 Add `src/BackroomsAudio.lua` (hum with fade, distance-based footsteps with no immediate repeats, pitch and volume variation) and constants for stride and volumes; unit test cadence per distance, no repeat in a row, and nothing playing while standing, airborne, falling or climbing.
- [ ] 1.3 Create and tear down the audio in `BackroomsState:enter`/`exit` so the hum and footsteps never play in the start screen, farm, fall transition or ending; test enter, exit and an ending run leave nothing playing, and verify by listening in a run.

## 2. Zone partition

- [ ] 2.1 In `src/LevelGen.lua`, grow connected zones by region growing over the connection graph on its own RNG stream, assign multi-cell rooms and module footprints as units, and snap boundaries to doorways; property test over 300 seeds that zones are connected, rooms and modules are single-zone, and a level has at least three zones.
- [ ] 2.2 Assign themes and lighting presets per zone with neighbours differing, and replace the per-cell theme assignment; test neighbouring zones differ, themes are constant within a zone and the same seed gives the same assignment while the layout is unchanged.
- [ ] 2.3 Emit `zones` and zone ids for boxes, fixtures, props and checkpoints in the room data and validate it in `Room.validate`; test validation errors and that old rooms without zones still build.

## 3. Zone lighting

- [ ] 3.1 Light fixtures from their zone's preset (colour, intensity, flicker mix, spacing) in `BackroomsLook`/`Room`; test fixtures in two zones get different settings.
- [ ] 3.2 Blend ambient and fog over a short distance by camera zone and boundary proximity, with the readability floor under every preset; test the blend is continuous across a boundary and screenshot-review a dark zone for visible plots, pickups and exit.
- [ ] 3.3 Update `Dressing` to select props by the zone's theme; test props follow the zone theme and exclusion zones still hold.

## 4. Room variety

- [ ] 4.1 Implement 1x2, 2x3 and L-shaped room stamps replacing the 2x2-only pass while keeping 2x2 rooms and hallways; property test that shapes stay in one region and elevation and exclude module, start and exit cells.
- [ ] 4.2 Add the crossroads atrium with a raised ceiling, long galleries and closets/alcoves; test ceiling clearance and that doors connect.
- [ ] 4.3 Add the pillared hall with clearance and exclusion rules; test player-width clearance, no pillar on plots, pickups, doorways or the exit, and include pillars in the reachability checks.
- [ ] 4.4 Run the abstract-graph and physics reachability sweeps over hundreds of seeds per level index with the new shapes; fix any failures and record seeds that exposed bugs.

## 5. Review and integration

- [ ] 5.1 Extend the backrooms screenshot script with scenes for zone transitions, each lighting preset in its zone, and each room shape; review and tune zone size, blend distance, shape weights and volumes, and record the findings.
- [ ] 5.2 Add the new tests to `tests/check_all.sh`, run it green on the real LÖVE runtime, and run a full autotest to the ending recording box count and frame cost for the largest level.

## Foundation (landed, unverified)

- Zone partition (region growing, rooms as units, theme/lighting graph colouring on its own RNG stream) and `meta.zones` / `meta.cells[i].zone` emitted in `LevelGen.build`; per-cell themes replaced by zone themes. Not yet covered by tests (2.1/2.2 still open; doorway snapping and `Room.validate` zones not done).
- Shared constants added in `src/constants.lua` (zones, shapes, audio). Nothing else implemented; no new tests written.

## Room shapes (4.1-4.3 written, UNVERIFIED; 4.4 not done)

- `LevelGen.build` step 3b stamps room1x2, room2x3, roomL, gallery (1x3/1x4), pillared (3x3, 4 pillars), atrium (plus, +ceiling) after the 2x2 pass on its own RNG stream (`seed*37+4421`); closets (`seed*41+6203`) are inset, lower-ceiling dead ends. Metadata: `meta.rooms[i].shape/pillars`, `meta.cells[i].shape`, `meta.pillars`, `meta.shapeCounts`. Pillars are `solid` boxes (colliders). Nothing has been run: no test, sweep or syntax check. `tests/zones_shapes.lua` is new and untested; 4.4 stays open until the full suite (incl. `tests/levels_sweep.sh`) passes on the real runtime.
