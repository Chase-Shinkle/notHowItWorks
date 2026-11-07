# Game Jam

LÖVE 2D/3D project. Run with `love .`

- `g3d/` – 3D engine (groverbuger/g3d). Put `.obj` files in `models/`.
- `lib/` – class, push (virtual resolution), knife (timer, etc.)
- `src/` – StateMachine, Entity, Util, constants, Dependencies, `states/`
- Assets: `graphics/`, `sounds/`, `fonts/`, `shaders/`

Notes: g3d needs a depth buffer, so draw 3D directly to the screen (or a canvas
created with `{format = "depth24"}` readable depth) rather than through push's scaling.

## Render path

States render through `push` (320x320 virtual) by default. A state with
`usesPush = false` (e.g. `BackroomsState`) skips push: `love.draw` enables
depth testing and calls `state:render()` for 3D at native resolution, then
disables depth and calls `state:renderHUD()` for the 2D overlay. `conf.lua`
requests a 24-bit depth buffer for the window.

## Farm controls

- Move: WASD / arrow keys (one tile per press, hold to repeat).
- Use the highlighted tile: E / Space / Enter: plant on an empty plot,
  harvest a mature crop, or sell to the villager.
- Seeds: 1-3 select a type, Tab/Q cycles. If the selected type is empty, the
  next type that still has seeds is planted.
- Mouse: hovering a plot or the villager outlines it; left click uses it.
  Clicking a seed slot in the top bar selects that seed.
- A crop grows through 5 stages, one every 3 s (`FARM_STAGE_TIME`), so a first
  plant -> harvest -> sell cycle takes about 20 s.

## The break

- After the first sale the villager keeps asking for crops. Trying to sell
  with no crops left (an over-sell) starts the break. Before any sale, selling
  empty-handed does nothing.
- If the player goes `FARM_IDLE_BREAK_TIME` (45 s) after their latest sale
  without over-selling, the break starts anyway.
- The break is a ~3 s one-shot sequence (screen shake, corruption, the farmer
  falls) that ignores all input, then the game changes to the backrooms.
- Only seeds carry over (coins and crops are dropped), and each type is topped
  up to `FIRST_ROOM_MIN_SEEDS`. Timing and values live in `src/constants.lua`.

## Debug / testing

- `F1` (when `DEBUG_MODE` is on in `src/constants.lua`) advances
  start -> farm -> backrooms -> start. From the farm this skips the break and
  passes the farm's game data through unchanged.
- `love . --placeholder-assets` forces every texture/sound/font to its
  flat-color / silent fallback, simulating empty asset folders.
- `lua tests/run.lua` (or `luajit tests/run.lua`) runs headless tests against
  mocked LÖVE/g3d. Run it from the repo root.
- `python3 -I tests/tools/lua_structure_check.py $(git ls-files '*.lua')` is a
  structural check (block/bracket balance, non-Lua operators) for machines
  without Lua. It does not run any code and cannot replace the test run.
- Verification status for the OpenSpec change is tracked in
  `openspec/changes/farm-to-backrooms-crop-escape/verification.md`.
