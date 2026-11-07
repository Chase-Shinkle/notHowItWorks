# Verification: farm-game-feel-polish-tilling-watering

**Status: reviewer checkpoint after task 5.3.** Sections 1-4 and tasks
5.1-5.3 are implemented and checked. **Task 5.4 (tuning) and all of section 6
are not started.** They wait for the shader and look review by Chase. No
reviewer approval has been given or is claimed here. The change is not
archived.

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
| **5.4 Tuning** | **pending reviewer** | Not started. Defaults in `src/constants.lua` (`FARM_FX_*`, `FARM_DAY_LENGTH`, `FX_BURSTS`, `FARM_SFX_VOLUME`) are first values only |
| **6.1-6.3** | **pending reviewer** | Not started |

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
