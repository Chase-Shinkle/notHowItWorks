# Game Jam

LÖVE 2D/3D project. Run with `love .`

- `g3d/` – 3D engine (groverbuger/g3d). Put `.obj` files in `models/`.
- `lib/` – class, push (virtual resolution), knife (timer, etc.)
- `src/` – StateMachine, Entity, Util, constants, Dependencies, `states/`
- Assets: `graphics/`, `sounds/`, `fonts/`, `shaders/`

Notes: g3d needs a depth buffer, so draw 3D directly to the screen (or a canvas
created with `{format = "depth24"}` readable depth) rather than through push's scaling.
