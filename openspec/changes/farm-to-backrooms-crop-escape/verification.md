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
| 1.2 state stubs | debug-key transition tests | F1 cycles start -> farm -> backrooms -> start | not run |
| 1.3 shared data | game-data and pass-through tests | console shows `[backrooms] seeds received: ...` | not run |
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
  `CarryOverGameData`.
- `FIRST_ROOM_MIN_SEEDS = {beanstalk = 1}` is a placeholder for Room 1's
  requirement and must be matched to the Room 1 data in task 5.4. Note that
  the room-puzzles spec ("seeds equal that room's allotment") will need to be
  reconciled with seed-carryover ("holds the seeds they had at the break")
  when rooms are built.

## Known risks to look at in the first real run

- `tests/mock_love.lua` stands in for LÖVE, push and g3d. A mock that is wrong
  (e.g. font `getWidth`, `push:toGame` scale) can hide a real failure.
- Pixel art is drawn at <= 2x inside push. Check that crop sprites of different
  sizes sit nicely on their plots.
- The glitch draw uses `math.random` every frame; check the shake and
  corruption are not too harsh (or too subtle) at the real window size.
- The built-in 8 px font is small at 320x320. Check that the top bar and hint
  bar are readable at the default 800x800 window.
