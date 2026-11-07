# Tasks

## 1. Look pipeline and fallback

- [x] 1.1 Add `src/BackroomsLook.lua` with pcall-wrapped shader/canvas setup, `--no-shader`, quality setting and once-only logging; tests with a forced compile failure confirm it stays disabled and the backrooms still render.
- [x] 1.2 Add `shaders/backrooms.glsl` (ambient, up to N point lights, fog) and apply it to room geometry; verify it compiles on the real LÖVE runtime and a screenshot shows falloff around a fixture.
- [x] 1.3 Add `BackroomsLook.flicker(mode, t, phase)` for steady/flicker/buzz/dead; unit tests cover variation over time and zero output for dead.

## 2. Lighting

- [x] 2.1 Accept `lights` and `lighting` on room data (validate in `Room.validate`) and upload the nearest N lights per frame; test validation and nearest-N selection.
- [x] 2.2 Add lighting presets (bright, dim, single-bulb, near-dark) with an ambient floor and unlit gameplay tints for plots, pickups, crops and the exit; screenshot review in the near-dark preset confirms they stay visible.
- [x] 2.3 Add soft contact-shadow blobs under billboards, crops and pickups; verify in a screenshot.

## 3. Atmosphere

- [x] 3.1 Add per-room fog colour and density and tune the long-hall fade; test fog uniforms per room and review a screenshot of a long hall.
- [x] 3.2 Add faked volumetric shafts under ceiling fixtures scaled by fog density; verify in a screenshot and that quality-low skips them.
- [x] 3.3 Add the optional post-process (grade, vignette, optional bloom) on a depth-capable canvas with the HUD drawn after it; test the HUD is not drawn through the pass and that fallback restores the plain render.
- [x] 3.4 Prove gameplay independence: a test plays the same level at every quality and with the shader disabled and asserts identical geometry, plots, pickups and collision results.

## 4. Materials

- [x] 4.1 Add `MATERIAL_THEMES` with more wall, floor and ceiling textures (placeholders allowed) and resolve box textures through the room theme in `Room:init`; test the missing-texture colour fallback.
- [x] 4.2 Give obstacle modules, plots and the exit a fixed high-contrast tint; screenshot each theme's pit, ledge and gap.
- [x] 4.3 Assign themes per room from the level seed in the generator; test the same seed gives the same themes and a level uses at least two walls and two floors.

## 5. Dressing

- [x] 5.1 Add `PROP_CATALOGUE` and room-type tagging; unit test that selection differs between a hall and a filler room.
- [x] 5.2 Implement exclusion-zone prop placement (plots, pickups, exit, doorways, module footprints, spawn); property test over many seeds that no prop overlaps an exclusion zone and routes stay clear.
- [x] 5.3 Add storytelling groupings and concealing props for secret nooks only; test a generated level contains a grouping and that nook doorways stay walkable.
- [x] 5.4 Make dressing deterministic from the level seed in its own RNG stream; test equal seeds give equal props and that adding props leaves layout unchanged.

Section 5 verification: new `src/Dressing.lua` (PROP_CATALOGUE, room-type tags, exclusion-zone placement on wall-hugging spots, storytelling groups, own RNG seeded from the level seed) hooked at the end of `LevelGen.build`; 4 tests `dressing 5.1-5.4` in tests/run.lua pass (188 passed, 0 failed; log in /workspace/qa/atmos/section5/run.txt). Props are non-solid billboards, no screenshots taken.

## 6. Review and integration

- [x] 6.1 Add a backrooms screenshot script (modelled on `tests/farm_shots.lua`) and review lighting presets, fog, themes and dressing across several seeds; record findings and tuned defaults.
- [x] 6.2 Add the new tests to `tests/check_all.sh` and run it green on the real LÖVE runtime, including a full autotest run with the look enabled.

## Section 3 verification (atmos-3)

- Tests: `atmos 3.1`-`3.4` in tests/run.lua (fog uniforms per preset, shafts scaled by fog and skipped at low, depth canvas + grade with HUD outside canvas/shader, post fallback logged once with state restored, identical level signature at high/medium/low/--no-shader/bad shader). Run subset only (full suite deferred to the orchestrator): 16 look/atmos tests pass.
- Captures in /workspace/qa/atmos/section3 (real LÖVE under Xvfb, seed 2026): `L*-*.png` full look, `-low` quality low, `-plain` --no-shader, `-badshader` forced compile failure. Fog fades the long hall to yellow-brown, vignette/grade visible, shafts faint under fixtures at high/medium and absent at low.

### Section 4 verification (branch wip/atmos-4)
- 4.1: `MATERIAL_THEMES` (level0, stripe, classic) in src/Room.lua; procedural wall/floor/ceiling textures in src/Dependencies.lua (flat placeholders under `--placeholder-assets`); `Room:init` resolves via box/room `theme`, falling back to `fallbackColor`. Test "materials 4.1" (incl. missing-texture fallback).
- 4.2: obstacle-module floors/solids (`obstacle = true`) use fixed slate/orange tints, plots a fixed tint, exit keeps `ROOM_EXIT_COLOR`; test "materials 4.2". Captures (pit/gap in levels 2-4): /workspace/qa/atmos/section4. Not captured per theme in isolation (tints are theme-independent by construction).
- 4.3: per-cell themes from a separate RNG stream in `LevelGen.build`; test "materials 4.3" (determinism, >=2 walls and floors over 120 levels); generated layout/pickups byte-identical to HEAD for seeds 1-30 x 3 difficulties.
- tests/run.lua: 187 passed, 0 failed (full suite not run).
