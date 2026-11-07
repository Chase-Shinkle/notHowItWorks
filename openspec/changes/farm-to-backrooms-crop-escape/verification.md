# Verification log

Checked tasks in `tasks.md` mean **the code is written**. Each task's
"verify ..." step is tracked here and is only marked done once it has
actually been performed.

## Environment (2026-11-07)

No Lua runtime is available in the development container:

- no `lua`, `lua5.x`, `luajit` or `love` binary on PATH
- `/sbin/ldconfig -p` lists no `liblua*` / `libluajit*`; no Lua shared
  libraries, headers or sources anywhere on the filesystem
- no Python Lua binding (`lupa`) and no JS/WASM Lua (fengari, wasmoon)
- apt's network is blocked (reported, not re-tested here); package sources were
  not modified and nothing was installed

What **was** run:

- `python3 -I tests/tools/lua_structure_check.py $(git ls-files '*.lua')`:
  38/38 tracked `.lua` files pass. This checks block-keyword and bracket balance and rejects
  non-Lua operators. It parses nothing deeper and executes nothing. As a
  control, it passes the third-party `g3d/`, `lib/knife`, and `lib/push`
  sources and fails 5 deliberately broken samples.
- A one-off scan that every ALL_CAPS / `g*` global used in `src/`, `main.lua`
  and `tests/run.lua` is assigned somewhere.

What was **not** run: `lua tests/run.lua`. No headless test, no game launch,
and no manual check below has been performed.

## Pending checks

Run first, on a machine with LÖVE 11.5 and Lua 5.1/LuaJIT:

```
lua tests/run.lua            # or: luajit tests/run.lua   (from the repo root)
love .
love . --placeholder-assets
```

| Task | Automated (tests/run.lua) | Manual (run the game) | Status |
|------|---------------------------|-----------------------|--------|
| 1.1 push opt-out | push/native render-path tests | Backrooms cubes intersect cleanly (depth OK), start screen still scaled by push, window resize | not run |
| 1.2 state stubs | debug-key transition tests (updated in section 4) | F1 cycles start -> farm -> backrooms room 1 -> 2 -> 3 -> ending -> start | not run |
| 1.3 shared data | game-data test; debug hand-off test (updated in section 4: now seeds-only via `CarryOverGameData`) | console shows `[backrooms] seeds received: ...` | not run |
| 1.4 placeholders | fallback / forced-placeholder tests | `love . --placeholder-assets` launches and every state draws | not run |
| 2.1 grid, avatar, input | movement, hold-repeat, highlight and mouse tests | farmer walks the field and is blocked by plots, villager and edges; yellow outline on the faced tile; white outline on hovered plot/villager; clicks work after a window resize (push letterbox) | not run |
| 2.2 plant, grow, harvest | planting, no-seed, fallback, growth-stage, maturity-timing, immature and harvest tests | seed count drops, sprites visibly change over about 12 s, harvest adds to the top-bar crop count | not run |
| 2.3 villager, coins, cycle | sell, sell-with-no-crops and timed first-cycle (<30 s simulated) tests | coins/crops in the top bar update; a fresh player finishes plant -> harvest -> sell in under about 3 minutes without reading instructions | not run |
| 3.1 repeat requests, over-sell gate | no-break-before-sale (keyboard + idle), repeated-requests, over-sell-after-stock-exhaustion, over-sell-by-click tests | after the last sale the villager bubble keeps asking; selling empty-handed before any sale only says "Got any crops?"; after a sale it starts the break | not run |
| 3.2 glitch sequence, input lock, one transition | input-lock (keys, held keys, clicks, seed slots, F1, growth frozen), shake/corruption/fall phases + exactly-one-transition, no-restart, already-broken and placeholder-render tests | shake, corruption blocks and the fall look right and readable (~3 s), glitch sound plays, the screen ends in the backrooms, nothing responds during the sequence | not run |
| 3.3 seeds-only carry-over, top-up | low-seed (0 seeds -> beanstalk 1), high-seed (5/3/3 preserved exactly) and `CarryOverGameData` unit tests | console shows `[backrooms] seeds received: ...` matching the farm HUD at the break; backrooms HUD shows no coins/crops | not run |
| 3.4 idle fallback | idle-fires-after-delay and new-sale-restarts-delay tests | after one sale, waiting `FARM_IDLE_BREAK_TIME` (45 s) without over-selling starts the break | not run |

