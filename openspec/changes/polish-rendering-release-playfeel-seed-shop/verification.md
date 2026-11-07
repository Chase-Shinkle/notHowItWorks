# Verification: polish-rendering-release-playfeel-seed-shop

All runs on LÖVE 11.5 (`/home/box/.local/bin/love`, LuaJIT 2.1) under Xvfb,
branch `feature/farm-to-backrooms`, starting from `1e76973`.

Workflow note: the `openspec` CLI is not installed in this environment, so the
apply workflow was followed by hand against `tasks.md` (read proposal, design,
specs and tasks; tick each checkbox as its task is verified).

Baseline before any change (`sh tests/check_all.sh` at `1e76973`): all checks
passed. 105 headless tests, 84 reachability assignments (0 unexpected),
autotest 82 checks with real assets and 74 with placeholders, from source and
from the `.love`, and two package builds with the same sha256.

## 1. Pixel-art filtering (M1)

- 1.1 `love.graphics.setDefaultFilter('nearest', 'nearest')` is now the first
  statement in `main.lua`, before `require 'src/Dependencies'`. The later call
  in `love.load` is removed. Real-runtime probe in `tests/autotest.lua`:
  hero, crop-beanstalk-3, crop-pumpkin-5, plot, well, bucket, villager, grass,
  soil, seedbag-vine, produce-pumpkin and the default and small fonts all report
  `nearest/nearest`, with real and with placeholder assets.
- 1.2 `wall`, `floor`, `ceiling` are rebuilt with mipmaps and set to linear
  (`Assets.smoothImage`, list `SMOOTH_SURFACE_TEXTURES` in
  `src/Dependencies.lua`). Real runtime: `linear/linear` with 12, 11 and 12
  mipmap levels. Placeholder surfaces stay `nearest/nearest`. Screenshots show
  no mipmap artifacts on the walls or floor. Close-ups are saved by the autotest
  as `02-farm-zoom.png` (farm HUD text, seed bags, grass),
  `06-room1-arrival-zoom.png` (backrooms HUD text) and
  `09-room2-arrival-zoom.png` (billboard sprite, 5x). Before and after crops of
  the farm HUD show that the blur is gone.
- 1.3 The probe runs automatically under `sh tests/check_all.sh` in two forms:
  two headless tests in `tests/run.lua` (`filtering: ...`, using a mock that now
  models LÖVE's default filter) and the real-runtime checks in
  `tests/autotest.lua`. Reversion check: with the call moved back into
  `love.load`, the headless suite gave `105 passed, 2 failed` (both filtering
  tests) and the autotest gave `98 checks, 13 failed` (every sprite and font).
  The change was then restored.

## 2. Release config (M2)

- 2.1 `DEBUG_MODE = false` in `src/constants.lua`. `--debug` is parsed in
  `src/Dependencies.lua` with `--placeholder-assets`, and `--autotest` is still
  handled in `main.lua`. `xvfb-run -a timeout 8 love . --debug` kept running
  with no errors (exit 124). Autotest from source with `--debug`: 101 checks,
  0 failed. These include "debug: F1 marker on the farm HUD" and "debug: debug
  line on the backrooms HUD (f1: debug skip room fps: ...)", with the F1 skip
  used. Without the flag: 104 checks, 0 failed. These include F1 doing nothing
  at the start screen, on the farm and in Room 1, and no debug text being
  drawn on the farm or backrooms HUD. The autotest wraps
  `love.graphics.print`/`printf` and inspects the text actually drawn each frame.
- 2.2 Every headless test that presses F1 now loads with `{'--debug'}`. That
  is 9 tests, including the break input-lock test, so F1 is live there and is
  still shown to be ignored. Two new tests were added: `release: debug mode is
  off by default; F1 changes no state and no debug text is drawn` (start, farm,
  backrooms and ending) and `release: --debug opts in to F1 skip and the debug
  HUD text`. The autotest sets `DEBUG_MODE = true` explicitly before its
  F1 x2 resize step. `tests/reachability.lua` does not use F1. `check_all.sh`
  gained an artifact playthrough with `--debug`. Full `sh tests/check_all.sh`:
  ALL CHECKS PASSED (109 headless tests, 84 reachability assignments with 0
  unexpected, autotest 104 real / 96 placeholder from source and artifact, and
  101 for the artifact with `--debug`).
- 2.3 `RELEASE.md` now says that debug mode is off in the build and that only
  `--debug` turns it on, and that `package.sh` never does. `README.md` is
  updated the same way. In
  `openspec/changes/farm-to-backrooms-crop-escape/verification.md`, a note at
  the top marks every F1 mention as debug-only. The "DEBUG_MODE is still on in
  the package" item and the publishing to-do are marked as resolved. Historical
  text is otherwise kept. A grep of the docs finds no claim that debug is on
  by default.
- 2.4 `sh tools/package.sh` was run twice with the same sha256
  (`6264ac91...d45b` at this point; the hash changes in later sections because
  the tree changes). `tools/package.sh` is unchanged. The packaged
  `src/constants.lua` has `DEBUG_MODE = false` and the packaged `RELEASE.md`
  has the new debug section. Artifact playthrough without the flag: F1 does
  nothing at start, on the farm and in Room 1, and no debug text is drawn
  (104 checks, 0 failed). With `--debug`: 101 checks, 0 failed.
