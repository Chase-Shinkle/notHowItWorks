# Design

## Context

LÖVE 11.5, Lua. The scaffold has a string-keyed `StateMachine` (`src/StateMachine.lua`), `push` for a 320x320 virtual resolution (`main.lua` wraps all rendering in `push:apply`), `lib/knife` Timer, and `g3d` (model, camera, collisions). `g3d.camera.firstPersonMovement`/`firstPersonLook` exist, and `main.lua` already forwards `mousemoved` to the current state. `g3d` sets `setDepthMode("lequal", true)` at load. Asset folders are empty and being filled by the user in parallel. See proposal.md for motivation and scope.

## Goals / Non-Goals

**Goals:**
- Two top-level play states (2D farm, 3D backrooms) joined by a scripted break, sharing a small data table.
- Puzzle content defined as data so rooms can be added or cut cheaply.
- Playable with placeholder (untextured / flat-color) assets.

**Non-Goals:**
- Procedural generation, saving, free-form crop placement, failure crops, general physics.

## Decisions

1. **Render 3D outside `push`.** The farm renders inside `push:apply`. `BackroomsState` needs a depth buffer, so `love.draw` must let the active state opt out of push (e.g. state flag `usesPush`), drawing 3D directly to the screen and the HUD at native resolution. *Alternative:* a depth canvas through push; rejected as more setup and blurrier scaling for little gain.

2. **Shared game data table.** A single table `{seeds = {beanstalk=n, pumpkin=n, vine=n}, coins, crops, hasSold}` is passed through `gStateMachine:change(name, data)`. Only `seeds` is read by the backrooms. *Alternative:* a global; rejected to keep state flow explicit, but a global is acceptable if time is short.

3. **Break is a farm sub-sequence.** `FarmState` detects an over-sell (after `hasSold` is true), runs a Timer-driven glitch (shake, offsets, fall), then changes to `backrooms`. Input is ignored while it plays. A villager keeps requesting crops to nudge the over-sell.

4. **Rooms as data.** Each room is a table: wall/floor boxes, plot positions, allowed seed counts, exit position, optional pre-grown demo crops. A single `Room` builder converts this into g3d models. Adding or cutting Room 3 is a data change.

5. **Seeds as growth rules.** Each seed type defines a final scale and growth axis; growth is a Timer tween on the g3d model scale. Collision uses g3d's `capsuleIntersection`/`sphereIntersection` against all room and crop models, with the player as a capsule and simple gravity. Standing on a structure is walking on its top face, so ladders are modelled as a climbable beanstalk volume (while inside it the player moves up) rather than true ladder physics.

6. **Billboards for farm assets.** Old farm sprites are drawn as camera-facing quads, with yaw set from the camera direction. *Alternative:* real 3D crop models; rejected for time.

7. **Fixed plots only.** Planting is context-sensitive: the nearest plot within range of the player. This avoids placement geometry bugs and makes every room hand-verifiable.

8. **Placeholder-first.** All art and audio are loaded through `Dependencies.lua` tables with fallbacks to flat colors, so gameplay does not block on assets.

## Risks / Trade-offs

- [Player controller feels bad (collision jitter, getting stuck)] → Use a simple capsule with slide-on-contact, test early (before puzzles), keep rooms made of large boxes.
- [Depth buffer / push interaction bugs] → Do the push opt-out first as a spike; the 2D farm is unaffected.
- [Solvability bugs from seed combinations] → Rooms are hand-verified; a room reset is always available; spare seeds in each allotment.
- [Over-sell may not be discovered] → Villager dialogue repeatedly asks for more; a fallback timer-based break if the player is idle too long.
- [24-hour budget] → Order work farm -> break -> movement -> tutorial room -> second room; Room 3 is the first cut.
