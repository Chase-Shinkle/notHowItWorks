# Design

## Context

Backrooms boxes are built by `Room:init` with per-face baked shade (`faceShade` in `src/Room.lua`) and three textures (`graphics/backrooms/{wall,floor,ceiling}`). Billboards (`src/Billboard.lua`) are camera-facing sprites. `love.draw` renders 3D states straight to the screen with a depth buffer (`usesPush == false`), then the HUD at native resolution. g3d's vertex shader (`g3d/g3d.vert`) already exposes `worldPosition`, `viewPosition` and `vertexNormal` varyings, so a custom fragment shader can light and fog per pixel. The farm has a multi-pass post-process (`src/FarmShader.lua`) with a pcall-wrapped safe fallback; the backrooms never used it. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- A convincing liminal look at low cost: per-pixel fixture lighting, fog, flicker, texture and prop variety.
- Effects are purely visual and always optional, with a tested fallback.
- Look data (theme, lights, fog, props) lives in the room data, so the generator and authored rooms both supply it.

**Non-Goals:**
- Real-time shadow maps, ray-marched volumetrics, 3D prop models, gameplay changes, farm visuals.

## Decisions

1. **One g3d fragment shader for geometry** (`shaders/backrooms.glsl`): ambient + up to N point lights (N fixed, e.g. 8) from a uniform array with distance falloff, flicker multiplier per light, and exponential distance fog. Alternative: bake lighting into vertex colours, rejected because flicker needs per-frame intensity and baked colours would force rebuilding meshes.
2. **Light budget per room.** A room supplies `lights = {{pos, color, intensity, radius, mode}}` with `mode` in steady | flicker | buzz | dead. Each frame the nearest N lights to the camera are uploaded. Alternative: all lights, rejected as uniform-array size grows with generated levels.
3. **Flicker is a pure function of time and a per-light phase** (`BackroomsLook.flicker(mode, t, phase)`), so it can be unit tested and never touches gameplay or RNG.
4. **Lighting conditions are presets** (bright, dim, single-bulb, near-dark) setting ambient floor, fixture mix and fog. A minimum ambient floor and unlit tints for plots, pickups, crops and the exit guarantee readability in the darkest preset.
5. **Contact shadows are blob quads** (soft radial alpha disc drawn just above the floor under billboards, crops and pickups), not shadow maps. They are drawn before billboards, depth-tested, and cost a draw per object.
6. **Faked volumetrics**: additive, camera-facing-in-yaw soft cone/glow quads under ceiling fixtures, intensity scaled by fog density. No ray marching.
7. **Post-process is optional and small**: reuse the `FarmShader` pattern (compile/canvas creation in pcall, log once, `--no-shader`) in `src/BackroomsLook.lua`. A single-pass grade + vignette (+ cheap bloom by reuse of the farm's blur chain at 160/80 px if time permits). The 3D scene goes to a native-resolution canvas with depth, then the pass, then HUD. Alternative: skip the post-process entirely and ship lighting+fog only; this is the first cut if time runs out.
8. **Fallback ladder**: full -> no post-process -> no look shader (plain textured render as today). Each rung is chosen by pcall results or the quality setting; gameplay code never branches on it.
9. **Materials as themes**: `MATERIAL_THEMES[name] = {wall, floor, ceiling, tint, fallbackColor}`. A room carries `theme`; `Room:init` resolves per-box textures through the theme. Obstacle modules (pit sides, ledge blocks, plots, exit) use a fixed high-contrast tint independent of the theme.
10. **Dressing from a prop catalogue** (`PROP_CATALOGUE[name] = {texture, height, tags, solid=false}`) filtered by room-type tags; the generator places props on a coarse grid, rejecting cells that overlap plots, pickups, exits, doorways, module footprints and the spawn. Storytelling groupings are small prefab arrangements stamped in free cells. Props are billboards, so they add no collision; any `solid` prop would be added to the reachability sweep. Concealing props are only used on secret-nook doorways (see `procedural-backrooms-levels`).
11. **Determinism**: all look choices come from the same level seed via the generator's RNG, in a separate stream from layout so adding a prop does not change layout.
12. **Order of work**: lighting+fog on the existing authored rooms first (proves the shader), then materials and dressing in the generator.

## Risks / Trade-offs

- [Dark rooms unplayable] → Ambient floor, unlit gameplay tints, readable-darkest scenario test via screenshot review.
- [GPU/driver differences] → pcall compile, fallback ladder, `--no-shader`, quality setting.
- [Frame cost from many lights/blobs] → light budget N, blob count cap, cheap shafts.
- [Visual noise hides obstacles] → fixed high-contrast obstacle tint, dressing exclusion zones.
- [Depends on generator] → authored rooms adopt the look first; generated-level hooks land when `procedural-backrooms-levels` does.
- [Art not ready] → placeholder-tolerant textures and props with colour fallbacks.

## Migration Plan

Additive. Rooms without look data render with defaults (ambient light, no fog), so existing authored rooms and tests keep working. Rollback is the fallback ladder's last rung.

## Open Questions

- Light budget N and quality-preset values; tune on target hardware.
- Whether bloom is worth the extra passes versus lighting+fog alone.
