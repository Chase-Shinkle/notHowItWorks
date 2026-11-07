# Verification: farm-game-feel-polish-tilling-watering

**Status (final, run 2): tasks 1.1-6.1 are done. Task 6.2 is NOT satisfied:
`sh tests/check_all.sh` ran once and reported SOME CHECKS FAILED (one stale
unit assertion, see "Final results"). Task 6.3 is recorded here. The change is
not archived.** The sections below up to "Look pass" are the earlier reviewer
checkpoint after task 5.3 and are kept as history. The look pass, tuning and
blur fix are recorded after them. All code was written by Claude Code.

Starting commit: `a428d0d` on `feature/farm-to-backrooms`. All code was
written by Claude Code.

## Commits

| Section | Commit | Summary |
|---|---|---|
| 1 | `722a272` | Display names (vine reads as corn), till / water / elapsed-time growth, `plotAction`, test and doc updates |
| 2 | `a128b16` | `src/Fx.lua`, action bursts and pops, flying harvests, coin ticker, squash, generated sounds |
| 3 | `00d7ccf` | Villager sprite, tool icon, sale bounce, rebuilt top bar, `tests/farm_shots.lua` harness |
| 4 | `c72b569` | `FARM_DECOR` dressing, walkability, ground variation, three soil looks, ambient sway |
| 5.1-5.3 | `95604e2` | Day cycle, `shaders/farm.glsl` + `src/FarmShader.lua` with fallback, break under the pass |

The commit that adds this file comes after these.

## Per-task status

| Task | Status | Evidence |
|---|---|---|
| 1.1 Display names | done | `names: vine reads as corn in every farm hint, popup, villager line and shop hint`; `names: backrooms prompts and messages say corn, never vine`; autotest checks the room 2 and 3 HUDs read `corn x` |
| 1.2 Till / water / advance | done | `plot care: watered crops mature in 12 s, unwatered in 24 s, never blocked`; `plot care: watering mid-growth keeps progress...`; `Farm rules: plant/harvest/sell return values` (untilled, tilled, occupied, not-growing) |
| 1.3 `plotAction` | done | `plot care: the hint, the action and the result agree for every plot state`; `plot care: tilling and watering after a sale keep the idle countdown; the break freezes growth` |
| 1.4 Tests and docs | done | run.lua / autotest.lua updated for till -> plant -> water; README and RELEASE.md growth and controls text; first cycle < 30 s watered and < 40 s unwatered (both < 3 min); check_all passed |
| 2.1 Fx module | done | `fx: bursts clean up...` (incl. cap and global RNG untouched), `fx: the coin ticker converges...`, `fx: squash and pop tweens...`, `fx: no effects remain a few seconds after input stops` |
| 2.2 Emit on actions | done | `fx: every farm action emits an effect; the break emits none` |
| 2.3 Fly to HUD, ticker | done | `fx: a harvest counts on the same frame, flies to its slot and pulses it on landing`; `fx: selling ticks the shown coins up with sparkles; buying ticks them down` |
| 2.4 Squash, maturity sparkle | done | `fx: a stage change starts a squash on that crop which returns to scale 1` |
| 2.5 Sounds | done | `python3 -I tools/gen_sounds.py` writes 9 WAVs (byte-identical on a re-run); real launch logs placeholder lines only for the two music slots; `sound:` tests (each action plays its own file, missing file runs silently) |
| 3.1 Villager sprite | done | `characters: the villager has its own sprite file, drawn untinted`; real runtime: villager.png differs from the hero in 90 pixels; screenshot |
| 3.2 Bounce, tool icon | done | `characters: the tool beside the farmer follows the faced plot`; `characters: the villager bounces briefly...`; screenshots of all four tools |
| 3.3 Top bar | done | `hud: ... nothing overlaps with three-digit counts` (mock font and 5 px/char worst case); real-font check on LÖVE 11.5: 19 elements, no overlaps; `hud: a new farm shows day 1; empty slots dim...`; screenshot |
| 4.1 Decor and walkability | done | `decor: solid dressing blocks movement...`; `decor: from the start, every plot, the villager and the stall have a reachable walkable neighbour` (BFS) |
| 4.2 Render dressing | done | `decor: nothing sits on the HUD rows, start tile, plots, villager or stall...`; `decor: ground variation is identical on two entries...`; `decor: three soil looks...`; screenshots |
| 4.3 Ambient motion | done | `decor: ambient sway and shimmer move with time but tile positions never change; frozen in the break`; existing break tests pass |
| 5.1 Day cycle | done | `day:` tests (day 1 daylight start, rollover at dawn, tint keyframes, night >= 0.65 brightness, growth same across a boundary, frozen in the break); fallback overlay test |
| 5.2 Shader | done | Compiles on real LÖVE 11.5 under xvfb (Mesa llvmpipe, OpenGL 4.5), also from the packaged .love; a real GLSL compile error falls back with one log line and the farm plays (till, plant, water by real input); `shader:` headless tests (pipeline order, uniforms from constants, zeroing one constant changes only that uniform) |
| 5.3 Break under the pass | done | `shader: during the break the pass is plain and corruption and the fade are drawn on top of it`; `shader: the backrooms never uses the farm pass`; screenshots of mid-break and fade (pass on and off); `--placeholder-assets` launch and autotest pass |
| 5.4 Tuning | done | See "Task 5.4" below: defaults changed, crispness measured on real captures; volume not human-verified |
| 6.1 Autotest farm run | done | `tests/autotest.lua` full farm run (128 checks from source, 120 with `--debug` off paths); debug features off in the package |
| **6.2 check_all and package twice** | **FAILED (open)** | check_all: 1 unit failure; package hash stable. See "Final results" |
| 6.3 Record results | done (this file) | Scenario table below |

