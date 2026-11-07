# Proposal

## Why

Game jam entry (theme: "I don't think it's supposed to work like that", ~24 hours). The project is a blank LÖVE 11.5 scaffold (start screen only). We need a complete, short game whose hook is a cozy 2D farming sim that breaks and drops the player into a 3D backrooms, where the farming verbs become puzzle tools.

## What Changes

- Add a 2D farm sim: plant, wait, harvest, and sell crops to villagers for coins. It doubles as the tutorial for the plant/grow/harvest loop.
- Add a scripted "break": villagers keep buying past the player's stock (over-sell), the sim glitches, and the player falls out of the farm.
- Add a first-person 3D backrooms (g3d) of hand-built rooms, decorated with billboarded old farm assets.
- Add a seed puzzle system: three seed types (beanstalk, pumpkin, vine) grow into walkable structures on fixed planting plots, and rooms require combinations of them to reach the exit.
- Add a guided tutorial room: a half-grown demo crop the player finishes with one seed.
- Seeds (only) carry over from the farm into the backrooms; per-room seed counts are limited and a room reset is provided.
- Wire the game flow: start screen -> farm -> break -> backrooms rooms -> ending.
- Out of scope: cursed/failure crops, free-form crop placement, procedural levels, saving, multiple escapes beyond three rooms. Room 3 is the first cut if time runs out.

## Capabilities

### New Capabilities
2D farm:
- `farm-planting`: plant seeds on plots and watch crops grow.
- `farm-harvesting`: harvest mature crops into the inventory.
- `villager-selling`: sell crops to villagers for coins; quick first cycle.

The break:
- `oversell-break`: villagers keep asking; over-selling (or idling) starts the break.
- `fall-transition`: the input-locked glitch-and-fall sequence into the backrooms.
- `seed-carryover`: seeds (only) carry into the backrooms, with a minimum top-up.

3D backrooms:
- `first-person-controls`: keyboard movement and mouse look.
- `backrooms-collision`: walls, floors, grown-crop surfaces, and gravity.
- `room-progression`: three hand-built rooms, exits, advancing, and the ending.
- `billboard-assets`: old farm sprites as camera-facing billboards.

Seed puzzles:
- `seed-types`: beanstalk, pumpkin, and vine and the structure each grows.
- `plot-planting`: plant a chosen seed on fixed plots with visible timed growth.
- `room-puzzles`: limited seed allotments and combination-required rooms.
- `tutorial-room`: the half-grown demo crop in the first room.
- `room-reset`: reset the current room.

### Modified Capabilities

None (no existing specs).

## Impact

- `main.lua`: input handling already supports keyboard/mouse latches and `mousemoved` forwarding; 3D states must render outside `push` (depth buffer, per README).
- `src/states/game/`: new `FarmState`, `BackroomsState` (plus transition handling) registered in the state machine; `StartState` leads into the farm.
- `src/Dependencies.lua`: load new states, textures, models, sounds.
- `g3d/` (camera, collisions, model) used as-is; `lib/knife` Timer for growth and glitch tweens.
- Asset directories (`graphics/`, `sounds/`, `models/`, `shaders/`) are being filled in by the user in parallel; code must tolerate placeholder assets.
