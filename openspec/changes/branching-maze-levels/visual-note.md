# Visual note: exit void and bottomless pits

Render-only; gameplay, colliders, killZ and LevelGen are unchanged.

- Exit: the trigger box is drawn solid black via a new `unlit` uniform in `shaders/backrooms.glsl` (no light, fog or tint), with a pale render-only frame (two posts + lintel, `ROOM_EXIT_FRAME*` in `src/Room.lua`) so it is findable.
- Pits/gaps (revised): no z-based shader fade. `Room:init` (`voidRim`/`voidModels` in `src/Room.lua`) reads `data.meta.cells`; any box reaching down to the void floor (walls, void floor, ledge body, pit soil column) that touches a `module` cell is re-rendered with vertex colours fading from full at that cell's rim (the lowest floor elevation among the cells it touches) to black over `ROOM_PIT_FADE` = 1.5 m. Elevated regions fade relative to their own rim; non-module cells and legitimate below-zero floors are untouched. Colliders keep the original boxes, so physics is identical; rim floor slabs are unmodified so edges stay readable. Vertex colours also apply with `--no-shader` / fallback, so the look is the same there.
- Limits: the pit bottom is black via vertex colour, not truly unlit, so with the look shader the distance fog can still lift it toward fogColor (dim in dark presets). Dressing or hand-authored rooms without `meta` get no pit fade. A wall shared by a module cell and a lower neighbour fades only below the lower floor. Not re-screenshotted or tested after this change.
- Screenshots (not evaluated): /workspace/qa/maze/visual/L2-pit-v.png, L2-exit-v.png.
