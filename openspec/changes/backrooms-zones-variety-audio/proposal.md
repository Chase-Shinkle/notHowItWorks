# Proposal

## Why

Playing the generated backrooms, the space feels disconnected. `LevelGen` picks a material theme independently for every cell, so a wall can change texture at the next doorway and the carpet never matches the wallpaper next to it. Lighting is a single preset for the whole level (chosen from the level id), so every area feels the same. The layout, though good, uses only hallways and 2x2 rooms. And the new sound files (`Footsteps Rug 1-5.wav`, `BackroomsHum.mp3`) are not played: the hum is registered under a different file name and footsteps are not wired at all.

## What Changes

- Group the maze into **zones** (volumes): contiguous areas of the maze where wallpaper, carpet, ceiling, lighting and fog are consistent. Different zones in the same level look and are lit differently, with changes happening at doorways and thresholds, never mid-room.
- Lighting becomes per-zone (preset, fixture colour, flicker mix, fog), with a short blend of ambient and fog as the camera crosses a zone boundary. Some zones are bright, some dim, some nearly dark.
- Add more room shapes beyond hallways and 2x2 rooms: wide rectangular rooms (1x2, 2x3), L-shaped rooms, pillared halls, crossroads atriums with a higher ceiling, long galleries, and small closets and alcoves. Hallways and 2x2 rooms stay.
- Wire the audio: footsteps (the five `Footsteps Rug` sounds) while walking on the ground, and the backrooms hum (`BackroomsHum.mp3`) as a looping ambience. Both play **only inside the backrooms** and are silent in the start screen, farm, fall transition and ending.
- Props and dressing follow the zone's theme so a zone's props feel like part of it.
- **BREAKING** relative to the unarchived `backrooms-visual-atmosphere`: "per-room theme" and "lighting condition per room" become per-zone. Reconcile at archive.
- Out of scope: new textures or art (existing themes are reused, new art is optional), changing obstacle modules or solvability, a music score, farm audio.

## Capabilities

### New Capabilities
- `level-zones`: contiguous zones of consistent materials, lighting and fog, differing between zones, with transitions at thresholds.
- `room-variety`: additional room shapes and sizes beyond hallways and 2x2 rooms, without breaking solvability.
- `backrooms-audio`: footsteps and the hum, played only inside the backrooms.

### Modified Capabilities

None. There are no archived specs. This change supersedes, in the unarchived `backrooms-visual-atmosphere`: `backrooms-materials` "Per-room material themes" and `backrooms-lighting` "Varied lighting conditions" (now per zone), and extends `maze-layout` from `branching-maze-levels` with more room shapes.

## Impact

- `src/LevelGen.lua`: zone partition, per-zone theme and lighting assignment, new room shapes, zone ids in output; box merging keyed by zone.
- `src/Room.lua`, `src/BackroomsLook.lua`, `shaders/backrooms.glsl`: per-zone lighting and fog data, camera-zone blending, fixtures carry zone colour.
- `src/Dressing.lua`: choose props by zone theme.
- `src/states/game/BackroomsState.lua`, `src/Dependencies.lua`, `src/constants.lua`: footstep and hum playback, correct sound file registration, volumes.
- `sounds/`: uses the already-added `Footsteps Rug 1-5.wav` and `BackroomsHum.mp3`.
- `tests/`: zone-consistency and shape property tests, solvability sweep with new shapes, audio gating tests, screenshot review.
