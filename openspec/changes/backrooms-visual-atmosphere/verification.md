# Verification: backrooms-visual-atmosphere (section 6)

Real LÖVE 11.5 under Xvfb, Mesa llvmpipe (software renderer: compare configs on this machine only). Branch `feature/farm-to-backrooms`, review fixes in `8b10c68`.

## 6.1 Review notes and tuned defaults
Captures: `/workspace/qa/atmos/final/` (seeds 2026/7/1234 x presets bright/dim/single-bulb/near-dark + pit/ledge/gap/prop/nook, fallback/, perf/). Harness: `tests/backrooms_review.sh`, `tests/backrooms_shots.lua`.
Orchestrator review of the 5 reference images: wallpaper, acoustic grid, fluorescent depth and dim haze match; HUD crisp; no moving bands. Findings fixed:
- Near-dark plot/crop/exit too muted: `gameplayFloor` dim 0.62->0.72, single-bulb 0.58->0.78, near-dark 0.55->0.82; gameplay fog cap 0.35->0.2; exit colour {0.45,1,0.55,0.9}. Post pass unchanged, surrounding dread kept.
- Prop clutter / bag lookalikes: removed `sacks` and `crate` from the catalogue (nook concealment sacks from LevelGen unchanged); heights ~0.35-1.0 m; ~0.5 group chance per non-filler cell (0.15 filler), at most one extra hall prop (0.5). Still the separate RNG stream (`seed*31+977`) and unchanged exclusion zones, so layout/collision/seed layout are identical.
- Beige baseboard: added, one merged render-only model (0.14 m high, 0.03 m deep, both faces of every generated-level wall), no colliders; a unit test checks colliders unchanged and one extra model.
- Ledge shot: camera now 4.5 m before the module, obstacle and corridor both in frame.

## 6.2 Test run (`sh tests/check_all.sh`, run once): ALL CHECKS PASSED
- Unit/headless `tests/run.lua`: 197 passed, 0 failed (includes new "dressing review" test).
- Reachability: 84 assignments searched, 0 unexpected (the "look disabled" line is the mocked runtime having no `love.filesystem.read`; expected).
- Generated-level sweep seeds 1..70 x difficulties 1-3: 210 levels, 3150 searches, 0 failures. Orchestrator's independent run: PASS, seeds 71..140, 210 levels, 3150 searches; 175 unit checks; 2 playthroughs, 171 checks each.
- Pit rim: ok (2.53 / 2.54 m).
- Fallback ladder step (new in check_all): badshader == noshader 3/3, badpost != full 3/3.
- Plain + `--placeholder-assets` launches 8 s clean; autotest (look on, default) 171 checks 0 failed; placeholder 163 checks 0 failed (5308 frames, 88.5 s simulated).
- Package: two builds, same sha256 `ba15bbff317ddadc6ebe3351a8cca4a46716a031cc890a24e90efa09b336eb5e`, 301 files, no dev-only files. Artifact launches and autotests: 171 / 163 checks, 0 failed; `--debug` autotest 168 checks, 0 failed.

## Performance (mean ms/frame over 5 poses, seed 2026 L2, 3 reps)
plain (`--no-shader`) 3.70/3.65/3.55; high 13.72/12.99/12.49; medium 10.87/9.91/9.75; low 10.56/9.65/9.71; high with post forced off 9.14/8.81/8.73. Same as pre-review within noise (high 12.2-12.9, low 9.5-9.8): no regression, no optimisation work done. Post pass ~3.5-4 ms of high on software GL.

## Known limits
- Timings are llvmpipe software GL; real GPUs will differ. High is ~3.5x plain here; low/medium keep the post pass out of the cheap path only partly (low ~9.7 ms still includes lit shader).
- Near-dark crop (green bridge) is visible but still dim by design.
- Pickup pixels can differ run to run (they bob on the real clock).
- Baseboard only on generated levels (rooms with `data.meta`).
- Manual notes: no real-GPU or interactive human playthrough was done in this pass.

## Independent checks for the orchestrator (repo root, nothing else running)
- Perf: `sh tests/backrooms_review.sh perf /tmp/o-perf` then `cat /tmp/o-perf/perf/summary.txt`
- Fallback: `sh tests/backrooms_review.sh fallback /tmp/o-fb` (expect same x3 / DIFF x3)
- Readability: `sh tests/backrooms_review.sh shots /tmp/o-shots`, inspect near-dark plot-crop/exit/pickup, ceiling, prop and ledge shots
- Full playthrough: `AUTOTEST_OUT=/tmp/at xvfb-run -a -s '-screen 0 1024x1024x24' love . --autotest` (expect 171 checks, 0 failed)
- Everything: `sh tests/check_all.sh` (~25 min)
