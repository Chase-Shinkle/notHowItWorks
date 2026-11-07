# Visual note: exit void and bottomless pits

Render-only; gameplay, colliders, killZ and LevelGen are unchanged.

- Exit: the trigger box is drawn solid black via a new `unlit` uniform in `shaders/backrooms.glsl` (no light, fog or tint), with a pale render-only frame (two posts + lintel, `ROOM_EXIT_FRAME*` in `src/Room.lua`) so it is findable.
- Pits/gaps: room surfaces below the floor plane fade to black between z = 0 and z = -2.5 in the look shader, so the bottom (z = -4) is never visible; rims and edges stay lit. Plots/crops (gameplay-lit) are unaffected.
- Caveat: with `--no-shader` / fallback the exit is still black with a frame, but pit depth is not faded.
- Screenshots (not evaluated): /workspace/qa/maze/visual/L2-pit-v.png, L2-exit-v.png.
