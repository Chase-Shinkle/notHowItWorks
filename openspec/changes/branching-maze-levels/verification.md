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

## Integration run (final, `sh tests/check_all.sh`, run once, NOT rerun)

The run was killed by my own 10-minute background timeout while inside the physical sweep (step 3), so the suite is **incomplete, not green**. Steps after the sweep (maze dump, maze_* tests, rim, fallback, launches, autotest, package) never ran. Raw log: /tmp/check_all_final.txt (not committed).

Completed steps:
- Unit/headless `tests/run.lua`: **194 passed, 4 failed**.
  - `backrooms opts out of push...`: tests/run.lua:114 drawn count got 18, want 15
  - `levelgen 2.2: a bad candidate is rejected...`: tests/run.lua:3547 second candidate used got 3, want 1
  - `sequence 4.1 ...`: tests/run.lua:3701 level seed got 1148977120, want 602283270 (expectation tied to the old generator/retry count)
  - `dressing review ...`: tests/run.lua:4351 merged baseboard model got 307, want 294
  - Likely stale expectations from the new generator (box counts, retry counts, seeds); not confirmed and not fixed.
- Reachability sweep: 84 assignments searched, 0 unexpected. (Look shader reports disabled in that harness: `love.filesystem.read` is nil under the mock runner; harness-only.)
- Physical sweep: started, no result.

## Visual review (/workspace/qa/maze/final/)
- `maze_d1_s1.png`, `maze_d3_s2.png` layout maps inspected by the orchestrator: real branching, turns and loops (d1 path 25 / turns 18 / loops 1; d3 path 55 / turns 34 / loops 5).
- In-game shots (seed 1, levels 2 and 3): `L*-pit-L*.png` shows a readable pit rim with a black void; `L*-turn-*`, `L*-junction-*` captured.

## Known limits
- `junction` shot (L3) looks like a plain corridor; the scene picks a path cell with degree >= 3 but the camera looks down the path, so the side branch is not clearly visible.
- `exit` scene in tests/backrooms_shots.lua assumes the exit lies along +x; in maze levels the shot faces a wall. Needs a path-direction-aware exit scene.
- Post-pass black void was only viewed on the pit shots, not an exit-specific one.
- Everything beyond the 4 unit failures above is unverified. Chase tests himself.

## Final fix pass (nothing below was re-tested; suite NOT rerun, NOT green)

Changed:
- `src/LevelGen.lua` / `src/constants.lua`: the carve is now a growing tree (`LEVELGEN_CARVE_MIX = 0.5`: half of carve steps extend a random active cell instead of the newest), and a candidate is rejected when the critical path exceeds `LEVELGEN_MAX_PATH_FRAC` (0.6) of the grid cells (difficulty-1 row overrides to 0.7 because its 21-cell minimum is 58% of 36). Grid sizes (6/8/9), minPath and gate counts are unchanged; required critical gates are not pruned.
- Measured by generation only (`tests/maze_layout.lua`, seeds 1-6, diffs 1-3): d2 path 27-34 of 64 cells (42-53%), d3 34-46 of 81 (42-57%), d1 21-25 of 36 (58-69%); loops 4-11 at d2/d3; 3-5 optional gates per level incl. a shortcut at d2/d3; every path still meets minPath (>= 30 s walk). These layouts changed from the earlier ones, so seed-specific expectations elsewhere may break.
- Stale test assertions, each checked against code: `tests/run.lua` draw count now includes the 3-part exit frame (Room.exitFrame, render-only); levelgen 2.2 picks a seed that passes first time and expects a later (>=1) derived attempt (layout rules can also reject candidates); sequence 4.1 checks `meta.requestedSeed == levelSeed(run, i)` (and `meta.seed` equal when attempt 0) because retries replace `meta.seed`; baseboard test expects `#models >= #boxes + 1` because pit rims render as several void parts. These edits were not run.
- `tests/backrooms_shots.lua`: `exit` scene approaches along the real last path step; `junction` scene stands 2 m before a path junction and looks between the path and the side opening.
- Re-rendered `/workspace/qa/maze/final/` (layout maps d1-d3 x seeds 1-3; L2/L3 pit, exit, junction, turn shots at run seed 1). Images not evaluated by me.

Still unverified: full `tests/check_all.sh` (incomplete since the earlier 10-minute timeout), the four edited assertions, other tests that may depend on old seeds/layouts (maze_*, sweeps, autotest, packaging), whether the new junction/exit shots read well, and whether path fraction at d1 (up to 69%) is acceptable.

## Exit render regression (fixed; tests NOT rerun)

The L2 exit shot (`qa/maze/final/L2-exit-L2.png`) showed a solid beige block instead of a black void. Root cause: the exit frame posts in `Room.lua` were full-width boxes offset along Y, so when the exit is approached along Y (the new exit shot scene follows the real last path step) the near post sat in front of the void and covered it. The frame is now four corner posts plus a lintel ring outside the void's faces, so it cannot occlude the void from any side. Recaptured the same scene (run seed 1, gen-1907137354): interior solid black with a pale frame, look on and `--no-shader` (`L2-exit-L2-plain.png`). Pit scene unchanged. No tests, suite or sweeps were rerun after this change.
