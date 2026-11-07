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

## Debug / testing

- `F1` (when `DEBUG_MODE` is on in `src/constants.lua`) advances
  start -> farm -> backrooms -> start.
- `love . --placeholder-assets` forces every texture/sound/font to its
  flat-color / silent fallback, simulating empty asset folders.
- `lua tests/run.lua` (or `luajit tests/run.lua`) runs headless tests against
  mocked LÖVE/g3d.
