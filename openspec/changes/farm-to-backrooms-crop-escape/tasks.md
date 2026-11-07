# Tasks

> A checked box means the code is written. Runtime and manual verification
> status lives in `verification.md`; no Lua runtime was available, so those
> checks are still pending for 1.1-4.5.

## 1. Foundation and render path

- [x] 1.1 Let a state opt out of `push` in `main.lua` `love.draw`; verify a stub state draws a g3d cube at native resolution with correct depth while `StartState` still renders through push.
- [x] 1.2 Create `FarmState` and `BackroomsState` stubs, register them in `main.lua` and `src/Dependencies.lua`, and verify `StartState` -> farm -> backrooms transitions run via a debug key press.
- [x] 1.3 Add a shared game-data table (seeds, coins, crops, hasSold) passed through `gStateMachine:change`; verify the backrooms stub prints the seeds received.
- [x] 1.4 Add placeholder fallbacks (flat colors) for missing textures/sounds in `Dependencies.lua`; verify the game launches with empty asset folders.

## 2. 2D farm (farm-planting, farm-harvesting, villager-selling)

- [x] 2.1 Implement a farm grid with plots, a player cursor/avatar, and keyboard/mouse interaction; verify movement and plot highlighting by running the game.
- [x] 2.2 Implement plant, timed growth stages, and harvest on plots with Timer; verify seed count decreases, crops mature, and harvest adds to inventory.
- [x] 2.3 Implement a villager and selling for coins; verify coins and crop count update correctly, and the first plant -> harvest -> sell cycle finishes in under about 3 minutes.

## 3. The break (oversell-break, fall-transition, seed-carryover)

- [x] 3.1 Make the villager keep requesting crops after stock is gone and detect an over-sell only after `hasSold`; verify no break on first attempt before any sale and break after a sale.
- [x] 3.2 Implement the glitch sequence (shake, corruption, fall) that blocks input, then changes to the backrooms; verify the sequence plays once and ends in the backrooms.
- [x] 3.3 Carry seeds (not coins/crops) into the backrooms and top up to the first room's minimum; verify with a low-seed and a high-seed run.
- [x] 3.4 Add a fallback break trigger for idle players; verify it fires after the configured delay.

## 4. Backrooms world (first-person-controls, backrooms-collision, room-progression, billboard-assets)

- [x] 4.1 Implement first-person look and move using `g3d.camera` and `mousemoved` forwarding, with mouse capture; verify walking and looking in a plain box room.
- [x] 4.2 Implement a capsule player controller with gravity and slide-on-contact against room models via `g3d.collisions`; verify no clipping through walls/floors and no sticking in corners.
- [x] 4.3 Implement the data-driven `Room` builder (wall/floor boxes, plots, exit, seed allotment); verify a sample room loads from a data table.
- [x] 4.4 Add billboarded farm-asset sprites facing the camera; verify they rotate to face the player.
- [x] 4.5 Implement exit detection, room progression, and the ending screen; verify reaching an exit loads the next room and the last exit shows the ending.

## 5. Seed puzzles (seed-types, plot-planting, room-puzzles, tutorial-room, room-reset)

- [ ] 5.1 Implement seed definitions (beanstalk, pumpkin, vine) with final scale and growth axis and a tweened growth on a g3d model; verify each grows to its distinct shape and becomes collidable.
- [ ] 5.2 Implement nearest-plot planting, seed selection, and per-type seed HUD; verify planting only works at plots and counts decrease.
- [ ] 5.3 Implement beanstalk climbing (move up while inside the volume) and standing on pumpkin/vine tops; verify the player can climb and cross each structure.
- [ ] 5.4 Build Room 1 (tutorial) with a half-grown demo crop and a visible unreachable exit; verify one seed completes it and the exit is reachable.
- [ ] 5.5 Implement room reset restoring plots and seed allotment; verify reset after wasting seeds returns the room to its initial state.
- [ ] 5.6 Build Room 2 requiring two seed types; verify it is solvable only with the correct combination and unsolvable with one type.
- [ ] 5.7 Build Room 3 requiring all three seed types (cut first if behind schedule); verify solvability and add the ending hook.

## 6. Integration

- [ ] 6.1 Hook in user-provided graphics and sounds (farm sprites, backrooms textures, music, SFX) and verify they appear/play without errors.
- [ ] 6.2 Play through the full flow from start to ending, fixing blockers; verify the run completes in under about 15 minutes with no soft-locks.
- [ ] 6.3 Package a `.love` build and verify it runs with `love game.love`.
