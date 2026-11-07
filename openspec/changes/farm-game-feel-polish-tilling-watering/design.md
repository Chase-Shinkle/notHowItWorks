# Design

## Context

See `proposal.md` for motivation. Current state that shapes the approach:

- The farm renders through `push` into a 320x320 canvas, a 10x10 grid of 32 px tiles (row 1 HUD, row 10 hint). Plots are `FARM_PLOTS` (cols 2-4, rows 4-5), the villager is at (8,4), the stall at (8,7), the player starts at (3,6) facing the plot above. `FarmState:isWalkable` only blocks plots, the villager and the stall.
- Growth is a per-plot knife `Timer.every(FARM_STAGE_TIME)` inside `Farm.plant`; tests (`tests/run.lua`, `tests/autotest.lua`) drive it by advancing time and assume the first use on a fresh plot plants.
- `FarmState` draws sprites with `drawSprite` and rectangles, one `popups` list for text, and `renderHUD` draws seed bags, produce and `Nc` coins as text. The villager is the hero texture tinted at draw time.
- `shaders/` and `sounds/` are empty: every sound is a silent stub (`Assets.loadSound`) and no `love.graphics.newShader` exists on the farm. `lib/push.lua` supports `setShader` but the 3D backrooms bypasses push.
- Sprite pack: 16 fence pieces, one barn (~97x95 px), well, soil/stone/plant tiles, tool icons, mature berry bushes. No corn, trees or pond.
- Open specs for the farm live in the unarchived changes; `openspec/specs/` is empty.

## Goals / Non-Goals

**Goals:**
- A farm that looks and feels finished, using existing art, with all new behavior unit-testable headless.
- Rules (till, water, growth) stay pure and testable in `src/Farm.lua`; presentation (effects, shaders, dressing) lives in new modules.
- Nothing can leave the player stuck or a plot unreachable; nothing can blank the screen.

**Non-Goals:**
- New art beyond a recoloured villager sprite, backrooms visuals, break timing, carry-over, music, trees.

## Decisions

