# Tasks

## 1. Fonts and shared UI

- [ ] 1.1 Confirm the licence and source of `fonts/SaH1Outline.ttf` with the author and add its entry to `THIRD_PARTY_NOTICES.md`; verify the notice names font, author and licence.
- [x] 1.2 Register the font in `src/Dependencies.lua` (title sizes) and add a cached, window-height-scaled `UI.font(size)` helper that falls back to the built-in font; unit test the fallback with the font path missing (no error, usable font).
- [x] 1.3 Add `src/UI.lua` with the `Menu`: button layout, one highlighted button (first by default), Up/Down/W/S navigation, Enter/Space activate, mouse hover and left-click hit-testing via a coordinate mapper; unit tests for hit-testing, navigation wrap, click-outside no-op and activation callbacks.
- [ ] 1.4 Add a placeholder-safe `UI` button draw (frame, highlight, label) that fits its label to the button; verify by screenshot with the TTF and with the fallback font.

## 2. Title screen

- [ ] 2.1 Rewrite `StartState` to draw the farm scene from existing textures (ground, path, soil plots, crops with sway, fence, barn, drifting clouds) in virtual coordinates; verify by screenshot at 800x800 and a resized window.
- [ ] 2.2 Draw the "Back to Farming" title and the Play Game / Exit Game menu; Play changes to `farm` with `NewGameData()`, Exit calls `love.event.quit()`; unit test both callbacks with the mocked state machine and quit.
- [ ] 2.3 Set the window title to "Back to Farming" in `love.load`; verify by test or log of `love.window.setTitle`.
- [ ] 2.4 Update `tests/autotest.lua` Start step (Enter still starts the game) and confirm the run still reaches the farm.

## 3. Backrooms hotbar

- [x] 3.1 Add `src/Hotbar.lua` with `layout(w, h)` (centred, scaled with height, clamped, on-screen at 640 and 1080) and `draw`; unit test layout bounds and slot count at several window sizes.
- [x] 3.2 Draw `seedbag-<type>` icons, key numbers, corner counts, selected frame and dimmed empty/unused slots; verify by screenshot including a zero-count slot and a type the room does not use.
- [x] 3.3 Add `love.wheelmoved` in `main.lua` (reset each update) and cycle the selection with wrap in `BackroomsState` only while the mouse is captured, skipping types the room does not use; unit test forward/backward wrap and no change when uncaptured.
- [x] 3.4 Rewrite `BackroomsState:renderHUD`: remove the full-width bands, add a compact room-name plate, keep the plant prompt and messages near the crosshair, fade the controls hint after a few seconds (shown while the mouse is free); verify by screenshots on bright and dark rooms and that planting prompts are unchanged.
- [x] 3.5 Test that hotbar counts follow planting, uproot refund and pickup collection (extend the existing seed tests), and run the maze/zones checks to confirm no gameplay regression.

## 4. Ending scene

- [ ] 4.1 Pass `{gameData, runSeed}` from `BackroomsState:advance` to the ending; `EndingState:enter` also accepts a bare `gameData` with a random seed; unit test both forms.
- [ ] 4.2 Make `EndingState` `usesPush = false`: build a `Room` from `LevelGen.generate` for the run seed, render through `BackroomsLook.renderScene`, use a flickering lighting preset; test that the same seed yields the same level and that `--no-shader` still renders.
- [ ] 4.3 Implement the scripted camera (time-parameterised drift and sway, holds at the end, clamped inside the hallway, ignores input) with an authored-hallway fallback; test the path stays within open cells across a seed sweep and that input does not move it.
- [ ] 4.4 Start `BackroomsAudio` in `enter` and dispose it in `exit`; free the mouse; test that audio is disposed when leaving to the title and that no hum plays on the title screen.
- [ ] 4.5 Draw the fading headline, subtitle and the "Back to Title" / "Exit Game" menu in `renderHUD`; ignore input until the buttons have faded in; test that a held key at entry activates nothing, "Back to Title" goes to `start`, and Exit quits.
- [ ] 4.6 Update `tests/autotest.lua` ending step (state check, screenshot heuristic no longer assumes a mostly black screen) and verify the full run: title -> farm -> backrooms -> ending -> title -> new game.

## 5. Integration

- [ ] 5.1 Add the new test files to `tests/check_all.sh`, run the full suite, and fix regressions; record results in a `verification.md` for this change.
- [ ] 5.2 Update `README.md` (title/menu controls, hotbar and mouse wheel, ending) and verify the documented controls match the game.
- [ ] 5.3 Review screenshots of title, hotbar and ending at 640, 800 and fullscreen sizes, with and without the TTF and shader; note any follow-ups.