## Test results (exact, from the last runs)

`sh tests/check_all.sh` after the section 5.1-5.3 changes: **ALL CHECKS PASSED**.

- Unit / headless (`tests/run.lua`): **161 passed, 0 failed** (baseline at
  `a428d0d` was 124 passed. 37 tests were added, and the existing farm tests
  were updated for till -> plant -> water.)
- Reachability sweep: 84 assignments searched, 0 unexpected.
- Pit-rim measurement: ok (room 2 span 2.53 m, room 3 span 2.54 m).
- Plain launch, 8 s: ok (`love .` and `--placeholder-assets`).
- Autotest from source: 123 checks, 0 failed; `--placeholder-assets`: 115
  checks, 0 failed.
- Package: 295 files, two builds with the same sha256
  `ceffd496fa9b9cda78461f21fa8d875b71dc559d66efd41e1fa3ec7bc0aa5999`. Contents
  are ok (no dev-only files; `tests/farm_shots.lua` and `tools/` are
  excluded; `shaders/farm.glsl`, `sounds/*.wav` and
  `graphics/characters/villager.png` are included).
- Artifact launch and autotest: 123 / 115 checks, 0 failed; artifact with
  `--debug`: 120 checks, 0 failed. `[farm-shader] post-process pass enabled`
  appears in the source, placeholder and artifact autotest logs.
- Screenshot harness (`love . --farm-shots`): pass on **25 checks, 0
  failed**; `--no-shader` **21 checks, 0 failed** (the forced-compile-failure
  scene is skipped there because the pass is already off);
  `--placeholder-assets` subset **10 checks, 0 failed**.

## Reviewer screenshots: `/workspace/qa/farmfeel/`

All are real `love.graphics.captureScreenshot` captures of the presented
frame from LÖVE 11.5 under `xvfb-run -a -s '-screen 0 1024x1024x24'`
(800x800 window; the 320x320 virtual view is scaled 2.5x by push). `-zoom`
files are nearest-neighbour crops of the same capture. `-shader-on` means the
default path and `-shader-off` means `--no-shader`, which is the fallback path.

Suggested review order:

