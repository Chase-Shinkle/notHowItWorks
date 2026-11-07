# Verification log

Checked tasks in `tasks.md` mean **the code is written**. Each task's
"verify ..." step is tracked here and is only marked done once it has
actually been performed.

## Current status (2026-11-07, section 5 review run)

LÖVE 11.5 is now installed (`/home/box/.local/bin/love`, an extracted
AppImage that bundles LuaJIT 2.1). Everything below marked **passed** was
actually executed on that runtime in this container. Nothing was
re-implemented in Python; the earlier Python structural checker and the
throwaway Python controller port are superseded and no longer evidence.

One command runs every automated check (about 1.5 minutes):

```
sh tests/check_all.sh
```

which runs:

| Check | Command | Result |
|-------|---------|--------|
| Headless tests (real LuaJIT, mocked LÖVE API, real g3d camera/collisions) | `love tests/love_runner tests/run.lua` | **102 passed, 0 failed** |
| Reachability sweep: every plot assignment in all three rooms | `love tests/love_runner tests/reachability.lua` | **84 assignments, 0 unexpected** (only the intended solutions reach an exit) |
| Plain launch, real assets | `xvfb-run -a timeout 8 love .` | exit 124 (still running), **no `Error` in the log** |
| Plain launch, forced placeholders | `xvfb-run -a timeout 8 love . --placeholder-assets` | exit 124, **no `Error` in the log** |
| Scripted playthrough, real assets | `xvfb-run -a -s '-screen 0 1024x1024x24' love . --autotest` | **72 checks, 0 failed** (3344 frames, 55.7 s simulated) |
| Scripted playthrough, placeholders | same with `--placeholder-assets` | **72 checks, 0 failed** |

Renderer under Xvfb: Mesa llvmpipe, OpenGL 4.5 core. A real GPU / driver
was not tested.

Harness notes:

- `tests/love_runner/` is a window-less LÖVE shell (no window/graphics/audio
  modules) that `dofile`s a plain-Lua test script with LÖVE's LuaJIT. The
  test scripts still install `tests/mock_love.lua` as the LÖVE API, so
  `run.lua` and `reachability.lua` exercise the game logic, g3d's pure-Lua
  camera/collision code and the real controller, not GL rendering.
- `tests/autotest.lua` is loaded only by `love . --autotest` (hook at the end
  of `main.lua`). It runs the **real** game (real window, depth buffer, push
  canvas, g3d shaders and meshes, billboard alpha shader, real assets) at a
  fixed 1/60 s step, drawing and presenting every frame. Input goes through
  the game's own `love.keypressed` / `love.mousepressed` / `love.mousemoved`
  handlers plus a held-key overlay on `love.keyboard.isDown`; the script
  never sets game state, it only reads it to know when to release a key and
  to assert. Any uncaught error goes through a replaced
  `love.errorhandler` that prints the traceback and exits 1. 17 screenshots
  are written to `$AUTOTEST_OUT` (default `/tmp/autotest`) and each is checked
  to be neither LÖVE's blue error screen nor blank.
- Negative controls run this session: a `love.load` that raises shows
  `Error: ...` in the log while `timeout` still exits 124 (so the launch
  check greps the log, not only the exit code); a raising script under
  `love_runner` exits 3; a script that exits 1 propagates 1; an error in the
  autotest script (a bug in its first draft) exited 1 with a traceback.

The autotest playthrough covers: start -> Enter -> farm; plant, wait 12.5 s,
harvest, walk to the villager, sell; over-sell starts the break; E and F1 are
ignored during it; the break ends in the backrooms with no coins; mouse look
turns and returns; Esc frees the mouse and a click recaptures without
planting; Room 1 (half-grown demo not climbable, demo plot refuses a
pumpkin, one beanstalk seed finishes it, climb and walk to the exit); Room 2
(allotment pumpkin 2 / vine 2; a vine in the pit fails and the player falls
and respawns; R restores seeds and clears crops; pumpkin then vine reaches
the exit); Room 3 (allotment 2/2/2; pumpkin, beanstalk climb onto the ledge,
vine, exit -> ending); Enter on the ending returns to start; a 640x480 window
resize, then F1 x2 into the backrooms still renders.

