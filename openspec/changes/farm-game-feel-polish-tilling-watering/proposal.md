# Proposal

## Why

The farm works but still feels like an MVP: the field is one repeated grass tile with bare plots, the player and the buyer are the same sprite, every action is silent and instant, and the loop is only plant, harvest, sell. A jam build is judged on feel, so this change adds game feel, a more polished look, and two more verbs (tilling and watering) to the 2D farm, without touching the backrooms.

## What Changes

- **Game feel**: particle bursts and a pop on plant, till, water, harvest and sale; a harvested crop icon flies to its HUD slot; the coin counter ticks up and down; plots squash and stretch when a crop reaches its next stage; soft sound effects (the `sounds/` folder is empty today, so the effects are generated as part of this change).
- **Tilling and watering**: an empty plot must be tilled before it takes a seed (and stays tilled after harvest). A planted crop is watered once; watered crops grow at full speed, unwatered ones at half speed. Both are context-sensitive uses of the existing use key, with the tool shown in the hint bar and near the farmer. **BREAKING** for the farm: the first use on a fresh plot now tills instead of planting, so the first cycle needs one more press and the unwatered cycle takes about twice as long.
- **World dressing**: fence pieces flanking the plot block, a dirt path to the villager and stall, the barn behind the villager, a well, berry bushes, a small pond, ground variation (tufts, stones) and soft drop shadows, with gentle idle sway. Tiles that block movement are not walkable, and every plot stays reachable.
- **HUD polish**: a coin icon, a divider between seed bags and harvested produce, dimmed empty slots, and a day counter.
- **Day cycle**: a short repeating day (dawn, day, dusk, night) that tints the field and increments the day counter.
- **Characters**: the villager gets its own sprite (different hair, an apron, a hat) so the player and buyer are distinguishable in a screenshot.
- **Shaders (new, farm only)**: one post-process pass over the farm canvas for warm sun tint and light shafts, soft bloom, glimmer on ripe crops and water, and the day/night grade. It falls back to plain drawing if it fails to compile. The backrooms stays plain.
- **Corn label**: the `vine` seed type is shown to the player as "corn" everywhere the farm and HUD name it. The sprites and the internal key stay as they are.
- Out of scope: new art for corn, trees or any other missing sprite (bushes stand in for trees), backrooms visual changes, changes to the break timing or carry-over rules, music (the farm music slot stays a placeholder).

## Capabilities

### New Capabilities
- `farm-juice`: particles, pops, flying pickups, the coin ticker, growth-stage squash and sound effects for farm actions.
- `farm-plot-care`: tilling and watering rules, growth rate, and how they gate and speed up planting.
- `farm-world-dressing`: fence, path, barn, well, bushes, pond, ground variation, shadows, idle motion and walkability of dressing.
- `farm-hud`: coin icon, seed/produce divider, dimmed empty slots, day counter.
- `farm-day-cycle`: the repeating day, its tint and its counter.
- `farm-characters`: distinct villager appearance and the tool shown on the farmer.
- `farm-shaders`: the post-process pass, its tunables and its safe fallback.
- `crop-display-names`: the player-facing names of the seed types.

### Modified Capabilities
None. `openspec/specs/` is empty because `farm-to-backrooms-crop-escape` and `polish-rendering-release-playfeel-seed-shop` are not yet archived. The plant-on-first-press behavior and the 12 s growth that this change alters are described there and in `README.md`, and are updated with this change.

## Impact

- `src/Farm.lua` (tilled/watered plot state, growth advanced by elapsed time instead of a fixed timer, rates), `src/constants.lua` (tuning, layout, day length, shader and effect constants, display names), `src/Dependencies.lua` (new textures, sounds, shader).
- `src/states/game/FarmState.lua` (tool uses, effects, rendering, HUD, day cycle), new modules for particles/tweens and the farm shader, `shaders/` (GLSL), `sounds/` (generated effects), new villager art in `graphics/`.
- `tools/` (sound and villager-sprite generators), `tests/` (growth, tilling/watering, reachability of plots, shader fallback, autotest steps), `README.md`, `RELEASE.md`.
- Backrooms code and `src/rooms.lua` are untouched except that the backrooms HUD uses the same display names.
