# Proposal

## Why

The backrooms are drawn with flat, unlit textured boxes: the same yellow walls, floor and ceiling everywhere, with four billboards per room. Generated levels (see `procedural-backrooms-levels`) will be many and varied, and they need to look and feel like unsettling liminal spaces: lit by flickering lights, fogged, textured with variety, and dressed with abandoned objects. The farm already has a look pipeline (`FarmShader`); the backrooms deliberately do not use it.

## What Changes

- Add per-pixel lighting and fog to backrooms geometry through a g3d fragment shader: light fixtures with falloff, varied ambient per room, distance fog, and soft contact shadows under props, crops and the player.
- Add flickering and varied lighting conditions: steady, flickering, buzzing and dead fixtures, and rooms lit differently (dim, bright, a single bulb, near-dark).
- Add atmosphere: fog colour and density per room, faked volumetric light (shafts under fixtures), and a lightweight post-process (grade, vignette, optional bloom) with a safe fallback to the plain render.
- Add more wall, floor and ceiling textures and a per-room material theme so rooms differ.
- Add environmental dressing: furniture, props and abandoned objects, and small storytelling groupings, placed by the level generator by room type.
- A visual quality setting and `--no-shader` flag to turn effects off or down; gameplay and collision never depend on the effects.
- Out of scope: objectives/HUD redesign, new gameplay, real-time shadow maps, 3D prop models (props stay billboards), audio changes, farm visuals.

## Capabilities

### New Capabilities
- `backrooms-lighting`: light fixtures, falloff, flicker and per-room lighting conditions, plus contact shadows.
- `backrooms-atmosphere`: fog, faked volumetric light, the post-process look, and safe fallback.
- `backrooms-materials`: wall, floor and ceiling texture variety and per-room themes.
- `backrooms-dressing`: furniture, props, abandoned objects and storytelling groupings placed by room type.

### Modified Capabilities

None. There are no archived specs; `billboard-assets` exists only in the unarchived `farm-to-backrooms-crop-escape` change and is extended here, not contradicted.

## Impact

- New `shaders/backrooms.glsl` (and a post-process shader if enabled) and `src/BackroomsLook.lua` (shader loading, uniforms, fallback), mirroring `FarmShader`'s safe-fallback pattern.
- `src/Room.lua`: build with the look shader; accept `lights`, `lighting`, `fog`, `theme` and `props` data; draw order for shafts and shadows.
- `src/Billboard.lua`: shadow blobs and light response for billboards.
- `src/constants.lua`, `src/Assets.lua`: material themes, texture keys, prop catalogue, quality settings.
- `src/LevelGen.lua` (from `procedural-backrooms-levels`): assign theme, lighting and props per room; this change depends on that one for generated levels but the tutorial and authored rooms can adopt the look first.
- `graphics/backrooms/`: new texture and prop art (placeholders tolerated).
- `tests/`: shader compile and fallback tests, uniform tests, a screenshot script (like `tests/farm_shots.lua`) for review.
