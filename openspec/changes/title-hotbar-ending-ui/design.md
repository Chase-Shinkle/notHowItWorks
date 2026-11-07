# Design

## Context

- States render through one of two paths (`love.draw`, `main.lua`). `usesPush = true` (Start, Farm, Ending today) draws into the 320x320 virtual canvas. `usesPush = false` (Backrooms) draws 3D at native resolution via `render()` and 2D via `renderHUD()` with depth off.
- `StateMachine:change(name, param)` passes a single `enterParams` value. The backrooms hands the ending only `gameData`; the run seed (`BackroomsState.runSeed`) is not passed.
- `BackroomsLook.renderScene(fn)` already wraps 3D in the lighting/post pipeline with its own fallbacks; `Room(data)` builds a drawable from level data; `LevelGen.generate(seed, difficulty, opts)` produces checked data; `BackroomsAudio.new()` starts the hum and must be `dispose()`d.
- `gFonts` has only the built-in font at 16 and 8. The farm HUD already draws seed-bag icons (`seedbag-<type>`); `gTextures` holds all farm sprites.
- `love.mousepressed` records into `love.mouse.buttonsPressed` but gives states no coordinates (states read `love.mouse.getPosition()`); there is no `love.wheelmoved`.
- Tests: `tests/autotest.lua` presses Enter on Start and expects `EndingState` after the last exit; unit tests run under `tests/mock_love.lua`.

## Goals / Non-Goals

**Goals:**
- One reusable button/menu component shared by the title and ending.
- HUD logic (slot layout, selection) testable without a GPU.
- The ending reuses the backrooms look and degrades the same way.

**Non-Goals:**
- Pause/settings menus, music, run stats, new art assets.
- Changing gameplay, seed rules or level generation.

## Decisions

1. **Shared `UI` module with a `Menu` object** (`src/UI.lua`). It owns button rects, highlight index, hover/click hit-testing and key navigation, and is parameterised by a coordinate mapper. Title uses virtual coordinates (`push:toGame`), the ending uses window pixels. Layout and hit-testing are pure functions, so unit tests can call them under the mock.
   *Alternative:* per-state ad-hoc code, rejected as it duplicates highlight/click rules the specs require to be identical.

2. **Title is a static composed scene in `StartState`, not an embedded `FarmState`.** It draws tiles, path, soil plots, crop sprites at fixed stages with a sine sway, fence, barn and clouds from existing `gTextures`, in virtual coordinates. A throwaway scene needs no timers or save data and cannot disturb `FarmState`.
   *Alternative:* attract-mode `FarmState`, rejected for coupling and input conflicts.

3. **Ending becomes `usesPush = false`.** `render()` runs `BackroomsLook.renderScene` over a `Room` built from a freshly generated level; `renderHUD()` draws the text and buttons at window resolution. The camera is `g3d.camera.lookInDirection` driven by a time-parameterised path; no `PlayerController`, no collision.
   *Alternative:* 2D textured backdrop (cheaper), rejected by the user in favour of live 3D.

4. **Ending hallway source: a fresh generated level** from `LevelGen.generate(LevelGen.levelSeed(runSeed, endingIndex), 1)`, using the run seed so it is reproducible. The camera path follows the level's first straight stretch from spawn (derived from the room's `spawn` and exit/region data) and holds at the end, with a clamp that keeps it inside the hallway. If a generated level offers no usable straight segment, fall back to a short authored hallway room definition. Lights are set to a flickering preset.
   *Alternative:* replay the last cleared level, rejected as it ties the ending to level-load internals. This choice was proposed and not objected to; revisit if the user prefers otherwise.

5. **Pass the run seed to the ending**: `gStateMachine:change('ending', {gameData = ..., runSeed = ...})`. `EndingState:enter` also accepts a bare `gameData` (tests, debug skip) and picks a random seed. Autotest and any caller of `change('ending', ...)` are updated.

6. **Hotbar as a pure layout + draw split** (`src/Hotbar.lua`): `Hotbar.layout(w, h)` returns slot rects scaled by window height (slot = ~7% of height, clamped); `draw` renders frames, `seedbag-<type>` icons, key numbers and counts using the layout. `BackroomsState:renderHUD` is rewritten to call it and to draw compact plates. `visibleSeedTypes()` still gates what the room *uses* for selection cycling, but the bar always shows all types; a type the room does not use is drawn dimmed and skipped by cycling.

7. **Mouse wheel**: add `love.wheelmoved(dx, dy)` in `main.lua`, recorded like key presses (`love.mouse.wheelDelta`, reset each update). `BackroomsState:update` reads it only when `mouseCaptured` and calls the existing `selectSeed` cycle logic, so planting rules do not change.

8. **Fonts**: manifest entries for `title` (the TTF at a few sizes) and a `ui(size)` helper that caches fonts by size for native-resolution screens, sized from window height. Headline text uses the TTF; small functional text keeps the built-in font because an outline face is likely noisy small. All loads go through `Assets.loadFont`, which already falls back to the built-in font. Title/button metrics are computed from the loaded font, so a fallback still fits.

9. **Hint fade**: the controls hint shows for a few seconds after a room loads or the mouse is captured, then fades; it stays while the mouse is released ("Click to capture the mouse").

10. **Window title** set in `love.load` to "Back to Farming".

## Risks / Trade-offs

- [Font licence unknown] → the task list blocks shipping on confirming the source/licence and adding the notice; the fallback keeps the game working without it.
- [Outline font illegible when small] → restrict it to large text, verify by screenshot at 640 and 1080 px windows.
- [Generated hallway camera path clips walls or finds no straight run] → clamp to cells known to be open; fall back to an authored hallway; sweep test builds the ending for many seeds.
- [Ending cost: building a `Room` from a generated level takes time] → build in `enter` behind the title fade; measure; the level is small (difficulty 1).
- [Edits collide with in-progress `backrooms-zones-variety-audio` / `branching-maze-levels`] → keep `BackroomsState` edits to `renderHUD`, wheel input and the ending hand-off; rebase on their merges.
- [Autotest assumptions about Start/Ending] → update the Enter-on-Start step and ending detection; the ending's "99% black" screenshot heuristic no longer applies.
- [Held key from the final exit activating a button] → ignore input for the first moments, and until the buttons have faded in.
- [Mouse capture state leaking] → `BackroomsState:exit` already frees the mouse; the ending asserts it and tests check the audio is disposed on leaving.
