# Design

## Context

`procedural-backrooms-levels` (not yet implemented) designs a generator that lays out a chain of hand-measured obstacle modules with filler between them, which plays as one long hallway. Rooms are plain data (`boxes`, `plots`, `exit`, `pickups`) built by `Room` (`src/Room.lua`); modules are measured against crop sizes (`src/Crop.lua`: beanstalk lifts 3.0 m, pumpkin fills a 1.0 m pit, vine bridges 4 m). Falling below `killZ` respawns at the level spawn. `tests/reach.lua` searches reachability over plot-to-crop assignments, which grows as 4^plots. See proposal.md for motivation and for which parts of `procedural-backrooms-levels` this supersedes.

## Goals / Non-Goals

**Goals:**
- A 2D maze with turns, junctions, loops, rooms and dead ends, still solvable by construction.
- Several plots per level, including optional and decoy obstacles.
- Cheap experimentation (refund) with small seed holdings.
- Longer levels without long penalties for falling.

**Non-Goals:**
- A map, compass or exit beacon; new crop types; ramps and stairs; lighting and props.

## Decisions

1. **Maze on a cell grid, carved from a spanning tree.** Cells are 6 m. A DFS/recursive-backtracker carve gives a perfect maze (a tree). Start and exit are the two ends of the longest tree path, so the critical path winds by construction; regenerate if it has fewer than three turns or is shorter than the level's minimum (see `level-length`). Alternative: BSP rooms plus corridors, rejected because the fixed-width obstacle modules snap to cell edges more simply in a grid, and a tree guarantees one critical path to reason about.
2. **Rooms and variety.** After carving, merge fully connected 2x2 blocks into large rooms for some cells and let junctions be T or X. Corridor cells vary in width and ceiling height within limits so it reads as different places, not a grid.
3. **Obstacles are edge attributes on the tree.** Pick straight, degree-2 stretches on the critical path for critical modules; each splits the tree into regions R_0..R_n in path order. Module footprints (1 or 2 cells long, straight, rotatable by 90 degrees with plot directions rotated) come from the measured pit, ledge and gap. Alternative: place modules in any cell, rejected because turns inside a module would break the measured geometry.
4. **Loops only inside a region.** After obstacles are placed, add extra passages between adjacent cells whose region and elevation match, so loops never bypass an obstacle. Elevation is per region (a ledge raises its downstream region by 2.6 m), and cells of different elevation only connect through a ledge module.
5. **Optional and decoy obstacles.** Pick off-path subtrees (dead-end branches) and turn their entry edge into an optional module. Solving it opens an alcove or dead end; some hold an extra seed, some are empty decoys. A shortcut is a non-tree edge between two already-reachable regions with a module on it. None of these is ever on the path to the exit or to a critical seed.
6. **Seed placement.** The prefix rule from the previous design still applies: each critical seed sits in R_0..R_{k-1} for its obstacle k, outside any optional area. Extras go to dead ends, decoy alcoves and nooks. Refund (decision 7) is a safety margin, not a counted source.
7. **Uproot refunds the seed.** `Room:uproot` returns the crop type and `BackroomsState` adds one to the stock; the previous "not refunded" decision is reversed. Stock cannot exceed collected + starting seeds because only planted seeds can be refunded. Refusals (demo crop, player on or inside the crop, crop currently climbed) stay and refund nothing. Alternative: refund only on grown crops, rejected as it makes cancelling a wrong plant needlessly punishing.
8. **Checkpoints.** Each region records the position of its entry cell centre on solid level floor; `BackroomsState` tracks the current checkpoint as the player enters regions and respawns there on `killZ`. Reset returns to the spawn. This matters because falls become costly in 100 m+ levels.
9. **Level size.** Grid 6x6 for the first generated level up to a cap of 9x9; critical path at least 14 cells (about 84 m, about 21 s walking). Greedy-merged wall and floor boxes keep the box count in budget; a measured budget is checked in tests. Draw culling by cell distance is added if the budget is exceeded.
10. **Landmarks.** Junction and large rooms get a landmark id and a theme/lighting hint, chosen so adjacent junctions differ. This change only produces the data; `backrooms-visual-atmosphere` renders it.
11. **Generation budget.** Generation must finish in a fraction of a second. Retries are bounded (about 20 derived seeds); if all fail, a known-good fallback template is used and the failure is logged, so the game never hangs.
12. **Verification scales differently.** Exhaustive plot-assignment search (4^plots) is infeasible with many plots. Instead: (a) an exhaustive check on the abstract region/obstacle graph; (b) physics reachability for the no-crops case and the intended-solution case via `tests/reach.lua`; (c) each optional obstacle checked on its own. Property tests run over hundreds of seeds per level index.

## Risks / Trade-offs

- [Players get truly lost and quit] → Landmarks, checkpoints, a reset key and a modest maximum size; a map is deliberately not included. Revisit after playtests.
- [Collision or draw cost on large levels] → Box merging, a per-frame broad phase on colliders, draw culling, and a budget test.
- [Physics sweep too slow] → Decision 12; sample seeds in `check_all.sh`, run the larger sweep manually.
- [Elevation regions limit loops] → Loops are within a region only; accept less connectivity around ledges.
- [Refund removes scarcity] → Seeds are still limited to those collected, and structures must stay planted to be used, so players still choose where to spend them.
- [Conflicts with the unarchived `procedural-backrooms-levels`] → Apply this change on top of it and reconcile its wording at archive.

## Migration Plan

Implement on top of `procedural-backrooms-levels` (or rework its generator tasks in place), then archive. No data migration. Generator output stays in the existing room data format with new optional fields (`checkpoints`, `regions`, `landmarks`).

## Open Questions

- Whether an optional audio hint for the exit (a faint hum that grows nearer) helps without being a map.
- Final grid caps and critical-path minimums; tune from playtests.