### Section 3 notes (2026-11-07)

Same environment as above: no Lua runtime, so none of the section 3 tests in
`tests/run.lua` (14 new, 45 in total) have been executed. They
were desk-checked against `lib/knife/timer.lua` only. The structural checker
passes 38/38 tracked `.lua` files after the change, and every new global
(`FARM_BREAK_*`, `FARM_IDLE_BREAK_TIME`, `FARM_VILLAGER_*`,
`FIRST_ROOM_MIN_SEEDS`, `CarryOverGameData`) is defined.

Behaviour decisions that the tests encode (check they feel right in play):

- The idle delay counts from the most recent successful sale; other input
  does not reset it. Before any sale neither trigger can fire.
- The break plays once per game (`gameData.hasBroken`); growth timers are
  frozen while it plays.
- The final sequence timer only sets a flag; `FarmState:update` performs the
  state change, because changing state inside a knife Timer callback would
  clear the group that `Timer.update` is iterating.
- The F1 debug skip from the farm is still a raw pass-through of the farm's
  game-data table (coins/crops included, no top-up). Only the real break uses
  `CarryOverGameData`. *(Superseded in section 4: F1 now also uses
  `CarryOverGameData`.)*
- `FIRST_ROOM_MIN_SEEDS = {beanstalk = 1}` is a placeholder for Room 1's
  requirement and must be matched to the Room 1 data in task 5.4. Note that
  the room-puzzles spec ("seeds equal that room's allotment") will need to be
  reconciled with seed-carryover ("holds the seeds they had at the break")
  when rooms are built.

### Section 4 rows

| Task | Automated (tests/run.lua) | Manual (run the game) | Status |
|------|---------------------------|-----------------------|--------|
| 4.1 look, move, mouse capture | capture/Esc/click/release, mouse-look yaw + clamped pitch, WASD/arrows relative to yaw with normalised diagonals, camera follows the eye, native-resolution HUD tests | in the plain box room (Room 1 fixture): the cursor is hidden and locked, the mouse turns smoothly in the expected directions (not inverted), WASD/arrows walk at a comfortable speed, Esc frees the cursor and a click recaptures it, the view is sharp at native resolution after a window resize | not run |
| 4.2 capsule, gravity, slide | rest without jitter, fall + land, wall stop, diagonal slide, corner in/out, walk off a ledge, ledge side blocks, thin-wall / long-fall tunnelling, dt clamp, ceiling, broadphase, kill-plane respawn tests | walk into every wall, the Room 2 pillar and corners: no clipping, no sticking, no visible jitter while standing; step off the Room 2 ledge and fall; check it at a low frame rate too | not run |
| 4.3 data-driven Room builder | sample-room build (boxes, colliders, collide=false, plots, exit bounds, allotment copy, billboards, demoCrops kept), UV tiling + face shading, validation errors, every fixture builds and spawns the player standing | the three fixture rooms look like backrooms (yellow walls, darker floor, readable box edges); textures tile once real wall/floor PNGs exist | not run |
| 4.4 billboards | upright quad verts / UVs, facing from 8 angles, aspect-ratio width, in-state facing + drawn after opaque geometry far-to-near tests | walk around the farm sprites: they always face you, are not mirrored, and their transparent areas do not hide walls or other sprites behind them (alpha-discard shader) | not run |
| 4.5 exits, progression, ending | walk-into-exit loads room 2 with its allotment, each exit fires once, last exit shows the ending (push path), single-room list, ending delay + Enter -> start tests | walk into each glowing doorway: the next room loads with the seeds HUD updated; the last one shows the ending; Enter returns to the start screen | not run |

### Section 4 notes (2026-11-07)

