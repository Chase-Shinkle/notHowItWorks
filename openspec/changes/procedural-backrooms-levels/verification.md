# Verification: procedural-backrooms-levels

Scope: sections 1-4 (sections 1-2 first run, 3 and 4 below, pickups now also verified in the real runtime). Section 5 (solvability sweep, check_all, playtest) is untouched.
No `check_all.sh`, no package build. `openspec` CLI is not installed in this environment, so tasks were read from and checked in `tasks.md` by hand.

## Section 1: Generator foundation

Run: `love tests/love_runner tests/run.lua` (real LÖVE 11.5 LuaJIT, mocked LÖVE API).

| Task | Status | Evidence |
|------|--------|----------|
| 1.1 RNG + level seed | done | `levelgen 1.1` passes |
| 1.2 modules | done | `levelgen 1.2` passes (pit = pumpkin footprint/depth, ledge <= beanstalk height, 0.8 m plot offset, vine spans gap) |
| 1.3 chain + cell layout | done | `levelgen 1.3` passes: 40 seeds x 3 difficulties validate, connected, no overlapping cells, deterministic |
| 1.4 elevation/ceiling | done | `levelgen 1.4` passes over 300 seeds: ledge raises floor, headroom kept, gap after ledge at ledge height |

Design notes: modules are one 6 m cell; spine along +x, side cells at cy = +-1/+-2; walls are centred on cell boundaries.

## Section 2: Seeds and pickups

Run: `love tests/love_runner tests/run.lua` -> 170 passed, 0 failed (full headless unit file, mocked LÖVE).

| Task | Status | Evidence |
|------|--------|----------|
| 2.1 critical/extra seeds, `pickups`, `seedTypes` | done | `levelgen 2.1`: 500 seeds, prefix sufficiency (computed from pickup coordinates against region reachability) and critical seed never behind its own obstacle |
| 2.2 self-check + derived-seed regeneration | done | `levelgen 2.2`: mutated candidate (critical seed removed) rejected, attempt 1 with derived seed used |
| 2.3 `Room.validate` / `Room:init` pickups + seedTypes | done | `levelgen 2.3`: bad seed, tier, pos, seedTypes rejected; Room builds pickups |
| 2.4 pickup billboards + collection | done (mock) | `levelgen 2.4`: +1 seed, pickup removed, message names seed, no double collect, draw runs. Billboards are `seedbag-<type>` bobbing sprites. Mock-only here; real-runtime check closed in section 4 below |
| 2.5 `visibleSeedTypes` | done | `levelgen 2.5`: pumpkin+vine level lists only those; allotment fallback unchanged |

Targeted physical spot check (not the section 5 sweep): `love tests/love_runner qa/levels/spot_reach.lua`
(script kept in /workspace/qa/levels/spot_reach.lua), 7 seeds over difficulties 1-3 using `tests/reach.lua`:
exit unreachable with no crops, reachable with the intended crops, 7/7 ok.

## Section 3: Uproot

Run: `love tests/love_runner tests/run.lua` -> 172 passed, 0 failed.

| Task | Status | Evidence |
|------|--------|----------|
| 3.1 uproot key (X) + `Room:uproot`/`Crop:remove` | done | `uproot 3.1`: wrong pumpkin planted on pit plot, uprooted while growing (growth cancelled, never completes) and when grown (collider gone); plot takes a vine afterwards; pumpkin count unchanged by uprooting; X key drives it |
| 3.2 refusals | done | `uproot 3.2`: tutorial demo crop refused (message "part of the lesson"); standing on top of / inside a grown pumpkin refused with "Step off it first" and crop kept; allowed once clear at the rim |

Standing check: player box vs the crop's full volume grown by `BACKROOMS_UPROOT_MARGIN` (0.12 m) on all sides.

## Section 4: Sequence and reset

Runs: `love tests/love_runner tests/run.lua` -> 175 passed, 0 failed (real LÖVE, mocked API);
`AUTOTEST_OUT=/workspace/qa/levels/autotest xvfb-run -a -s '-screen 0 1024x1024x24' love . --autotest`
-> 171 checks, 0 failed, exit 0 (real window, real g3d, real input handlers; run seed fixed 4242, override `AUTOTEST_RUN_SEED`).

| Task | Status | Evidence |
|------|--------|----------|
| 4.1 sequence, difficulty, run seed | done | `sequence 4.1`: levels = tutorial + `BACKROOMS_GENERATED_LEVELS` (3); level seed == `LevelGen.levelSeed(runSeed, i)`; obstacles 2,3,4 non-decreasing and last > first; same run seed -> identical boxes/pickups, other seed differs; run seed logged `[backrooms] run seed N`; `love . --run-seed=N` flag; default is random per run |
| 4.2 stock policy | done | `sequence 4.2`: tutorial still topped up from farm seeds; generated levels start `0/0/0` even with leftovers or as a first room; `RoomStartingSeeds` returns zero for `generated = true` data |
| 4.3 reset | done | `sequence 4.3`: all pickups collected + crop planted, then R: same level data, same collider count and exit, pickups respawned, crops cleared, stock back to zero. Also in autotest per generated level |
| 4.4 ending + full flow | done | autotest: farm -> break -> tutorial (real climb) -> generated levels 2,3,4 solved in chain order (pit, gap, ledge all appear) -> ending -> start. Unit: last exit changes to `ending` once |

Autotest scripted generated playthrough (reusable): per level it teleports to the critical pickups and to the foot of each
obstacle (physics reachability over 200+ seeds is section 5), but selecting, planting, growth, climbing, crossing, collision, exit
and reset are real. A pickup lying within 0.9 m of the spawn is collected on arrival; checks account for that.

Real-runtime pickup screenshots (closes the 2.4 mock-only gap), in `/workspace/qa/levels/`:
`16-level2-pickup-a.png`, `16-level3-pickup-a.png`, `16-level4-pickup-a.png` (seed bag billboards on the floor, readable),
`17-level3-collected.png` (message + HUD count after collecting), `18-level3-first-crop.png`, `15-level4-arrival.png`;
full autotest set in `/workspace/qa/levels/autotest/`.

Notes: old puzzle rooms 2-3 in `rooms.lua` are unused by the game now; unit tests reach them via `BackroomsState.roomsOverride`
(the test-only override from the design). The autotest no longer plays them in the real runtime.

## Not done / pending

- Section 5 (200+ seed physical sweep, check_all.sh, package builds, playtest) unchecked.
- No check_all.sh or package build in this pass (only the unit file and the autotest).
- Atmosphere/visual change not started.
