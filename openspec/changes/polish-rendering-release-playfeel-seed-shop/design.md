# Design

## Context

The review findings are in `proposal.md`. Relevant current state:

- `main.lua:1` requires `src/Dependencies`, which loads all images and fonts through `Assets.loadImage` / `Assets.loadFont` before `love.load` runs `setDefaultFilter('nearest','nearest')`, so everything is created with the default linear filter.
- `DEBUG_MODE = true` in `src/constants.lua:11` gates `main.lua` (F1 skip), `BackroomsState` and `FarmState` debug text. `tools/package.sh` zips the tree unchanged.
- `Room:nearestPlot` uses `BACKROOMS_PLANT_RANGE = 1.8` (horizontal distance to the plot centre). The pit plot sits at the pit centre, so only a thin strip at the rim is both on the floor and in range.
- `CarryOverGameData` keeps seeds only; `RoomStartingSeeds` tops up Room 1 and replaces seeds in Rooms 2+. Coins have no sink. Farm targets are plots and one villager tile (`FarmState:targetAt`).
- The related behavior specs live in the unarchived change `farm-to-backrooms-crop-escape`; nothing here edits them.

## Goals / Non-Goals

**Goals:**
- Crisp pixel art and text with no per-asset special-casing at call sites.
- A release `.love` with debug off, reproducible, with an explicit dev opt-in.
- Pit plots plantable from a comfortable distance without opening puzzle shortcuts.
- Coins spendable; backrooms HUD shows only usable seeds.

**Non-Goals:**
- Changing room layouts, allotments, carry-over or the break timing.
- A full shop UI, prices that vary, or saving.

## Decisions

1. **Filtering (M1)**: call `love.graphics.setDefaultFilter('nearest','nearest')` at the very top of `main.lua`, before the `require`, and remove the later call. Large backrooms textures (`wall`, `floor`, `ceiling`) are explicitly set to linear (with mipmaps if it works in LÖVE 11.5 without artifacts) after loading. *Alternative*: set the filter inside `Assets.loadImage`/`loadFont`; rejected as the default because placeholder images and any future loader would need the same call. A one-line top-of-file default covers all of them.
2. **Debug flag (M2)**: `DEBUG_MODE` defaults to `false` in `src/constants.lua`. Development opts in with a command-line flag (`love . --debug`), parsed alongside the existing `--autotest` / `--placeholder-assets` handling, and with no change to `package.sh`. *Alternative*: have `package.sh` rewrite the constant; rejected because it makes the package differ from the tree and complicates the reproducible-hash check. `tests/autotest.lua` uses F1? If so it must set the flag itself rather than rely on the default; this is checked in tasks. `RELEASE.md` is corrected.
3. **Pit reach (M3)**: add a per-plot optional `reach` field (default `BACKROOMS_PLANT_RANGE`) and set pit plots to 2.6 m. A plot-level value avoids raising range for plots near ledges where a large reach could let the player plant from the wrong level (the vertical limit `BACKROOMS_PLANT_HEIGHT` still applies, so a pit plot at -1.0 m remains reachable from floor level only if the height check allows it; verify). *Alternatives*: raise the global range to 2.5 (risks neighbouring plots such as `foot`/`lip` in Room 3 becoming ambiguous, though nearest-plot still resolves); look-direction raycast (more code, hurts keyboard-only feel). The reachability tool (`tests/reach.lua`, `reachability.lua`) is rerun to confirm no new shortcuts.
4. **Seed stall (M4)**: add `FARM_SHOP = {col, row}` and `SEED_PRICES` constants. Suggested prices: beanstalk 2, vine 3, pumpkin 4 against sale values 3, 4, 5, so each harvest-sell-rebuy cycle nets 1 coin. The stall is a new target kind `'shop'` in `FarmState:targetAt` / `interact`; it buys one seed of `selectedSeed` per use via a pure `Farm.buySeed(gameData, seedType)` returning `ok, reason` (testable headless). It reuses an existing seed-bag sprite for art and the existing `deny` and `sell` sounds. It does not touch `idleTimer`/`nagTimer` and is disabled during the break (`self.breaking`). Position: an unoccupied tile away from plots and the villager (e.g. col 8, row 7); verify walkability and that the starting hint still reads clearly. *Alternatives*: hide coins (smaller, but the user chose to give coins a use); a menu-based shop (more UI).
5. **Backrooms HUD (M4)**: the HUD and the `1-3` / `Q` / `Tab` selection iterate a `visibleSeedTypes()` list derived from the current room's allotment (`allotment[t] > 0`). The room data is unchanged and `self.gameData.seeds` still holds all types, so reset and carry-over behave as before. The backrooms HUD does not draw coins (it already does not; this is now specified).

## Risks / Trade-offs

- [Tests rely on F1 or on `DEBUG_MODE`] → grep `tests/` for both; make the autotest and mock runners set the flag explicitly; add a test that the default is off.
- [Packaged build hash changes] → expected; recheck the reproducible double-build.
- [Mipmapped linear surfaces shimmer or fail on some GPUs] → fall back to plain linear if any artifact appears; correctness only requires pixel art to be nearest.
- [Pit reach lets the player plant from the wrong side or a different height] → height check plus reachability tool, and a headless test at the spawn and rim positions measured in the review (`scripts/rim.lua`).
- [Shop makes the farm grindable] → prices are constants; a net +1 per cycle with a 12 s grow is slow enough, and the break is still triggered by the villager, not by seed count.
- [Hiding seed types hides information about carried seeds] → deliberate; those seeds cannot be used in that room.

## Migration Plan

No data migration. Ship by rebuilding with `sh tools/package.sh` and rerunning `sh tests/check_all.sh`. Rollback is a git revert.

## Open Questions

- Exact prices and stall tile may be tuned during playtesting without changing specs (the spec requires only price < sale value).
