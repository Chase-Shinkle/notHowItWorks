# Tasks

## 1. Pixel-art filtering (M1)

- [x] 1.1 Move `love.graphics.setDefaultFilter('nearest','nearest')` to the top of `main.lua` before `require 'src/Dependencies'` and remove the later call; verify a headless/real-runtime probe reports `getFilter()` = nearest for hero, crop, plot, well, bucket images and the default and small fonts.
- [x] 1.2 Keep `wall`, `floor`, `ceiling` linear (mipmapped only if artifact-free) and confirm placeholder images are nearest; verify with the same probe and a screenshot of text and sprites up close.
- [x] 1.3 Add the filter probe as an automated check in `tests/` (runs under `sh tests/check_all.sh`) and verify it fails if the call order is reverted.

## 2. Release config (M2)

- [x] 2.1 Set `DEBUG_MODE` default to `false` and add a `--debug` launch flag that enables it, handled with the existing launch flags; verify `love . --debug` shows F1 skip and the debug HUD text and `love .` shows neither.
- [x] 2.2 Update `tests/autotest.lua`, mocks and any script that presses F1 or reads `DEBUG_MODE` to opt in explicitly; verify `sh tests/check_all.sh` passes.
- [x] 2.3 Update `RELEASE.md` (debug section, controls) and the F1 mentions in `openspec/changes/farm-to-backrooms-crop-escape/verification.md`; verify no doc claims debug is on by default.
- [x] 2.4 Rebuild with `sh tools/package.sh`, confirm the sha256 is stable across two builds, and verify on the packaged `.love` that F1 does nothing and the HUDs show no debug text.

## 3. Pit-plot reach (M3)

- [x] 3.1 Add an optional per-plot `reach` (default `BACKROOMS_PLANT_RANGE`) used by `Room:nearestPlot`, and set it to about 2.6 m on the Room 2 and Room 3 `pit` plots; verify a headless test plants a pumpkin from the spawn-side floor at 1.0 m and 2.0 m back from the rim in both rooms.
- [x] 3.2 Rerun the reachability checks and the playthrough; verify all rooms are still solvable with their allotments and not solvable without the required seed types, and the nearest-plot rule still resolves `foot`/`lip` in Room 3.
- [x] 3.3 Re-measure with `scripts/rim.lua` (or equivalent) and verify the plantable floor span is at least 2.5 m wide, with no change needed to the pit geometry.

## 4. Seed stall (M4, farm)

- [x] 4.1 Add `FARM_SHOP` and `SEED_PRICES` constants (each price below the crop sale value) and a pure `Farm.buySeed(gameData, seedType)`; verify headless tests for success, insufficient coins, and no change to crops or `hasSold`.
- [x] 4.2 Add the stall as a target in `FarmState` (draw, hover, click, face + use key, hint text, popups, `deny` on failure, disabled during the break); verify in a playthrough that buying works by keyboard and mouse and the stall tile is walkable-around and not overlapping plots, villager or HUD.
- [x] 4.3 Verify the break is unaffected: a test that buying after the first sale leaves `idleTimer` untouched, over-sell still breaks, and carry-over still produces seeds only with the Room 1 top-up.
- [x] 4.4 Update `RELEASE.md` controls with the stall and extend `tests/autotest.lua` with a buy step; verify `sh tests/check_all.sh` passes.

## 5. Backrooms HUD (M4, backrooms)

- [x] 5.1 Add a `visibleSeedTypes()` derived from the room allotment and use it for the HUD seed list and for `1-3`, `Q`, `Tab` selection; verify headless tests for Room 1 (beanstalk only), Room 2 (pumpkin, vine), Room 3 (all), hidden-key no-op and cycling.
- [x] 5.2 Verify room reset still restores the recorded seeds and Room 1 carry-over with extra pumpkin and vine seeds is unchanged (`tests/` seed-carryover tests plus the playthrough), and a screenshot of the Room 1 HUD shows only beanstalk and no coins.

## 6. Integration

- [ ] 6.1 Run `sh tests/check_all.sh` end to end (headless tests, reachability, launches, playthrough with real and placeholder assets, from source and from the rebuilt `.love`); verify all pass.
- [ ] 6.2 Play the packaged `.love` once by hand: crisp text and sprites, no F1 effect, plant the Room 2/3 pit from a comfortable distance, buy and plant a seed on the farm; record results in `verification.md`.
