# Verification: backrooms-zones-variety-audio

Branch `feature/farm-to-backrooms`. Status at writing: **implemented; the automated suite has NOT been run on this final state** (the orchestrator runs `sh tests/check_all.sh` next). Everything below marked "unverified" is code/tests written but not yet executed.

## Implemented
- Zones: threshold-only boundaries, per-zone theme + lighting, blend at thresholds. Neighbour colouring is now an exact backtracking graph colouring (themes and lightings independently, most-connected first, 20000-step cap); only if a pool cannot colour the adjacency graph (3 themes vs. a K4) does the old least-shared fallback run, and `tests/zones_lighting.lua` 2.2 / the `neighbor-clash` line in `tests/zone_maps.lua` flag it (never silent).
- Shapes: pillared hall, atrium, 2x3, L, 1x2, gallery, closet. Fix in this pass (`src/LevelGen.lua` step 3b): candidates were shuffled together, and the far more numerous 1x2/gallery sites used up `ROOM_SHAPE_MAX` before pillared/atrium/2x3/L were tried, and pillared/atrium rolled only 0.18/0.135 on 1-3 eligible sites. Now large shapes are tried first (pillared, atrium, 2x3, L), at most `ROOM_SHAPE_MAX-2` of them so small shapes still appear, and the first eligible pillared hall / atrium is taken (`ROOM_SHAPE_BIG_CHANCE = 1`, weight 0 still disables). Eligibility (`usable`: same region/elevation, no module/start/exit/optional cell, no open edge leaving the stamp) is unchanged, so region/gate isolation and solvability rules are untouched. Same seed still reproduces the same layout (own RNG stream).
- Audio: hum is owned by `BackroomsState` (created in `enter`, disposed in `exit`). Spec: silent at start, farm, fall, ending. The fall is the farm break (`FarmState:startBreak/updateBreak`), which creates no backrooms audio; the hum starts when the state changes to `backrooms`.

## Evidence captured (real LÖVE 11.5 under Xvfb, generation + rendering only, no test run)
Dir `/workspace/qa/zones/final/`.
- Zone maps (real metadata): `seed2026-L2..L14.png` (the game has 4 levels, tutorial + L2-L4; L5-L14 are map-tool-only extra levels) and `seed1-L2..L4.png`, `seed7-L2..L4.png`. All printed `neighbor-clash=0 entities-without-zone=0`; all borders `door/ok` (none MIDROOM).
- Shape counts, seed 2026 maps: pillared L5 L7; atrium L8 L14; 2x3 L5 L9 L11; L rooms in nearly every level. Real-game levels (L2-L4): seed 1 L3 atrium, L4 pillared; seed 7 L4 atrium + 2x3.
- Screenshots (no ABSENT substitutions): `shots-seed1/L4-shape-pillared.png`, `shots-seed1/L3-shape-atrium.png`, `shots-seed1/L3-shape-roomL.png`, `shots-seed1/L3-zone-transition.png`, `shots-seed7/L4-shape-atrium.png`, `shots-seed7/L4-shape-room2x3.png`, `shots-seed7/L4-shape-roomL.png`. Earlier seed-2026 zone/lighting/closet/gallery shots in `shots/` predate the shape fix (generation for L2-L4 seed 2026 is unchanged in colouring but shapes in L2-L4 shifted slightly; re-shoot if needed).
- Pillared and atrium shots were viewed: real pillars/raised-ceiling atrium. The seed-7 atrium zone is near-dark by design.

## Unverified (needs the suite)
- `sh tests/check_all.sh`: all of it, including `tests/zones_shapes.lua` (pillar clearance, physical hall walks, "every enabled shape generated" over 100 seeds x 3 difficulties with the new ordering), `tests/zones_lighting.lua`, `tests/zones_audio.lua`, the 210-level physical sweep and reachability (the shape change alters which stamps fire, so these must be re-run).
- New check `zones_audio.lua` 1.3b (silent fall via a scripted `farm:startBreak` then `updateBreak`); it uses the real glitch asset in the mocked runtime and may need a tweak.
- Counts: not yet available.

## Manual listening (user manual, nothing automated covers it)
1. Start screen, farm and the glitch/fall: no hum, no rug footsteps.
2. On landing in the backrooms: hum fades in over ~1 s, loops, quiet.
3. Walk: rug footsteps audible over the hum, varied; none while falling/climbing/standing.
4. Reach the ending: hum stops. Esc to start: silence. Re-enter a run: hum starts again once.
5. Walk through several zones: lighting/wall theme changes at thresholds only, never mid-room.

## Known limits
- Rooms with only 1-3 eligible big-shape sites still depend on the maze layout: levels without an eligible 3x3 / plus-shaped site have no pillared hall or atrium (seed 2026 L2-L4 has none; seeds 1, 7 do).
- Theme pool has 3 values, so a K4 zone adjacency graph cannot be properly coloured; the fallback keeps minimal clashes and the zone-map clash counter exposes them. Lighting has 4 values and always colours planar graphs when the backtracker finishes within its cap.
- Software GL screenshots only; no real-GPU or human playthrough.
