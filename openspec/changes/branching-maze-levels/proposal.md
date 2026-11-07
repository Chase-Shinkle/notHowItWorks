# Proposal

## Why

The layout planned in `procedural-backrooms-levels` is a chain of obstacles joined by filler, which in play is one long hallway with a few side nooks. You cannot get lost in it, there is one plot per obstacle so there is nothing to decide, and levels would be short. We want levels that turn, branch, loop and sprawl, with several plots whose crops can lead you somewhere useful or to a dead end, and a seed economy where trying things is cheap.

## What Changes

- Replace the corridor-plus-filler layout with a 2D branching maze on a cell grid: turns, T and X junctions, loops, wide rooms, and several routes, so players can lose their way. The critical path to the exit winds through it and is never a straight line.
- Add many plots per level, not only plots that solve the chain. Branch plots sit beside optional obstacles that grow into alcoves, shortcuts and dead ends, so growing something can be a mistake or a detour as well as progress.
- Make uprooting refund the seed. Trying a crop becomes cheap, but you still hold few seeds, so you must uproot crops in places you are done with.
- Make levels longer: larger grids and a minimum length for the critical path, so a level takes minutes, not seconds.
- Respawn after a fall at the last safe checkpoint (the entrance of the region you are in) instead of the level spawn, because levels are long.
- **BREAKING** relative to `procedural-backrooms-levels` (not yet implemented): its straight-chain layout, its "seed is not refunded" uproot rule and its short level sizes are superseded by this change. Obstacle modules, the generate-the-solution-first approach, seed tiers, seeded determinism and the tutorial are kept.
- Out of scope: a minimap or compass (getting lost is wanted), new crop types, real 3D ramps and stairs, lighting/props (see `backrooms-visual-atmosphere`; this change only provides landmark hooks).

## Capabilities

### New Capabilities
- `maze-layout`: a branching, looping, turning 2D layout with a winding critical path, recognizable landmarks and no straight-hallway levels.
- `branch-plots`: multiple plots per level including optional and decoy obstacles that lead to rewards or dead ends.
- `seed-refund`: uprooting returns the seed to the player's stock.
- `level-length`: minimum level size and critical-path length, and how they scale with level index.
- `checkpoint-respawn`: respawning at the last safe checkpoint after a fall.

### Modified Capabilities

None. There are no archived specs. This change supersedes, in `procedural-backrooms-levels`: `level-generation` "Varied, connected space", `crop-uproot` "Seed is not refunded" and the "Uproot limits" wording on refunds, `level-sequence` difficulty sizes, and the respawn-at-spawn behaviour. Reconcile when archiving: apply this change's wording.

## Impact

- `src/LevelGen.lua` (from `procedural-backrooms-levels`): cell-grid maze carving, path winding, module placement on edges, branch plots, landmarks, region and checkpoint tracking.
- `src/Room.lua`, `src/rooms.lua`: more plots per level, checkpoints, per-region data (elevation, checkpoint position).
- `src/states/game/BackroomsState.lua`: uproot refund, respawn at checkpoint, longer-level flow.
- `src/constants.lua`: grid sizes, path-length minimums, branch counts, cell size.
- `tests/`: property tests over many seeds (turn count, loops, dead ends, solvability, length), `tests/reach.lua` sweep with branch plots, and a layout dump for review.