1. `farm-start-daylight-shader-on.png` / `-shader-off.png`: fresh farm, day
   1, daylight (sun tint and faint diagonal shaft visible on).
2. `day-dusk-shader-on.png`, `day-night-shader-on.png`, `day-dawn-shader-on.png`
   (and `-shader-off` versions with the overlay fallback).
3. `ripe-crops-daylight-shader-on-zoom.png` vs `-shader-off-zoom.png`: bloom
   and glimmer on the ripe markers; `pond-closeup-shader-on-zoom.png`.
4. `break-mid-shader-on.png`, `break-fade-shader-on.png` (and `-shader-off`),
   then `backrooms-after-break-shader-on.png`.
5. `tool-1-shovel…`, `tool-2-seedbag…`, `tool-3-watering-can…`,
   `tool-4-sickle…` `-shader-on-zoom.png`: tool icon close-ups.
6. `hud-three-digit-counts-shader-on-zoom.png`: 999 seeds / produce / coins,
   day 999, selected-and-empty slot dimmed but outlined.
7. `villager-next-to-hero-shader-on-zoom.png`,
   `villager-sale-bounce-shader-on-zoom.png`.
8. `soil-three-looks-shader-on-zoom.png`: untilled | tilled | watered.
9. `compile-failure-fallback.png`: frame drawn after a real GLSL compile
   failure.
10. `*-placeholder-assets.png`: farm start, tools and break with every asset
    forced to its fallback.

Logs: `run-shader-on.log`, `run-shader-off.log`, `run-placeholder-assets.log`.

### Test setup used for the captures

The harness is `tests/farm_shots.lua`, loaded only by `love . --farm-shots`.
It is dev-only and not packaged. Each scene starts a fresh farm with
`gStateMachine:change('farm', NewGameData(...))` and runs real frames.
Actions use the game's own `love.keypressed`. When a state would take long to
reach by play, the scene sets it directly, and the log line for that shot says
so:

- **villager**: farmer placed on the tile left of the villager; one real E sale for the bounce.
- **tools**: real E presses for till, plant and water; growth is then advanced to mature directly for the sickle shot.
- **hud**: counts, coins and day set to three digits directly.
- **soil, ripe, day-cycle**: plot states and crops set directly; for the day-cycle shots the clock is set to phases 0.03 / 0.66 / 0.84.
- **compile-failure**: the shader source is replaced at runtime with GLSL that fails to compile, then restored.
- **break**: a real over-sell by E after `hasSold = true` data.

The mouse is parked off the field.

Commands:

```
SHOTS_OUT=/workspace/qa/farmfeel SHOTS_SUFFIX=-shader-on  xvfb-run -a -s '-screen 0 1024x1024x24' love . --farm-shots
SHOTS_OUT=/workspace/qa/farmfeel SHOTS_SUFFIX=-shader-off xvfb-run -a -s '-screen 0 1024x1024x24' love . --farm-shots --no-shader
SHOTS_ONLY=farm-start,tools,break SHOTS_OUT=/workspace/qa/farmfeel SHOTS_SUFFIX=-placeholder-assets xvfb-run -a -s '-screen 0 1024x1024x24' love . --farm-shots --placeholder-assets
```

## Deviations and notes for the reviewer

- **The `openspec` CLI is not installed** in this environment. The apply
  workflow was followed by hand: I read the proposal, design, specs and tasks
  and ticked the checkboxes in `tasks.md` directly.
- **Extra sound key `buy`**: task 2.5 lists the new keys `till`, `water` and
  `coin`. It also generates `buy.wav`, and the spec wants a buy sound, so I
  added a `buy` key; buying used to play `sell`.
- **Ground variation RNG**: instead of `love.math.newRandomGenerator` (design
  9), the ground variation and the particles each use a small
  fixed-seed local generator. It works the same under the headless mock (which
  has no `love.math`), and it never touches the global `math.random`. Tests
  check that.
- **Watered look**: an early version used the pack's "Water Soil" prop. It
  read as a blue blob on the crop, so I replaced it with darker soil, damp
  patches and sheen pixels drawn in code.
