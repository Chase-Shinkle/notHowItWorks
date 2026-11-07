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
