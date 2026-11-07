# Tasks

## 1. Maze carving

- [~] 1.1 In `src/LevelGen.lua`, implement the seeded cell-grid carve, longest-path start/exit selection and turn/length acceptance with bounded retries and a fallback template; property test over 300 seeds that every level is a connected tree plus loops, has at least three critical-path turns and meets its minimum length.
  - IMPLEMENTED in src/LevelGen.lua (carve, longest path, turn/length acceptance, bounded retries + serpentine fallback); the 300-seed property test is NOT written or run (Chase runs tests).
- [~] 1.2 Merge connected 2x2 blocks into large rooms and vary junction shape, corridor width and ceiling height; test no overlapping geometry and that junctions of degree three or more exist.
  - IMPLEMENTED (2x2 rooms, ceiling/width variety, T/X junctions from the tree); dedicated overlap test NOT written, nothing run.
- [~] 1.3 Emit walls, floors and ceilings with doorways as merged boxes in room format and pass `Room.validate`; test box count stays within the configured budget for the largest level and measure frame cost of drawing and colliding with it.
  - IMPLEMENTED (merged floors/ceilings, `LEVELGEN_BOX_BUDGET` check in `LevelGen.check`, `Room.validate` called by check); frame-cost measurement NOT done.

## 2. Obstacles, regions and elevation

- [~] 2.1 Define module footprints (1 or 2 cells, straight, rotatable) from the measured pit, ledge and gap, rotating plot positions and directions; test each module in all four rotations against crop sizes.
  - IMPLEMENTED (`LevelGen.frame`, rotated modules, 1-cell footprints only; `footprint` field ready for 2-cell modules); per-rotation crop test NOT written or run.
- [~] 2.2 Place critical modules on straight degree-2 path stretches, compute regions R_0..R_n and per-region elevation and ceiling height; test the exit is unreachable without crops and the elevation changes only at ledge modules.
  - IMPLEMENTED (modules on straight degree-2 cells, regions, elevation, checks in `LevelGen.check`); unreachable-without-crops is asserted by `check`, not separately run.
- [~] 2.3 Add loops only between same-region, same-elevation cells; test no loop bypasses an obstacle.
  - IMPLEMENTED (loops/rooms only within same region and elevation, enforced in `check`); not run.

## 3. Branch plots

- [~] 3.1 Turn off-path subtrees into optional modules (alcoves, empty decoys, extra-seed dead ends) and add at least one shortcut in later levels; test each optional area is unreachable until its module is solved and that none gates the exit or a critical seed.
  - IMPLEMENTED in src/LevelGen.lua (section 2b/4b, `LevelGen.checkBranches`, called by `check`): alcove/dead-end modules (pit/gap) on straight off-path cells with the subtree behind them as walled-off area, decoys vs extra-seed rewards, shortcut modules (leaf joined straight across to a same-region cell) from difficulty 2 on. Assertions in tests/maze_branches.lua; NOT run, nothing in this section has been executed.
- [~] 3.2 Enforce at least two more plots than critical obstacles; test the plot counts across many seeds.
  - IMPLEMENTED: `checkBranches` requires `#plots >= obstacles + 2` (generation retries a seed otherwise); count test in tests/maze_branches.lua, NOT run.
- [~] 3.3 Place critical seeds by the prefix rule outside optional areas and extras in dead ends and alcoves; test prefix sufficiency and that a critical-seed-only run solves the level.
  - IMPLEMENTED: critical seeds stay in non-optional branch/filler cells of earlier regions; extras in non-optional dead ends and optional areas; prefix check blocks optional modules; test in tests/maze_branches.lua, NOT run. Physical (reach) critical-only run belongs to 7.1.

## 4. Uproot refund

- [ ] 4.1 Make `Room:uproot` return the crop type and refund one seed in `BackroomsState`, cancelling pending growth for growing crops; tests for grown, growing, demo-refusal and standing-on refusal, including the repeated plant and uproot stock invariant. (implemented, UNVERIFIED: tests/maze_refund.lua written, not run)
- [ ] 4.2 Add the uproot key and message, and update the HUD text; verify in a headless play script that plant then uproot restores the seed count. (implemented, UNVERIFIED: HUD/message done; headless play script not run)

## 5. Checkpoints and respawn

- [ ] 5.1 Record region checkpoints on solid floor and track the player's current checkpoint on entering regions; test a checkpoint is never on a crop and updates on entry.
  - IMPLEMENTED (`Room:buildCheckpoints`/`regionAt`, `BackroomsState:updateCheckpoint`); UNVERIFIED: tests in `tests/maze_checkpoints.lua` written, not run.
- [ ] 5.2 Respawn at the current checkpoint on `killZ`, keeping crops, seeds and collected pickups, and return to the spawn on reset; test both paths.
  - IMPLEMENTED (`BackroomsState:respawnAtCheckpoint` on killZ; `resetCheckpoint` on load/reset); UNVERIFIED: not run.

## 6. Level size and sequence

- [ ] 6.1 Configure grid sizes (6x6 up to 9x9), minimum path lengths and branch counts per level index in `src/constants.lua`; test levels never shrink and the last exceeds the first.
- [ ] 6.2 Wire the longer levels into the level sequence and the autotest; run the full flow to the ending and record time per level.

## 7. Verification and review

- [ ] 7.1 Extend `tests/reach.lua` and `tests/reachability.lua` with the abstract-graph exhaustive check, the intended-solution physics run and per-optional-module runs; run them over hundreds of seeds per level and fix generator failures found.
- [ ] 7.2 Add a layout dump (ASCII map per seed) for review, then playtest several seeds per level, tune the size caps, loop counts and decoy ratio, and record findings.
- [ ] 7.3 Add the new tests to `tests/check_all.sh` and run it green on the real LÖVE runtime.