- **Path tile**: uses the pack's stone-soil tile, so it reads differently
  from the plots.
- **Barn roof under the HUD**: as designed, the barn's roof is behind the
  translucent top bar and shows through it at the top right. The design lists
  this as a look risk; please judge it in the screenshots.
- **What the pass covers**: the field, characters, tool icon and particles go
  through the pass. The speech bubble, popups, HUD and flying pickups are
  drawn after it, so text stays crisp and is not tinted at night. During the
  break the scene (including the HUD) goes through a neutral pass, and the
  corruption and fade are drawn on top of it.
- **Bloom/shaft visibility**: with the first `FARM_FX_*` values the shafts
  are subtle and the bloom shows mainly on the ripe-crop markers and the pond
  highlights. Those values are what task 5.4 will tune after review.
- **Tool icon**: I moved it from over the head to the farmer's right side and
  set it to 12 px after looking at the first capture.
- **Git identity**: no git user was configured, so commits use the repo's
  existing author identity via per-command `-c user.name/-c user.email`.
  Global and repo config were not changed.
- The `fx` field on FarmState still holds the break's shake / corruption /
  fall values (existing tests read it). The new effects module is
  `FarmState.juice`, and `FarmState.popups` aliases its popup list.

## Spec scenario coverage at this checkpoint

Every scenario is covered for the parts in sections 1-5.3, either by a
headless test, a real-runtime check or a screenshot listed above. Two items
are left for the reviewer: the subjective look (crispness with the pass on
compared with off; whether the bloom, shafts and glimmer are visible enough)
and the barn-under-HUD layout. Section 6.3 will produce the full
scenario-by-scenario table after the review.

## Look pass after the shader/look review (round 1)

The owner handed the shader/look review to the orchestrator. Round 1 found: flat top-down look, no perceptible depth blur, imperceptible shafts, sparse ground, and the barn roof showing through the top HUD near "Day 1". Changes are in design.md decision 7a. That decision moves away from the single-pass design to a small chain of downsampled blur and bloom passes.

- **Reference images:** the instructions pointed to `/workspace/qa/farmfeel/reference/ref1-village-festival.jpg` and `ref2-countryside-path.jpg`. Neither file exists on this machine (no `reference/` directory, no match anywhere on the filesystem). The work follows the orchestrator's written description of them instead.
- **HUD bug:** the cause was a top bar at 65 % alpha, plus the HUD being drawn inside the pass during the break. Both bars are now opaque. The HUD, all text and the tool icon are drawn after the composite in the normal and break render paths. Headless tests now assert this:
  - no `print`/`printf` before the composite (normal and break);
  - the opaque bar is drawn after it;
  - six blur steps run;
  - the break zeroes tilt, saturation, vignette and glow.
- **Tests:** `love tests/love_runner tests/run.lua` gives **161 passed, 0 failed**. Real LÖVE 11.5 under xvfb `--farm-shots` gives **26 checks, 0 failed** with the shader on, **22, 0 failed** with `--no-shader`, and **26, 0 failed** with `--placeholder-assets`. The forced compile failure still falls back and plays. The full `check_all.sh` run is recorded under task 6.2.
- **Screenshots:** `/workspace/qa/farmfeel/final/` holds `final-*` shots for shader on, off and placeholder, plus `final-compare-*` before/after images (baseline 577d3e6 on the left). The baseline is kept in `/workspace/qa/farmfeel/baseline-577d3e6/`. The new scene `focus-follows-farmer` walks the farmer up next to the barn using real arrow presses.
- **Status:** all checks are scripted (automated runs and screenshots). No human has playtested the new look.
- **Known trade-offs:**
  - the stall price label stays sharp when the stall is out of focus;
  - the focus band follows the farmer, so plots 2–3 rows away soften slightly;
  - the blur is computed at 160/80 px, so up close it shows as soft blocks after push's nearest 2.5x upscale.

### Task 5.4: tuning (scripted, after the look pass)

