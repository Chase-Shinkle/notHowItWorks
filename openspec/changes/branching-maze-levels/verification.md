# Verification

## Section 6 (level size and sequence): implemented, unverified

Rows in `LEVELGEN_DIFFICULTY` (`src/constants.lua`), level i uses row i-1 (already wired in `BackroomsState`; `BACKROOMS_GENERATED_LEVELS = #LEVELGEN_DIFFICULTY`):

| level | obstacles | grid | minPath | minTurns | branches |
|---|---|---|---|---|---|
| 1 | 2 | 6x6 | 14 | 3 | 2 |
| 2 | 3 | 8x8 | 20 | 4 | 3 |
| 3 | 4 | 9x9 | 26 | 5 | 4 |

`LevelGen.build` honors `grid`, `minPath`, `minTurns`; `branches` is data for the branch sections. Data test: `tests/maze_scaling.lua` (not run).

### Instructions for tests/autotest.lua (owned by another agent)
- Full flow: levels are now longer (path 14/20/26 cells at 4 m/s, 6 m cells: roughly 21/30/39 s of pure walking, plus obstacles and branches). Raise the full-flow total timeout and any per-level timeout to scale with the level index (e.g. base 60 s + 2x the walking time of `LEVELGEN_DIFFICULTY[i].minPath * LEVELGEN_CELL / BACKROOMS_WALK_SPEED`), not a single constant.
- Per-level: log elapsed time per level at each level transition (task 6.2 "record time per level") and write it to verification.
- Loop over `#LEVELGEN_DIFFICULTY`, not a hard-coded 3.
