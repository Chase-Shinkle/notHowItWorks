# Tasks

## 1. Look pipeline and fallback

- [ ] 1.1 Add `src/BackroomsLook.lua` with pcall-wrapped shader/canvas setup, `--no-shader`, quality setting and once-only logging; tests with a forced compile failure confirm it stays disabled and the backrooms still render.
- [ ] 1.2 Add `shaders/backrooms.glsl` (ambient, up to N point lights, fog) and apply it to room geometry; verify it compiles on the real LÖVE runtime and a screenshot shows falloff around a fixture.
- [ ] 1.3 Add `BackroomsLook.flicker(mode, t, phase)` for steady/flicker/buzz/dead; unit tests cover variation over time and zero output for dead.

## 2. Lighting

- [ ] 2.1 Accept `lights` and `lighting` on room data (validate in `Room.validate`) and upload the nearest N lights per frame; test validation and nearest-N selection.
- [ ] 2.2 Add lighting presets (bright, dim, single-bulb, near-dark) with an ambient floor and unlit gameplay tints for plots, pickups, crops and the exit; screenshot review in the near-dark preset confirms they stay visible.
- [ ] 2.3 Add soft contact-shadow blobs under billboards, crops and pickups; verify in a screenshot.

## 3. Atmosphere

- [ ] 3.1 Add per-room fog colour and density and tune the long-hall fade; test fog uniforms per room and review a screenshot of a long hall.
- [ ] 3.2 Add faked volumetric shafts under ceiling fixtures scaled by fog density; verify in a screenshot and that quality-low skips them.
- [ ] 3.3 Add the optional post-process (grade, vignette, optional bloom) on a depth-capable canvas with the HUD drawn after it; test the HUD is not drawn through the pass and that fallback restores the plain render.
- [ ] 3.4 Prove gameplay independence: a test plays the same level at every quality and with the shader disabled and asserts identical geometry, plots, pickups and collision results.

## 4. Materials

- [ ] 4.1 Add `MATERIAL_THEMES` with more wall, floor and ceiling textures (placeholders allowed) and resolve box textures through the room theme in `Room:init`; test the missing-texture colour fallback.
- [ ] 4.2 Give obstacle modules, plots and the exit a fixed high-contrast tint; screenshot each theme's pit, ledge and gap.
- [ ] 4.3 Assign themes per room from the level seed in the generator; test the same seed gives the same themes and a level uses at least two walls and two floors.

## 5. Dressing

- [ ] 5.1 Add `PROP_CATALOGUE` and room-type tagging; unit test that selection differs between a hall and a filler room.
- [ ] 5.2 Implement exclusion-zone prop placement (plots, pickups, exit, doorways, module footprints, spawn); property test over many seeds that no prop overlaps an exclusion zone and routes stay clear.
- [ ] 5.3 Add storytelling groupings and concealing props for secret nooks only; test a generated level contains a grouping and that nook doorways stay walkable.
- [ ] 5.4 Make dressing deterministic from the level seed in its own RNG stream; test equal seeds give equal props and that adding props leaves layout unchanged.

## 6. Review and integration

- [ ] 6.1 Add a backrooms screenshot script (modelled on `tests/farm_shots.lua`) and review lighting presets, fog, themes and dressing across several seeds; record findings and tuned defaults.
- [ ] 6.2 Add the new tests to `tests/check_all.sh` and run it green on the real LÖVE runtime, including a full autotest run with the look enabled.