1. **Growth by elapsed time, not a Timer.** `Farm.plant` stops creating a `Timer.every`. Plots hold `progress` (stage-seconds), and `Farm.advance(plot, dt)` adds `dt * rate` where rate is 1 if watered else `FARM_UNWATERED_RATE` (0.5), computing the stage from progress. `FarmState:update` advances every growing plot. *Why*: a Timer interval cannot change rate mid-growth, and watering must keep progress. *Alternative*: keep the Timer and re-arm it on watering; rejected as it complicates pause and tests. Existing growth tests that run the Timer group are updated to call `update(dt)`.
2. **Plot state.** `Farm.newPlot` gains `tilled` and `watered` flags. Actions: `Farm.till`, `Farm.water` (pure, return `ok, reason`), and `Farm.plant` requires `tilled`. `Farm.harvest` clears `watered` and keeps `tilled`. `FarmState:interact` picks the action from plot state; the hint text and tool icon derive from one `FarmState:plotAction(plot)` helper so hints, icon and behavior cannot drift. No tool-selection UI: context-sensitivity keeps one-key play. *Alternative*: explicit tool keys; rejected as slower for a short game.
3. **Effects module.** New `src/Fx.lua` owns particles, flying pickups, popups-with-pop, a ticker and a squash tween table, all in virtual pixels and updated with `dt` (no knife Timers, so they never clear on the break Timer groups). `FarmState` creates one `Fx` per entry, emits through small helpers (`fx:burst(kind, x, y)`, `fx:fly(icon, from, to, onLand)`), and does not emit during the break. Effects are capped (particle count ceiling) so a spam of presses cannot degrade the frame rate.
4. **Coin ticker.** `FarmState` keeps `displayCoins` easing toward `gameData.coins` at a rate proportional to the gap, with a pulse scale while it differs. Real data is never delayed (tests and rules read `gameData`).
5. **Squash on stage.** `Farm.advance` reports stage changes (returns the new stage); `FarmState` starts a squash tween on that plot's draw scale (1.25x wide, 0.75x tall easing back, `Fx` owns the curve).
6. **Sounds generated, not sourced.** A new `tools/gen_sounds.py` synthesises short soft WAVs (till thud, plant pop, water splash, harvest pop, coin ticks, buy, quiet deny) with Python's `wave`/`struct` and no dependencies, writing to `sounds/`. The existing `Assets.loadSound` fallback makes a missing file silent. New keys: `till`, `water`, `coin`. Music stays a placeholder.
7. **Shader pass, single pass.** New `shaders/farm.glsl` and `src/FarmShader.lua`. `FarmState:render` draws the scene to its own 320x320 canvas, then draws that canvas through the shader to the push canvas. The shader does, in one pass: day tint (uniform `dayPhase`), sun (warm multiply plus a diagonal light shaft that drifts with `time`), bloom (an 8-tap blur of a luminance-thresholded sample added back), and glimmer (a time-varying hash-noise sparkle applied only above a brightness threshold, so ripe crops and pond highlights catch it, with no mask or second canvas). Strengths come from `FARM_FX_*` constants sent as uniforms. *Alternatives*: multi-pass bloom with a second canvas (nicer, more code, more risk); a shader per effect (more state switching). Compile and canvas creation are wrapped in `pcall`; on failure `FarmShader.enabled = false`, one log line, and the scene is drawn straight through. The break draws the scene normally and the shader is applied with tint and bloom zeroed so corruption stays crisp. *Caveat*: LÖVE shader code is GLSL ES-style; `love.graphics.newShader` is checked on the real runtime in the xvfb check.
8. **Day cycle.** `FarmState.dayTime` (seconds) advances in `update` outside the break, `dayPhase = (dayTime % FARM_DAY_LENGTH) / FARM_DAY_LENGTH` and `day = floor(dayTime / FARM_DAY_LENGTH) + 1`. The phase maps to a tint through a small keyframe table in constants (dawn warm, day neutral, dusk orange, night blue at about 0.7 brightness so it stays readable). Starts at phase just after dawn (full daylight). Without the shader, the same tint is applied as a translucent overlay rectangle so the cycle still shows.
7a. **Look pass after review (departure from 7).** The shader/look review (delegated by the owner to the orchestrator) found the single pass read flat: no perceptible depth, imperceptible shafts, sparse ground. The farm now uses a small multi-pass chain instead of one pass: the 320 px scene is blurred by `shaders/farm_blur.glsl` (separable 9-tap Gaussian) into 160 px (`nearTex`) and 80 px (`farTex`) soft copies and an 80 px thresholded bloom; `shaders/farm.glsl` composites a tilt-shift band that is sharp around the farmer (`focusY`, `FARM_FX_FOCUS_HALF/RAMP`), restrained bloom, a golden glow and fanning diagonal shafts from beyond the top-left corner (`FARM_FX_SUN_POS/GLOW`, `FARM_FX_SHAFT`), glimmer, a saturation lift and vignette, then the day tint. Six small passes plus one composite per frame. Every shader and canvas is still created under `pcall` with the same one-line fallback. The HUD bars are opaque, and the HUD, every piece of text (stall price, bubble, popups, hint) and the tool icon are drawn after the composite, including during the break, so the barn roof can no longer show behind "Day N". Dressing got denser from a second fixed-seed layer: extra tufts, code-drawn pixel flowers in the existing tuft style, the pack's `Tile -Plant - 01` ground tile and non-blocking native-size bush sprites. Ambient motes, petals and leaves are a pure function of `time` (frozen in the break). No new sprite art. Known trade-off: the stall's price label stays sharp when the stall is outside the focus band.
9. **World dressing as data.** `src/constants.lua` gets a `FARM_DECOR` table: lists of fence tiles, path tiles, bushes, pond tiles, the well, and the barn anchor, each with its blocking flag. Fence flanks the plot block on the left and right of both plot rows only, so row 3 above the plots stays open and every plot stays reachable (a closed ring would block the top plot row). The barn is drawn at native size anchored at cols 8-10, bottom at row 3's bottom edge, so its roof sits behind the HUD bar; cols 8-10 rows 2-3 are blocking. `FarmState:isWalkable` also consults a `blocked` set built from `FARM_DECOR`. A headless test breadth-first searches from the player start and asserts a reachable walkable neighbour for every plot, the villager and the stall. Ground variation uses a fixed-seed local `love.math.newRandomGenerator`, so the layout is identical every run and does not disturb the global RNG that corruption uses.
10. **Ambient motion** is a sine offset keyed to tile position and `time` on bushes, tufts and crops (a rotation or x-skew of a pixel or two), and animated highlight pixels on the pond. It never changes logical positions.
11. **Villager art.** `tools/make_villager.py` (Pillow, dev-time only) recolours the hero sprite's hair, adds an apron and a hat, and writes `graphics/characters/villager.png`, committed to the repo like the other assets. `Dependencies.lua` loads it as `villager` with the existing fallback, and the draw-time tint is removed. *Alternative*: a recolour shader; rejected, since a real sprite also shows up in screenshots and needs no shader.
12. **Tool icon on the farmer** uses existing icon sprites (shovel, seed bag, watering can, sickle) drawn small beside the farmer, chosen by `plotAction`.
13. **Display names.** `SEED_DISPLAY_NAMES = {beanstalk = 'beanstalk', pumpkin = 'pumpkin', vine = 'corn'}` and `SeedName(seedType)` in `src/Util.lua`. Every player-visible string in `FarmState` and `BackroomsState` goes through it. *Alternative*: rename the key; rejected for the reasons in the spec (data, allotments, tests, art keys).
14. **HUD layout.** The 320 px top bar must fit 3 seed slots, divider, 3 produce slots, coin icon with amount and the day counter. If it does not fit at the current slot widths, slot widths shrink (constants), not the font. Empty slots draw at reduced alpha.
15. **Docs and controls.** `README.md` and `RELEASE.md` are updated: tilling/watering, the 24 s unwatered timing, the day cycle, and generated sounds. The README line "A crop grows through 5 stages, one every 3 s" is corrected.

