# Proposal

## Why

A post-build review of `farm-to-backrooms-crop-escape` found four medium issues that hurt the jam build: sprites and text render blurry, debug keys ship in the `.love`, the Room 2/3 pit plot is easy to overshoot and fall into, and coins and seed counts are shown but cannot be used. Fixing them now makes the submitted build look, play and read as intended.

## What Changes

- **M1 Rendering**: Pixel art and fonts load with nearest-neighbour filtering. Large backrooms surface textures stay linear (mipmapped if cheap).
- **M2 Release config**: The packaged `.love` ships with debug mode off (no F1 skip, no debug HUD text or F1 marker). Development runs can still turn it on.
- **M3 Pit plot playfeel**: The pit plots in Rooms 2 and 3 can be planted from a comfortable distance back from the rim, so players don't have to hit a 0.57 m strip to avoid falling.
- **M4 Seed economy (design call: coins buy seeds)**: Add a seed stall on the farm where coins buy seeds, so coins are spendable and farm seeds can go up as well as down. The backrooms HUD shows only the seed types usable in the current room, so Room 1 no longer shows pumpkin and vine counts it cannot use.
- Out of scope: new puzzles, changes to room layouts or allotments, new carry-over rules (seeds-only carry-over stays; Rooms 2+ keep fixed allotments), re-tuning the break timing.

## Capabilities

### New Capabilities
- `pixel-art-rendering`: filtering rules for sprites, tiles and fonts versus large 3D surface textures.
- `release-build-config`: debug features are off in the packaged build and on only by explicit opt-in.
- `backrooms-pit-planting`: reach and prompt rules so pit plots can be planted before the rim without falling.
- `farm-seed-shop`: spend coins on the farm to buy seeds.
- `backrooms-seed-hud`: the backrooms HUD lists only seed types usable in the current room.

### Modified Capabilities
None. `openspec/specs/` is empty because `farm-to-backrooms-crop-escape` is not yet archived; the related capabilities there (`villager-selling`, `seed-carryover`, `plot-planting`, `room-puzzles`) are unchanged in behavior and these deltas are written as new capabilities that do not contradict them.

## Impact

- `main.lua`, `src/Assets.lua`, `src/Dependencies.lua` (filter order).
- `src/constants.lua` (`DEBUG_MODE`, `BACKROOMS_PLANT_RANGE` or a pit-specific range, shop price/position constants), `tools/package.sh`, `RELEASE.md`.
- `src/Room.lua`, `src/rooms.lua` (pit plot reach), `src/states/game/BackroomsState.lua` (HUD).
- `src/states/game/FarmState.lua`, `src/Farm.lua`, `src/GameData.lua` (seed shop, hint text, HUD).
- Tests under `tests/` (headless tests, `autotest.lua` playthrough, reachability) and `openspec/changes/farm-to-backrooms-crop-escape/verification.md` references to F1.