Defaults changed: `FARM_FX_GLIMMER` 0.5 → 0.4, harvest burst 14 → 12 particles, water burst 12 → 10, `FARM_SFX_VOLUME` 0.6 → 0.5. These were unchanged: bloom 0.55 at threshold 0.66, shafts 0.30, `FARM_DAY_LENGTH` 90 s (a first loop runs into dusk). Look values: see constants.

Crispness was measured on real LÖVE captures of `farm-start-daylight`, comparing shader on and `--no-shader`. The metric is mean horizontal luminance edge energy over each window-pixel region (on / off):

| Region | On / off |
|---|---|
| HUD top bar | 1.00 (identical) |
| Hint bar | 1.00 (identical) |
| Farmer (focus band) | 0.94 |
| Villager (focus band) | 0.98 |
| Barn (background) | 0.32, softened on purpose |
| Bottom row (foreground) | 0.52, softened on purpose |

The small drop inside the focus band comes from the grade (vignette, warm multiply), not from blur. Captures are in `/workspace/qa/farmfeel/final/final-tuned-5.4-*`. Unit tests: 161 passed, 0 failed. Shots: 9 checks, 0 failed on each of on and off. The volume is set by value only; nobody listened to it, so it is not human-verified.

## Blur fix (commit `b8c80a0`) and its review

The second look pass blurred the top/background and bottom too little and
unevenly. `b8c80a0` adds a second Gaussian round, a 4-tap upsample and a
smootherstep focus falloff.

- **Orchestrator review (not a fresh inspection by Claude):** the orchestrator
  reviewed the AFTER capture against
  `final/final-tuned-5.4-farm-start-daylight-shader-on.png`: top/background and
  bottom blur smoother, focus sprites and HUD crisp, golden shafts preserved.
  Accepted, no further visual tuning.
- **Correction on the before images:** the run 1 "before" images were made
  from `baseline-577d3e6` (before the HD-2D look pass), not from the commit
  just before the blur fix. In `/workspace/qa/farmfeel/blurfix/`,
  `before-farm-start-daylight.png` and `before-blurred-top-zoom.png` /
  `before-blurred-bottom-zoom.png` were replaced in run 2 with the real
  pre-blur-fix frame, `final/final-tuned-5.4-farm-start-daylight-shader-on.png`
  (a copy, and 2x nearest-neighbour crops at the same geometry as the after
  zooms: top = x0 y16 400x224, bottom = x0 y576 400x208, both 800 px wide).
  Crop geometry was found by exact pixel match against the after zooms. No game
  launch was needed. Statements in run 1 notes that the baseline was the
  pre-blur-fix state are wrong.
- **Reference images:** the orchestrator read the reference photos in an
  earlier round. Claude's round 1 note above says they were not on this
  machine and the look followed the orchestrator's description. Both are true:
  Claude did not see them.

## Final results (run 2, at `b8c80a0` plus this file)

`sh tests/check_all.sh` was run exactly once and not rerun:
**SOME CHECKS FAILED.**

- Unit / headless (`tests/run.lua`): **160 passed, 1 failed.** Failing test:
  `shader: the scene goes into the farm canvas and through the pass; text and
  HUD are drawn after it`, `tests/run.lua:3317: six blur steps: got 10, want
  6`. Cause (not debugged further): the blur fix added a second Gaussian round,
  so the assertion that expects six blur steps is stale and the chain now makes
  ten. This is a test expectation to update to the new design, not shown to be
  a rendering defect. It is NOT fixed here, because the instruction was to run
  the suite once and not start debugging.
- Reachability sweep: 84 assignments searched, 0 unexpected.
- Pit-rim measurement: ok (room 2 span 2.53 m, room 3 span 2.54 m).
- Plain launch, 8 s: ok.
- Autotest: source **128 checks, 0 failed**; `--placeholder-assets` **120, 0
  failed**; packaged artifact 128 and 120, 0 failed; artifact with `--debug`
  **125, 0 failed** (3521 frames).
