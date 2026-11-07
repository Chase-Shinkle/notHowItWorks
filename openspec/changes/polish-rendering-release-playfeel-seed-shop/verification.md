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

## 3. Pit-plot reach (M3)

**Deviation from design.md decision 3 (reach value).** The design suggests
about 2.6 m. Measured with the real controller (`tests/rim.lua`), the
player's feet fall off the spawn-side rim at x = -3.96 (Room 2) and -5.96
(Room 3). That is 1.26 m from the pit plot centre, because the plot sits in
the middle of the 2.6 m wide pit. Reach is measured from the plot centre, so:

| reach | plantable floor span | 1.0 m back from rim | 2.0 m back from rim |
|-------|----------------------|---------------------|---------------------|
| 1.8 (before) | 0.53 m | no | no |
| 2.6 (design) | ~1.34 m | yes | **no** (3.26 m from the plot) |
| 3.8 (chosen) | 2.53 m (Room 2), 2.54 m (Room 3) | yes | yes |

Task 3.1 (plant from 2.0 m back) and task 3.3 (span of at least 2.5 m)
cannot both be met at 2.6 m, so the pit reach is
`BACKROOMS_PIT_PLANT_RANGE = 3.8`. This meets the spec's "within at least
2.5 m" and "1.0 m or more back from the rim". Pit geometry is unchanged. In
Room 3 the whole 3 m spawn floor can now reach the pit, including the spawn
itself.

- 3.1 Plots take an optional `reach` (validated as a positive number,
  default `BACKROOMS_PLANT_RANGE`), used by `Room:nearestPlot`. Only the Room 2
  and Room 3 `pit` plots set it. New headless tests:
  - Per-plot reach and default reach; the nearest plot wins when both are in
    reach; the height limit still applies; an invalid reach is rejected.
  - Through `BackroomsState` in Rooms 2 and 3, standing at 1.0 m and 2.0 m
    back from the rim: on the floor, pit targeted, "E / click: plant pumpkin"
    prompt drawn, E plants a pumpkin (one seed used), it grows solid and the
    player never falls.
  - Walking from the Room 2 spawn, the pit is targeted before x = -5.9.
  - Room 3 neighbours: spawn gives pit, the ledge face and mid floor B give
    foot, the ledge gives lip (not the pit 3.6 m below).
- 3.2 `tests/reachability.lua`: 84 assignments searched, 0 unexpected. Every
  room is solvable only with its intended combination, which is unchanged.
  The extra reach changes only where a seed can be planted from, not where
  crops grow, and the reachability search covers every crop assignment. The
  floor-B strip of Room 3 at x < -3.25, where the pit is nearer than foot,
  already targeted the pit with the old 1.8 m range, so foot and lip resolve
  as before. The autotest now plants the Room 2 pit from 2.47 m back from the
  rim (twice, around the reset) and the Room 3 pit from 1.53 m back. The full
  playthrough passes (107 checks, 0 failed); screenshot
  `09b-room2-pit-prompt.png` shows the prompt from there.
- 3.3 `tests/rim.lua` is new (no `scripts/rim.lua` existed in the repo) and
  runs in `check_all.sh`. Room 2: stands up to x = -3.96, pit plantable over
  x = [-6.49, -3.96] (2.53 m). Room 3: up to x = -5.96, plantable over
  [-8.50, -5.96] (2.54 m). The pit is targeted at 1.0 m and 2.0 m back in
  both rooms. No pit geometry was changed.

## 4. Seed stall (M4, farm)

- 4.1 `FARM_SHOP = {col = 8, row = 7}` and `SEED_PRICES` (beanstalk 2,
  pumpkin 4, vine 3; sale values 3, 5, 4) are in `src/constants.lua`. The pure
  `Farm.buySeed(gameData, seedType)` returns `ok, seedType, price`, or
  `false, 'no-coins' | 'unknown-seed', price` with nothing changed. Headless
  tests cover: every price is below its sale value; success changes only
  coins and that seed (crops, `hasSold` and `hasBroken` untouched); not enough
  coins changes nothing; an unknown type is refused; a plant -> harvest ->
  sell -> rebuy cycle leaves more coins (+1) for every type.
- 4.2 The stall is a new `'shop'` target in `FarmState:targetAt`, so it blocks
  movement and gets the facing and hover highlights. `interact` buys one seed
  of the selected type: a `sell` sound and a `+1 <type> -Nc` popup, or a
  `deny` sound and a `need Nc` popup. During the break `interact` returns
  nil, so the stall is disabled. The hint bar shows `[E] buy <type> seed (Nc)`
  or `<type> seed costs Nc (have Mc)` when the stall is faced *or hovered*.
  Drawing: a striped awning and counter, the selected type's seed-bag sprite
  (existing art) and its price. Headless tests check the stall is on its own
  field tile (not a plot, the villager, the start tile or a HUD row), its four
  neighbours are walkable, the start hint is still `[E] plant beanstalk`, a
  keyboard buy and denial, a mouse hover hint and highlight, a click buy and
  denial, and planting a bought seed. On the real runtime the autotest walks
  to the stall, checks the hint, hovers it with the real cursor
  (`love.mouse.setPosition`) and buys by click (3 -> 1 coins). It then presses
  E with 1 coin (refused), walks to plot (4,5), plants the bought seed and
  over-sells. Screenshot `04b-farm-stall.png` (plus `-zoom`) shows the stall,
  the price, the purchase popup and the denial hint, with nothing overlapping
  plots, the villager or the HUD.
- 4.3 Headless tests: after the first sale, buying leaves `idleTimer` and
  `nagTimer` unchanged and the idle break fires on schedule from the sale;
  buying and then selling with zero crops is still an over-sell; after buying
  and the break, the backrooms gets seeds only (`beanstalk=1 pumpkin=0 vine=1`:
  the bought vine kept, beanstalk topped up for Room 1), with 0 coins and 0
  crops. The autotest also checks the idle timer kept running.
- 4.4 The `RELEASE.md` and `README.md` controls cover the stall and prices.
  The autotest buy step is described in 4.2. `sh tests/check_all.sh`: ALL
  CHECKS PASSED. That is 121 headless tests, reachability 84/0, rim ok,
  autotest 117 (real) and 109 (placeholder) checks from source and artifact,
  and 114 for the artifact with `--debug`. The package sha256 was stable
  across two builds (`f34787f3...6c59` at this point).