I looked at the screenshots: walls, floor, ceiling, ledge, pits, crops,
plots, billboards and the green exit marker draw with correct depth; the
HUD sits on top; the farm, the glitch frame and the text screens render
through push. That is a smoke check by eye on llvmpipe, not the human
playfeel review below.

### Still needs a human (not automatable here)

- Feel: mouse sensitivity and real relative-mouse behaviour (first delta,
  focus loss, alt-tab); the autotest calls `love.mousemoved` directly.
- Whether a first-time player understands each room without help, and the
  plant -> harvest -> sell cycle and full run times with a real player
  (task 2.3 "under about 3 minutes", task 6.2 "under about 15 minutes").
- Sound: every sound is currently a placeholder (no files in `sounds/`), so
  nothing audible has been checked.
- Visual polish: billboard sizes (the Room 1 crop billboard near the spawn
  looks large and blurry close up), the 8 px farm font at 800x800, the hint
  bar wrapping at 640 px wide, glitch harshness.
- Real GPU/driver rendering (only llvmpipe was used).

## Earlier per-task tables

The tables below were written before any runtime existed. Their
"Automated" column now **passed** in the run above (102/102). Their
"Manual" column is partly covered by the autotest (noted per row) and the
rest is still pending a human.

| Task | Automated (tests/run.lua) | Manual (run the game) | Status |
|------|---------------------------|-----------------------|--------|
| 1.1 push opt-out | push/native render-path tests | Backrooms cubes intersect cleanly (depth OK), start screen still scaled by push, window resize | automated: passed; autotest screenshots (llvmpipe) show correct depth, push-scaled start/farm/ending and a working 640x480 resize; human check on a real GPU pending |
| 1.2 state stubs | debug-key transition tests (updated in section 4) | F1 cycles start -> farm -> backrooms room 1 -> 2 -> 3 -> ending -> start | automated: passed; manual: pending |
| 1.3 shared data | game-data test; debug hand-off test (updated in section 4: now seeds-only via `CarryOverGameData`) | console shows `[backrooms] seeds received: ...` | automated: passed; autotest log shows `[backrooms] seeds received: ...` after the real break |
| 1.4 placeholders | fallback / forced-placeholder tests | `love . --placeholder-assets` launches and every state draws | automated: passed; `love . --placeholder-assets` launch + full autotest playthrough pass, every state drawn |
| 2.1 grid, avatar, input | movement, hold-repeat, highlight and mouse tests | farmer walks the field and is blocked by plots, villager and edges; yellow outline on the faced tile; white outline on hovered plot/villager; clicks work after a window resize (push letterbox) | automated: passed; manual: pending |
| 2.2 plant, grow, harvest | planting, no-seed, fallback, growth-stage, maturity-timing, immature and harvest tests | seed count drops, sprites visibly change over about 12 s, harvest adds to the top-bar crop count | automated: passed; manual: pending |
| 2.3 villager, coins, cycle | sell, sell-with-no-crops and timed first-cycle (<30 s simulated) tests | coins/crops in the top bar update; a fresh player finishes plant -> harvest -> sell in under about 3 minutes without reading instructions | automated: passed; manual: pending |
| 3.1 repeat requests, over-sell gate | no-break-before-sale (keyboard + idle), repeated-requests, over-sell-after-stock-exhaustion, over-sell-by-click tests | after the last sale the villager bubble keeps asking; selling empty-handed before any sale only says "Got any crops?"; after a sale it starts the break | automated: passed; manual: pending |
| 3.2 glitch sequence, input lock, one transition | input-lock (keys, held keys, clicks, seed slots, F1, growth frozen), shake/corruption/fall phases + exactly-one-transition, no-restart, already-broken and placeholder-render tests | shake, corruption blocks and the fall look right and readable (~3 s), glitch sound plays, the screen ends in the backrooms, nothing responds during the sequence | automated: passed; manual: pending |
| 3.3 seeds-only carry-over, top-up | low-seed (0 seeds -> beanstalk 1), high-seed (5/3/3 preserved exactly) and `CarryOverGameData` unit tests | console shows `[backrooms] seeds received: ...` matching the farm HUD at the break; backrooms HUD shows no coins/crops | automated: passed; autotest: seeds at the break = room 1 seeds, coins 0; HUD shows no coins/crops (screenshot 06) |
| 3.4 idle fallback | idle-fires-after-delay and new-sale-restarts-delay tests | after one sale, waiting `FARM_IDLE_BREAK_TIME` (45 s) without over-selling starts the break | automated: passed; manual: pending |

