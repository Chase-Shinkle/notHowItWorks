# Proposal

## Why

The game opens on a bare "Game Jam" text screen, the backrooms HUD is a pair of dark text bands with seed counts typed out as labels, and the ending is two lines of text. None of it carries the game's identity: a cosy farm that breaks into the backrooms. The first and last things a player sees, and the thing they look at the whole time in the backrooms, should look finished.

## What Changes

- **Title screen** ("Back to Farming"): `StartState` becomes a farm scene (grass, path, soil plots with swaying crops, fence, barn, drifting clouds) composed from the existing farm art, with the title and two buttons, **Play Game** and **Exit Game**. Buttons work with mouse hover/click and with Up/Down + Enter. Play starts the farm as Enter does today; Exit quits. The window title becomes "Back to Farming".
- **Backrooms hotbar**: the backrooms HUD replaces the dark bands and `[1 Beanstalk x2]` text with a Minecraft-style hotbar centred at the bottom. It always shows one slot per seed type with the seed-bag icon, the key number and the count at the slot corner. The selected slot has a bright frame; empty slots dim. Mouse-wheel cycles the selection (new), alongside the existing 1-3 / Q / Tab keys and unchanged planting rules. Room name, plant prompt, messages and the controls hint are restyled as light overlays (hint fades after a few seconds) so nothing blocks the view.
- **Ending screen**: `EndingState` becomes a live 3D backrooms scene. A freshly generated hallway (from the run seed) is rendered through the existing backrooms look (lighting, fog, flicker, post-process) with a slow scripted camera drift and the backrooms hum. The headline, subtitle and two buttons (**Back to Title**, **Exit Game**) fade in over it. The mouse is released for the buttons.
- **Fonts**: the supplied `fonts/SaH1Outline.ttf` is used for the title, buttons and ending headline. A small helper provides fonts scaled to the window height for the native-resolution screens (hotbar counts, ending).
- The backrooms passes the run seed to the ending, so the ending hallway is reproducible for a run.

## Capabilities

### New Capabilities
- `title-menu`: the farm-themed title screen, its Play/Exit buttons and input handling, and the window title.
- `backrooms-hotbar`: the Minecraft-style seed hotbar and the restyled backrooms HUD overlays, including mouse-wheel selection.
- `ending-scene`: the live-3D backrooms ending, its camera, audio, text and buttons, and the transitions in and out.
- `ui-fonts`: the supplied display font, its fallback, scaled font helper and licence notice.

### Modified Capabilities
<!-- None: openspec/specs/ holds no capabilities yet; earlier behaviour lives in unarchived changes. -->

## Impact

- Code: `src/states/game/StartState.lua`, `EndingState.lua` (rewritten), `BackroomsState.lua` (`renderHUD`, wheel input, passes run seed on finish), `main.lua` (`love.wheelmoved`, window title, ending uses native render path), `src/Dependencies.lua` (font manifest, new files), `src/constants.lua` (UI constants); new `src/Hotbar.lua` (or similar) and `src/UI.lua` button helper.
- Assets: `fonts/SaH1Outline.ttf` (already added; no licence/attribution required), no new images (title reuses farm tiles and sprites).
- Tests: `tests/autotest.lua` drives Start with Enter and expects an Ending screen with text; both need updating. New unit tests for button hit-testing, hotbar layout/state and ending scene setup; a check that shader/post failure still leaves a readable ending.
- Overlap: `backrooms-zones-variety-audio` and `branching-maze-levels` are in progress and touch the backrooms; this change confines its `BackroomsState` edits to HUD, wheel input and the ending hand-off.
- Out of scope: pause menu, settings, run statistics, new audio/music, controller support.
