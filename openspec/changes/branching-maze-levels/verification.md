# Verification

## Section 6 (level size and sequence): implemented, unverified

Rows in `LEVELGEN_DIFFICULTY` (`src/constants.lua`), level i uses row i-1 (already wired in `BackroomsState`; `BACKROOMS_GENERATED_LEVELS = #LEVELGEN_DIFFICULTY`):

| level | obstacles | grid | minPath | minTurns | branches |
|---|---|---|---|---|---|
| 1 | 2 | 6x6 | 21 | 3 | 2 |
| 2 | 3 | 8x8 | 27 | 4 | 3 |
| 3 | 4 | 9x9 | 33 | 5 | 4 |

`LevelGen.build` honors `grid`, `minPath`, `minTurns`; `branches` is data for the branch sections. Data test: `tests/maze_scaling.lua` (not run).

Integration note: the level-length spec needs both "critical path >= 14 cells" and "pure walking time >= 30 s". At 6 m cells and 4 m/s, 14 cells is only 19.5 s, so minPath was raised to 21/27/33 (still >= 14; (21-1)*6/4 = 30.0 s). `tests/maze_scaling.lua` now asserts both. Whether the generator reaches 21 cells on 6x6 without the serpentine fallback is checked from the layout dump (`meta.fallback`), not yet from a test.

### Instructions for tests/autotest.lua (owned by another agent)
- Full flow: levels are now longer (path 21/27/33 cells at 4 m/s, 6 m cells: 30/39/48 s of pure walking, centre to centre, plus obstacles and branches). Raise the full-flow total timeout and any per-level timeout to scale with the level index (e.g. base 60 s + 2x the walking time of `LEVELGEN_DIFFICULTY[i].minPath * LEVELGEN_CELL / BACKROOMS_WALK_SPEED`), not a single constant.
- Per-level: log elapsed time per level at each level transition (task 6.2 "record time per level") and write it to verification.
- Loop over `#LEVELGEN_DIFFICULTY`, not a hard-coded 3.