Same environment: no Lua/LÖVE, so none of the 30 new tests (75 in total in
`tests/run.lua`) have run. Four section 1-2 tests were changed to match the new
behaviour: the native-render draw count, the F1 cycle, and the two farm ->
backrooms hand-off tests. The hand-offs now expect a fresh seeds-only table, not
the farm's own table.

What was run:

- `rg --files -g "*.lua" -0 | xargs -0 python3 -I tests/tools/lua_structure_check.py`:
  43/43 `.lua` files pass (structural check only, nothing executed).
- A throwaway Python port of g3d's capsule path (`capsuleIntersection`,
  `triangleCapsule`, `triangleSphere`, `trianglePoint`) and of
  `PlayerController`, kept outside the repo. It reproduced the expected
  numbers for the 4.2 scenarios (rest at z = 0.001, wall stop at 2.699, slide,
  corner in/out, ledge drop, thin wall, long fall, ceiling) and the
  three fixture spawns. It also found one wrong test start height, which is
  fixed. It is a re-implementation, so it is only a desk-check. It cannot
  replace running the real Lua.

Test-harness change: `tests/mock_love.lua` now loads the **real** pure-Lua g3d
modules (`camera`, `matrices`, `vectors`, `collisions`), freshly for each test.
Only `g3d/init.lua` (shader) and `newModel` (mesh) are still stubbed. So the
controller and look tests exercise g3d's real collision and camera code.

Decisions the code and tests encode (check in play):

- **Seed policy** (design.md decision 9, an explicit exception to the
  room-puzzles wording; requirement text unchanged): Room 1's first entry
  keeps the farm seeds topped up to Room 1's allotment, and later rooms
  get exactly their fixed allotment. A reset restores the seeds recorded on
  entering the room. `BackroomsState:resetRoom()` exists, but no key is bound
  yet, and there are no crops to clear yet (task 5.5).
- The rooms in `src/rooms.lua` are **section 4 fixtures**. Their exits can be
  reached on foot, so room-progression's "exit cannot be reached without
  growing crop structures" is **not met yet**. That is tasks 5.4/5.6/5.7.
- There is no jump, so later puzzle heights must be reachable by crops alone.
  The capsule does not step up ledges either: in the tests a 1 m ledge blocks.
  Small steps are untested.
- F1 in the backrooms now skips the current room (the last skip shows the
  ending), and F1 on the ending returns to start.
- Falling below `BACKROOMS_KILL_Z` respawns the player at the room spawn
  without resetting seeds.
- The ending ignores Enter for its first 0.5 s, so a key held while reaching
  the exit does not skip it.

## Known risks to look at in the first real run

- `tests/mock_love.lua` stands in for LÖVE, push and g3d. A mock that is wrong
  (e.g. font `getWidth`, `push:toGame` scale) can hide a real failure.
- Pixel art is drawn at <= 2x inside push. Check that crop sprites of different
  sizes sit nicely on their plots.
- The glitch draw uses `math.random` every frame; check the shake and
  corruption are not too harsh (or too subtle) at the real window size.
- Section 4: g3d's capsule test uses one sphere per triangle (the triangle's
  closest point on the capsule spine). It handled walls, floors, corners and
  edges in the Python port, but real play may still show snags on box seams,
  e.g. where a floor meets a ledge.
- Section 4: `g3d.collisions` scales normals by `scale_x` only, so
  non-uniform scaling breaks them. Growing crops (task 5.1) should either use
  uniform scale or rebuild verts at the new size.
- Section 4: the billboard alpha-discard shader is built with
  `love.graphics.newShader(g3d.shaderpath, pixelCode)` inside `pcall`. If it
  fails to compile, sprites fall back to g3d's shader and their transparent
  corners may hide what is behind them.
- Section 4: `love.mouse.setRelativeMode` behaviour (first large delta,
  focus loss, alt-tab) is untested; mouse sensitivity is g3d's fixed 1/300.
- The built-in 8 px font is small at 320x320. Check that the top bar and hint
  bar are readable at the default 800x800 window.
