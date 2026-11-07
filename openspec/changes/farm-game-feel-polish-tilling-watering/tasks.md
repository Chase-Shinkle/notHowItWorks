# Tasks

## 1. Display names and plot-care rules

- [x] 1.1 Add `SEED_DISPLAY_NAMES` and `SeedName()` and route every player-visible seed name in `FarmState` and `BackroomsState` through it; verify a test that no farm hint, popup, villager line or shop hint contains "vine" and that internal keys, allotments and carry-over are unchanged.
- [x] 1.2 Add `tilled`/`watered` plot state, `Farm.till`, `Farm.water`, a tilled requirement in `Farm.plant`, and `Farm.advance(plot, dt)` replacing the per-plot Timer (rate 1 watered, `FARM_UNWATERED_RATE` otherwise, progress kept when watering mid-growth); verify headless tests for till-then-plant, replant keeps tilled, water lost on harvest, watered timing 12 s, unwatered 24 s, and mid-growth watering.
- [x] 1.3 Make `FarmState:interact` and the hint text use one `plotAction` helper (till, plant, water, harvest, growing) and have `update` advance growth; verify hints and actions agree for every plot state and that the break still freezes growth and input and is unaffected by tilling or watering after a sale.
- [x] 1.4 Update `tests/run.lua` and `tests/autotest.lua` for the new first-use flow (till, plant, water), and the README and RELEASE.md growth and controls text; verify `sh tests/check_all.sh` passes and the first plant, harvest and sell cycle still finishes well under 3 minutes with and without watering.

## 2. Effects module and game feel

- [x] 2.1 Add `src/Fx.lua` (capped particle bursts per action, pop tweens, squash tween, flying pickup, coin ticker, all `dt`-driven and not on knife groups); verify unit tests for lifetime cleanup, the particle cap, ticker convergence for gains and spending, and that no effects remain a few seconds after input stops.
- [x] 2.2 Wire bursts and pops into till, plant, water, harvest, sell and buy in `FarmState`, with no emission while breaking; verify with headless calls that each action emits an effect and the break emits none.
- [x] 2.3 Add the flying harvested-crop icon to its produce slot with a slot pulse, and the coin ticker with coin sparkles (data updated immediately); verify the count is correct on the same frame and the displayed coins reach the real total.
- [x] 2.4 Add growth-stage squash and a maturity sparkle using the stage change returned by `Farm.advance`; verify a test that a stage change starts a squash which then returns to scale 1.
- [x] 2.5 Add `tools/gen_sounds.py` (stdlib only) generating soft till, plant, water, harvest, coin, buy, deny and glitch WAVs into `sounds/`, add the `till`, `water` and `coin` keys to `Dependencies.lua` and play each in the matching action; verify running the tool creates the files, a launch logs no placeholder-sound lines for them, and a missing file still runs silently.

## 3. Characters and HUD

- [x] 3.1 Add `tools/make_villager.py` (Pillow, dev-time) producing `graphics/characters/villager.png` (different hair, hat, apron), load it as `villager` and remove the draw-time tint; verify the loaded villager image differs from the hero and a screenshot shows them distinguishable.
- [x] 3.2 Add the villager sale bounce and the tool icon beside the farmer (shovel, seed bag, watering can, sickle, none when nothing usable is faced); verify a test mapping each plot state to its icon and a screenshot of each.
- [x] 3.3 Rebuild the top bar: seed group, divider, produce group, dimmed empty slots (selected slot stays highlighted), coin icon with amount, and day number; verify no overlap with three-digit counts by a layout test on the computed rectangles and a screenshot.

## 4. World dressing

- [x] 4.1 Add `FARM_DECOR` (fence, path, bushes, pond, well, barn anchor and blocking flags) and make `isWalkable` honour blocking decor; verify headless tests that blocking tiles stop movement, path tiles do not, and a breadth-first search from the player start finds a reachable walkable neighbour of every plot, the villager and the stall.
- [x] 4.2 Render the dressing: ground variation from a fixed-seed local RNG, path, fence, barn, well, bushes, pond, soft shadows under field sprites, and the three soil looks (untilled, tilled, watered); verify identical layout on two entries and a screenshot with no overlap of HUD, start tile, plots, villager or stall.
- [x] 4.3 Add ambient motion (sway on bushes, tufts and crops, pond shimmer) that never changes logical positions and is frozen during the break; verify a test that tile positions are unchanged over time and that the break test still passes.

## 5. Day cycle and shaders

- [x] 5.1 Add the day cycle (`FARM_DAY_LENGTH`, keyframed tint, counter increments at dawn, paused during the break, starts in daylight, fallback tint overlay when no shader); verify headless tests for rollover, break pause, day 1 start, and that growth timing is identical across a day boundary.
- [x] 5.2 Write `shaders/farm.glsl` and `src/FarmShader.lua` (single pass: day tint, sun and light shaft, thresholded bloom, glimmer, with `FARM_FX_*` uniforms, canvas owned by the farm, `pcall` compile and canvas creation, one-time log on failure); verify it compiles on the real LÖVE runtime under xvfb and that forcing a compile failure still renders and plays the farm.
- [x] 5.3 Keep the break correct under the shader (tint and bloom zeroed, corruption and fade fully visible) and the backrooms untouched; verify by screenshots at the start, mid-break and fade, and that `--placeholder-assets` still launches and plays.
- [ ] 5.4 Tune defaults conservatively (bloom, shaft, glimmer, day length, particle counts, sound level); verify by comparing screenshots with the pass on and off that sprites and text stay crisp.

## 6. Integration

- [ ] 6.1 Extend `tests/autotest.lua` with a full farm run (till, plant, water, harvest with fly-to-HUD, sell, buy, day counter, break into the backrooms); verify it passes and that debug features remain off in the packaged build.
- [ ] 6.2 Run `sh tests/check_all.sh` and `sh tools/package.sh` twice and verify all checks pass, the package hash is stable, and the backrooms visuals and carry-over are unchanged.
- [ ] 6.3 Record results in `openspec/changes/farm-game-feel-polish-tilling-watering/verification.md`, including screenshots of each requirement area; verify every spec scenario has a pass or an explicit manual-check note.

## Workflow follow-up

- Hand the shader and look review to the planned reviewer after section 5, before tuning.
- Archive the change after review and verify the archived result.
