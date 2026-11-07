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

## Backrooms

- First person: the mouse is captured on entry (relative mode). Mouse looks,
  WASD / arrows walk. Esc frees the cursor; a left click captures it again.
- The player is a capsule (`src/PlayerController.lua`) with gravity, blocked
  by walls and supported by floors and box tops, sliding along surfaces. It
  uses `g3d.collisions.capsuleIntersection`. Tuning is `BACKROOMS_*` in
  `src/constants.lua`.
- Rooms are data (`src/rooms.lua`), built by `src/Room.lua`: axis-aligned
  boxes, fixed plots, an exit trigger, a seed allotment and billboarded farm
  sprites (`src/Billboard.lua`). Walking into the glowing exit loads the next
  room; the last exit shows the ending.
- Seeds: Room 1 keeps the farm seeds (topped up to its allotment); later rooms
  give exactly their own allotment.
- Seed puzzles: E / Enter / left click plants the selected seed on the
  nearest soil plot in range (there is no planting anywhere else). 1-3 select a
  type, Q / Tab cycles; the HUD shows every type's count. R resets the room
  (crops removed, seeds restored to what you had on entering it).
- Crops (`src/Crop.lua`) grow over 2-2.5 s and do nothing until fully grown:
  a beanstalk is a 3 m climb volume (press forward while standing in it to
  climb; back climbs down; walk off sideways at the top), a pumpkin is a
  2.6 x 2.6 x 1 m solid block (walkable when it fills a 1 m pit, since there
  is no jump or step-up), and a vine is a 6 m flat bridge growing from its
  plot in the plot's direction.
- Room 1: finish the half-grown beanstalk with one seed and climb to the exit.
  Room 2: pumpkin in the pit, then vine over the gap. Room 3: pumpkin, then
  beanstalk up the ledge, then vine over the gap. Falling into a pit or gap
  respawns you at the room start with your crops and seeds kept.

## Debug / testing

- `F1` (when `DEBUG_MODE` is on in `src/constants.lua`) advances
  start -> farm -> backrooms -> start. From the farm it skips the break but
  uses the same seeds-only hand-off (`CarryOverGameData`). In the backrooms it
  skips the current room (the last skip shows the ending); on the ending it
  returns to start.
- `love . --placeholder-assets` forces every texture/sound/font to its
  flat-color / silent fallback, simulating empty asset folders.
- `lua tests/run.lua` (or `luajit tests/run.lua`) runs headless tests against
  mocked LÖVE/g3d. Run it from the repo root.
- `lua tests/reachability.lua` searches every seed-to-plot assignment in
  every room with the real controller code and fails if anything but the
  intended combination reaches an exit (slower; `tests/reach.lua`).
- `rg --files -g "*.lua" -0 | xargs -0 python3 -I tests/tools/lua_structure_check.py` is a
  structural check (block/bracket balance, non-Lua operators) for machines
  without Lua. It does not run any code and cannot replace the test run.
- Verification status for the OpenSpec change is tracked in
  `openspec/changes/farm-to-backrooms-crop-escape/verification.md`.