### Section 3 notes (2026-11-07)

*(Historical: written before LÖVE was installed; these tests now pass, see "Current status".)* Same environment as above: no Lua runtime, so none of the section 3 tests in
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
| 4.1 look, move, mouse capture | capture/Esc/click/release, mouse-look yaw + clamped pitch, WASD/arrows relative to yaw with normalised diagonals, camera follows the eye, native-resolution HUD tests | in the plain box room (Room 1 fixture): the cursor is hidden and locked, the mouse turns smoothly in the expected directions (not inverted), WASD/arrows walk at a comfortable speed, Esc frees the cursor and a click recaptures it, the view is sharp at native resolution after a window resize | automated: passed; manual: pending |
| 4.2 capsule, gravity, slide | rest without jitter, fall + land, wall stop, diagonal slide, corner in/out, walk off a ledge, ledge side blocks, thin-wall / long-fall tunnelling, dt clamp, ceiling, broadphase, kill-plane respawn tests | walk into every wall and corner (the section 4 pillar/ledge fixtures were replaced by the section 5 rooms): no clipping, no sticking, no visible jitter while standing; step off the Room 2 ledge and fall; check it at a low frame rate too | automated: passed; manual: pending |
| 4.3 data-driven Room builder | sample-room build (boxes, colliders, collide=false, plots, exit bounds, allotment copy, billboards, demoCrops kept), UV tiling + face shading, validation errors, every fixture builds and spawns the player standing | the three fixture rooms look like backrooms (yellow walls, darker floor, readable box edges); textures tile once real wall/floor PNGs exist | automated: passed; manual: pending |
| 4.4 billboards | upright quad verts / UVs, facing from 8 angles, aspect-ratio width, in-state facing + drawn after opaque geometry far-to-near tests | walk around the farm sprites: they always face you, are not mirrored, and their transparent areas do not hide walls or other sprites behind them (alpha-discard shader) | automated: passed; by eye in autotest screenshots the transparent sprite corners do not hide walls; walk-around check pending |
| 4.5 exits, progression, ending | walk-into-exit loads room 2 with its allotment, each exit fires once, last exit shows the ending (push path), single-room list, ending delay + Enter -> start tests | walk into each glowing doorway: the next room loads with the seeds HUD updated; the last one shows the ending; Enter returns to the start screen | automated: passed; autotest walks into all three exits through real play, ending + Enter -> start |

### Section 4 notes (2026-11-07)

