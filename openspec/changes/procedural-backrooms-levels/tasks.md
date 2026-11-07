# Tasks

## 1. Generator foundation

- [x] 1.1 Add seeded RNG and level-seed derivation in `src/LevelGen.lua`; unit test that equal seeds give equal sequences and different seeds differ (tests/run.lua).
- [x] 1.2 Define pit, ledge and gap obstacle modules from the current room measurements (entry/exit faces, plots, dirs, elevation change, min ceiling); test each module's dimensions against the Crop sizes.
- [x] 1.3 Implement chain selection by difficulty and the cell grid layout with filler rooms, halls, loops, dead ends and secret nooks, emitting room-format boxes, plots and exit; test: no overlapping cells, all regions connected, `Room.validate` passes.
- [x] 1.4 Track floor elevation and ceiling clearance through the chain; test a ledge-then-gap chain keeps the exit reachable with enough headroom.

## 2. Seeds and pickups

- [x] 2.1 Place critical seeds by the prefix rule and extras in dead ends/nooks, add `pickups` and `seedTypes` to the output; property test over 500 seeds that prefix sufficiency holds and critical seeds are never behind their own obstacle.
- [x] 2.2 Add the generation self-check with derived-seed regeneration; test that a forced-bad candidate is rejected and replaced.
- [x] 2.3 Extend `Room.validate`/`Room:init` to accept and build pickups and `seedTypes`; test validation errors and that bad pickups are rejected.
- [x] 2.4 Render pickups as bobbing seed-bag billboards and collect them by proximity in `BackroomsState`, with message and HUD count update; test collection adds one seed and removes the pickup.
- [x] 2.5 Make `visibleSeedTypes` use `seedTypes` when present; test a pumpkin+vine level lists only those two.

## 3. Uproot

- [ ] 3.1 Add crop removal in `Crop.lua`/`Room.lua` and the uproot key and action in `BackroomsState`; test the plot accepts a new seed after uprooting and the seed count is unchanged.
- [ ] 3.2 Refuse uprooting the demo crop and while the player stands on or inside the crop; tests for both with the on-screen message.

## 4. Sequence and reset

- [ ] 4.1 Add the level sequence (tutorial, then generated levels with the difficulty table and run-seed derivation, logging and override) in constants and `BackroomsState`; test the sequence order and per-level seeds.
- [ ] 4.2 Apply the seed-stock policy (zero start, no carry between levels, tutorial unchanged) in `GameData.lua`; test starting stocks for tutorial and generated levels.
- [ ] 4.3 Make reset rebuild from the same seed, restore starting seeds, respawn pickups and clear crops; test layout equality and pickup restoration after reset.
- [ ] 4.4 Wire the ending after the last generated level; run the full flow in `tests/autotest.lua` and confirm it reaches the ending.

## 5. Solvability verification

- [ ] 5.1 Extend `tests/reachability.lua` to sweep hundreds of seeds per difficulty: exit unreachable with no crops, reachable with the intended crops; fix any generator failures found.
- [ ] 5.2 Add the sweep and property tests to `tests/check_all.sh` and run it green on the real LÖVE runtime.
- [ ] 5.3 Playtest each generated level index with a few seeds, tune the difficulty table and pickup radius, and record seeds that exposed bugs in the verification notes.