## Risks / Trade-offs

- [Tilling lengthens the first cycle and every test that assumes "first press plants"] → one extra press once per plot; update `tests/run.lua` and `tests/autotest.lua` explicitly and keep a test that a tilled plot plants on one press. Starting seeds and the 45 s idle break are unchanged, so a first sale still fits comfortably (till + plant + water, about 15 s watered).
- [Unwatered crops take 24 s] → the player is never blocked, and the hint prompts watering. Verify the whole first cycle stays well under the 3-minute check already in the tests.
- [Shader fails on some GPUs or drivers] → `pcall` compile plus fallback to a tint overlay; the xvfb launch check runs both with and without the shader forced off.
- [Bloom blurs pixel art] → thresholded and low strength, constants default conservative; compare screenshots with the pass off.
- [Barn under the HUD looks cluttered] → verify by screenshot; fallback is to draw the barn smaller at integer scale or move it to the left edge (layout is data).
- [Generated sounds sound cheap] → they are replaceable by dropping real files at the same paths; no code changes.
- [Scope is large for a jam] → tasks are ordered so each group ends in a playable build and the highest-value items (feel, characters, HUD) come before the shader and dressing.
- [Effects and the break] → effects stop spawning on `breaking`, and the day cycle and ambient motion are frozen so the existing break tests still hold.

## Migration Plan

No data migration. Ship by regenerating sounds and the villager sprite, running `sh tests/check_all.sh` and `sh tools/package.sh`. Rollback is a git revert.

## Open Questions

- Final tuning (day length, bloom strength, particle counts, sound loudness) is playtesting work; defaults are set in constants and none changes the specs.
