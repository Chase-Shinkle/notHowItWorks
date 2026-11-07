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

9. **Seed policy: carry-over into Room 1, fixed allotments after.** (Added during task 4.3/4.5.) The seed-carryover spec says the player "holds the seeds they had at the break", while room-puzzles says on entering a room "their seeds equal that room's allotment". These conflict for Room 1, so Room 1 is an explicit exception to the room-puzzles wording; the requirement text is unchanged:
   - Room 1, first entry: the carried farm seeds are kept and each type is topped up to Room 1's allotment, which is the minimum (`FIRST_ROOM_MIN_SEEDS` must equal it).
   - Rooms 2 and 3: seeds are exactly the room's fixed allotment; leftovers do not carry forward.
   - Room reset restores the seeds recorded on entering the current room. For Room 1 that is the topped-up farm seeds, not the bare allotment.
   - The debug skip from the farm (F1) uses the same `CarryOverGameData` hand-off as the break, so coins and crops never reach the backrooms.
   Implemented in `RoomStartingSeeds` (`src/GameData.lua`).

10. **g3d used as-is in the backrooms.** Mouse look is `g3d.camera.firstPersonLook` (it turns on relative mouse mode itself), and the camera is placed with `lookInDirection`, never `lookAt`: g3d's `lookAt` derives yaw and pitch with a y-up formula that does not match `lookInDirection`/`firstPersonLook` (z-up). Walking does not use `firstPersonMovement`, because that moves the camera freely (including Space/Shift flying) with no collision. A capsule controller moves the player and the camera follows its eye point. `g3d.collisions` ignores model rotation, so all room colliders are axis-aligned boxes.

11. **Crops: growth, collision and climbing.** (Added during section 5.) `CROP_DEFS` (`src/Crop.lua`) gives each seed a full size, growth axes and grow time: beanstalk 0.8 x 0.8 x 3.0 m grows along z, pumpkin 2.6 x 2.6 x 1.0 m grows along x, y and z, vine 6.0 x 1.2 x 0.3 m (top level with its plot) grows along the plot's `dir`. Growth is a knife `Timer.tween` of `progress` in `BackroomsState`'s own Timer group. Only the draw model is scaled.
   - A crop has no effect until it is fully grown: it is not solid and cannot be climbed. A grown solid crop also waits until the player's box is clear of it before it turns solid, so finishing growth never traps or shoves the player.
   - g3d's collision code scales vertex normals by `scale_x` only, so crop colliders never carry a scale. Their vertices are built at the full grown size and their collision transform is a translation only. The scaled draw model is never passed to `g3d.collisions`. g3d itself is unchanged.
   - A beanstalk is a climb volume, not a solid. Climbing starts with forward input while standing inside it, and continues while the player stays inside. There is no gravity while climbing: forward climbs at `BACKROOMS_CLIMB_SPEED`, back climbs down, otherwise the player holds on. The feet are capped at the top, and the player leaves by walking off sideways. A falling player is not caught. This is what stops a beanstalk planted in a pit from working as a pole across it.
   - A tutorial demo crop is a frozen part-grown crop (`demoCrops`). Its plot only takes a seed of its own type, which resumes growth from where it is.
   - Planting uses the nearest plot within 1.8 m horizontally and 1.6 m vertically of the feet. A plot holds one crop. Nothing is consumed when planting fails.

12. **Section 5 room geometry.** The controller has no jump and no step-up: a 1 m ledge already blocks it. So:
   - A pumpkin's top can only be walked on where it grows in a pit exactly 1.0 m deep. There it fills the pit level with the floor.
   - Height only comes from beanstalks (3.0 m of climb), and gaps are only crossed by vines (6 m long).
   - Pits and gaps are voids with `killZ = -0.5`. A fall respawns the player at the spawn with crops and seeds kept, so a fall is never a soft-lock. Pit plots sit on decorative non-solid soil columns, so a falling player cannot land on one.
   Rooms:
   - Room 1 has one plot, holding a half-grown beanstalk 0.8 m in front of a 2.6 m ledge, with the exit on the ledge. The exit marker can be seen from the spawn over the ledge lip.
   - Room 2 is a 2.6 m pit (pumpkin), then a 4 m gap (vine). Its allotment is pumpkin 2, vine 2 and no beanstalks.
   - Room 3 is a 2.6 m pit (pumpkin), a 2.6 m ledge (beanstalk), then a 4 m gap at ledge height (vine), with a 6 m ceiling. Its allotment is 2 of each.
   Why the wrong seeds fail, with margins:
   - **Beanstalk in a pit.** A player standing on the rim is at least 1.0 m from the plot centre, horizontally. Overlapping the climb volume needs 0.4 + 0.3 = 0.7 m, so climbing cannot start: 0.3 m margin.
   - **Beanstalk at a gap edge, then walking off the top.** The fall distance is d = v * sqrt(2h / g) = (4/3) * sqrt(h) m. In Room 3 the ceiling caps the feet at 4.3 m, so h = 1.7 m above the far side. The player leaves the volume 0.7 m past the plot centre, which is 0.8 m before the edge, and lands within about 0.24 m of an edge. That gives about 1.9 m past the edge, against a 4 m gap. The coarse search's furthest x over the Room 3 gap was 4.99, so about 1 m short of the far edge at x = 6.
   - **Vine in a pit.** Its top is 1.0 m below the floor, under `killZ`.
   - **Pumpkin on flat floor or at a gap edge.** A 1 m wall that cannot be climbed.
   - **Vine at Room 3's beanstalk plot.** It grows along +y, so it is flat floor and does not run under the gap.
   - **Planting across an obstacle.** Every plot past an obstacle is more than 1.8 m from the near side.
   Carried farm surplus only reaches Room 1, whose only plot is the demo plot, and that plot refuses other types. Rooms 2 and 3 get exactly their allotment.
   Checked by `tests/reach.lua`, a coarse breadth-first search over the real controller (8 directions, 0.25 s actions, 0.4 m cells). `tests/run.lua` runs the key cases; `tests/reachability.lua` runs every plot assignment.

## Risks / Trade-offs

- [Player controller feels bad (collision jitter, getting stuck)] → Use a simple capsule with slide-on-contact, test early (before puzzles), keep rooms made of large boxes.
- [Depth buffer / push interaction bugs] → Do the push opt-out first as a spike; the 2D farm is unaffected.
- [Solvability bugs from seed combinations] → Rooms are hand-verified; a room reset is always available; spare seeds in each allotment.
- [Over-sell may not be discovered] → Villager dialogue repeatedly asks for more; a fallback timer-based break if the player is idle too long.
- [24-hour budget] → Order work farm -> break -> movement -> tutorial room -> second room; Room 3 is the first cut.