- `sh tools/package.sh` twice: 296 files, 2,117,424 bytes, identical sha256
  `7968aa1d8985c70dcac257b8cde2b1d7d05af92037e71c0de592c11b266a641b`
  (hash stable).
- Backrooms visuals and carry-over: the backrooms autotest checks (rooms 1-3
  HUD, screenshots 07-17, carry-over, ending) all passed, and the shader test
  `the backrooms never uses the farm pass` passed. No backrooms files changed.
  Compared by checks, not by a human.
- **6.2 stays unchecked** until the stale assertion is updated and a clean
  check_all run is recorded.

## Scenario-by-scenario result

"scripted" means a headless test, real-runtime scripted run or scripted
capture. No human playtested anything. Audio and real-GPU look are manual.

| Spec | Scenarios | Result |
|---|---|---|
| crop-display-names | Hint and popups; HUD and shop; Backrooms HUD; Data unaffected | pass, scripted (`names:` tests, autotest room 2/3 HUD lines) |
| farm-hud | Divider present; Dim and restore; Coin counter; Initial day; Large counts | pass, scripted (`hud:` tests, real-font layout check, `hud-three-digit-counts` captures) |
| farm-plot-care | all 11 scenarios (till, plant, replant, water, already watered, lost on harvest, both timings, mid-growth, hint match, after first sale) | pass, scripted (`plot care:` tests) |
| farm-world-dressing | Landmarks visible; barn blocks; path walkable; reachability; stable layout; idle motion; three soil looks | pass, scripted (`decor:` tests, BFS, `soil-three-looks` capture). Manual: barn roof showing under the top bar was fixed in round 1 by an opaque bar |
| farm-shaders | Pass active; Compile failure; Placeholder-assets launch; Break visible | pass, scripted (real LÖVE 11.5 under xvfb, `compile-failure-fallback`, `--placeholder-assets` runs). The unit test for the pass order (six steps) now fails as a stale expectation, see above |
| farm-shaders | Tuning; Crisp sprites | pass by measurement (edge-energy table in 5.4: HUD 1.00, farmer 0.94, villager 0.98). **Manual-check note:** the subjective look on a real GPU was reviewed by the orchestrator from captures only |
| farm-day-cycle | Day rolls over; Night readable; Growth unaffected; Frozen during the break; Start of run | pass, scripted (`day:` tests, `day-dusk/night/dawn` captures) |
| farm-characters | Told apart in a screenshot; Player look; Tool changes with state; Sale reaction | pass, scripted (`characters:` tests, villager and tool captures) |
| farm-juice | Harvest burst; Effects clean up; Fly and count; Sale ticks up; Spending ticks down; Stage change; Missing sound; Break plays cleanly | pass, scripted (`fx:` and `sound:` tests, autotest farm run) |
| farm-juice | Distinct cues | **manual-check note:** nine distinct WAVs are generated and each action plays its own file (scripted). Whether they sound distinct and at a good level was not heard by anyone |

## Screenshots per requirement area

All under `/workspace/qa/farmfeel/` (area: files): world dressing and look:
`final/final-farm-start-daylight-*`, `final/final-focus-follows-farmer-*`,
`blurfix/*`; day cycle: `final/final-day-{dawn,dusk,night}-*`; shaders and
fallback: `final/final-compile-failure-fallback-*`, `*-placeholder*`; break:
`final/final-break-*`, `final/final-backrooms-after-break-*`; HUD:
`final/final-hud-three-digit-counts-*`; characters and tools: `tool-*`,
`villager-*`; soil: `soil-three-looks-*`; juice (ripe markers, pond):
`ripe-crops-*`, `pond-closeup-*`. All captures are scripted. Effects in motion
(bursts, flying pickups) are covered by tests, not stills.

## Deviations (this run)

- 6.2 is not complete: one stale unit assertion fails (see above).
- check_all was run once as instructed, so no second run confirms a fix.
- The before images for the blur fix were corrected as described above.
- Audio and the real-GPU look were not human-checked. Nothing is archived.