*(Historical: these tests now pass on the real runtime.)* Same environment: no Lua/LÖVE, so none of the 30 new tests (75 in total in
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
- *(Superseded by section 5: the rooms are now the real puzzles and every exit starts out of reach, checked by `tests/reach.lua`.)* The rooms in `src/rooms.lua` were **section 4 fixtures**. Their exits can be
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

### Section 5 rows (2026-11-07)

All of these ran on the real runtime (see "Current status").

| Task | Automated (tests/run.lua, reachability.lua) | Real-game autotest (`love . --autotest`) | Human check still pending |
|------|---------------------------------------------|------------------------------------------|---------------------------|
| 5.1 seed types, growth, collidable | growth tween per axis, unusable until grown, full-size unscaled colliders, grown pumpkin waits until the player is clear | demo beanstalk, pumpkins and vines visibly grow and are then climbed / walked on | growth reads well and looks like the three distinct shapes |
| 5.2 nearest plot, selection, HUD | nearest plot within 1.8 m / 1.6 m (incl. just inside / just outside the range), E plants and only that count drops, nothing away from plots, occupied/empty refused, 1-3 / Q / Tab / click, last seed auto-selects the next | plots in range at each scripted stand point; counts drop by one per plant; Esc + click recapture does not plant | prompts are noticed and understood |
| 5.3 climbing / standing | climb + step off onto the ledge, hold / climb down / top cap, falling player not caught, ungrown not climbable, pumpkin-in-pit walkable at floor level, vine bridge | Room 1 and Room 3 beanstalk climbs onto 2.6 m ledges; pumpkin walked over at z = 0.00; both vines crossed | climb feel (forward to climb, sideways to leave) |
| 5.4 tutorial room | frozen half-grown demo + unreachable visible exit, demo plot refuses other types, one beanstalk finishes it and reaches the exit | half-grown demo not climbable; pumpkin refused ("This beanstalk needs a beanstalk seed"); one beanstalk -> climb -> exit; exit marker visible over the lip from the spawn (screenshot 06) | a new player figures it out unaided |
| 5.5 room reset | R in room 2 restores the exact initial state; room 1 demo returns to half-grown; deterministic | wrong vine in the pit, fall + respawn, R restores pumpkin 2 / vine 2 and clears crops, then the room is solved | - |
| 5.6 room 2 combination | played-through solution; each single type fails; only pumpkin@pit + vine@edge reaches the exit (all 16 assignments) | solved by real input after a wasted seed and a reset | - |
| 5.7 room 3 + ending hook | played-through solution to the ending; single types and every combination missing a type fail; only pumpkin@pit + beanstalk@foot + vine@lip reaches the exit (all 64 assignments) | solved by real input; exit -> ending -> Enter -> start | - |

### Section 5 notes (2026-11-07)

Fixes in this run, both test bugs found by the first real execution (the
game code was right):

- `planting: the nearest plot ...`: the test placed two plots 4 m apart and
  asked for the "nearest of two in range" from a point 1.9-2.1 m from each,
  so both were out of the 1.8 m range. Plots moved to 3 m apart; added
  just-outside-range and the other-side nearest cases.
- `planting: 1-3 select ...`: expected Room 3 to start on beanstalk, but the
  selected seed is a UI preference that is kept between rooms (Room 2
  auto-selects pumpkin because it has no beanstalks). The test now asserts
  the carried selection and presses 1 first.
- Docs: the vine is 1.2 m wide (`CROP_DEFS.vine.width`), not 1.4 m as
  design.md and the `src/rooms.lua` header said; docs corrected.

Limits of the evidence:

- "Unsolvable" is shown by `tests/reach.lua`, a coarse breadth-first search
  over the real controller and real g3d collisions (8 headings, 0.25 s
  actions, 0.4 m cells), not a proof. It also cannot model mouse-look tricks
  finer than its 8 headings, or input timing finer than 0.25 s.
- Soft-locks: every fall below `killZ` respawns at the spawn (checked in the
  autotest), and R works in every backrooms situation (including while
  climbing), so a wasted seed or awkward position is always recoverable.
  A human should still try to break the rooms.

## Known risks (written before the first real run; status updated 2026-11-07)

- `tests/mock_love.lua` stands in for LÖVE, push and g3d. A mock that is wrong
  (e.g. font `getWidth`, `push:toGame` scale) can hide a real failure.
  *Mitigated: the `--autotest` playthrough runs the real LÖVE/push/g3d path
  and passes; farm mouse clicks after a push letterbox resize are still only
  covered by the mock.*
- Pixel art is drawn at <= 2x inside push. Check that crop sprites of different
  sizes sit nicely on their plots.
- The glitch draw uses `math.random` every frame; check the shake and
  corruption are not too harsh (or too subtle) at the real window size.
- Section 4: g3d's capsule test uses one sphere per triangle (the triangle's
  closest point on the capsule spine). It handled walls, floors, corners and
  edges in the Python port, but real play may still show snags on box seams,
  e.g. where a floor meets a ledge. *The real-runtime tests and the autotest
  showed no snags on the scripted paths; free play is still untested.*
- Section 4: `g3d.collisions` scales normals by `scale_x` only, so
  non-uniform scaling breaks them. Growing crops (task 5.1) should either use
  uniform scale or rebuild verts at the new size.
- Section 4: the billboard alpha-discard shader is built with
  `love.graphics.newShader(g3d.shaderpath, pixelCode)` inside `pcall`. If it
  fails to compile, sprites fall back to g3d's shader and their transparent
  corners may hide what is behind them. *Checked: it compiles on Mesa
  llvmpipe (autotest check); other drivers untested.*
- Section 4: `love.mouse.setRelativeMode` behaviour (first large delta,
  focus loss, alt-tab) is untested; mouse sensitivity is g3d's fixed 1/300.
- The built-in 8 px font is small at 320x320. Check that the top bar and hint
  bar are readable at the default 800x800 window.
