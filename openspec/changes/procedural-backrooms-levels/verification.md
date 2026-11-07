# Verification: procedural-backrooms-levels

Scope: sections 1-4 (sections 1-2 first run, 3 and 4 below). Section 5 (solvability sweep, check_all, playtest) is untouched.
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
| 2.4 pickup billboards + collection | done (mock) | `levelgen 2.4`: +1 seed, pickup removed, message names seed, no double collect, draw runs. Billboards are `seedbag-<type>` bobbing sprites; visual look not screenshotted |
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

## Not done / pending

- Sections 3 (uproot), 4 (sequence, stock policy, reset, ending), 5 (sweep over hundreds of seeds, check_all, playtest) unchecked.
- No full check_all.sh, no package build, no autotest, no real-window screenshot run in this pass.
- Generated levels are not yet wired into the sequence (section 4); `loadRoom(1)` would still apply the tutorial top-up.
- Atmosphere/visual change not started.
