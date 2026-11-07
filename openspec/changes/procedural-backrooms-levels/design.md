# Design

## Context

Backrooms levels are plain data tables in `src/rooms.lua` (`boxes`, `plots`, `exit`, `allotment`, `billboards`, `demoCrops`) validated and built by `Room` (`src/Room.lua`). Obstacles are hand-measured against the crop sizes in `src/Crop.lua` (pit 1.0 m deep with pumpkin, 2.6 m ledge with beanstalk, 4 m gap with 6 m vine). Plots accept any seed, so a wrong crop permanently occupies its plot. `tests/reach.lua` and `tests/reachability.lua` search physical reachability over plot-to-crop assignments. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Generated levels in the existing room data format, so rendering, collision and crop code are untouched.
- Solvable by construction, with an independent check as a backstop.
- Reproducible from a seed for debugging and tests.

**Non-Goals:**
- Freely generated obstacle geometry, new crop types, endless mode, saving.
- HUD/objective redesign and lighting/prop passes (follow-up changes).

## Decisions

1. **Generate the solution first.** Pick the chain (ordered obstacle modules by difficulty), then lay out space around it. Alternative: random layout then verify/repair, rejected because obstacles must be exact modules and rejection rates would be high.
2. **Modules are straight corridors, 6 m wide, snapped to a coarse grid** (cell edge 6 m). Each module declares its entry/exit faces, plot positions and dirs (copied from today's measurements), its floor elevation change, and minimum ceiling. Filler rooms are 1-3 cells; halls are 1-cell-wide strips. Doorways are openings in cell-edge walls. The generator tracks current floor elevation: a ledge raises it and later cells sit at that height. Alternative: free-form BSP rooms, rejected because it cannot host the fixed-width modules cleanly.
3. **Regions.** Solving obstacle k opens region R_k. R_0 is the start area. Loops and branches belong to a region. This is the unit seed placement reasons about.
4. **Seed placement rule.** For each obstacle k, place its critical seed in a random walkable cell of R_0..R_{k-1}, preferring branch cells. Extras go to dead ends, nooks and branch cells in any region, never required. Secret nooks are branch cells whose doorway is partly covered by a prop billboard (visual concealment only; no collision change). Pickups are a new `pickups = {{pos, seed, tier}}` list on the room data.
5. **Own RNG.** A small seeded generator in `LevelGen.lua` (not `love.math`) so tests under the mocked LÖVE API are deterministic and independent of the engine. Level seed = hash(run seed, level index); retry uses a derived seed.
6. **Two-layer verification.** (a) Structural check at generation: the region graph, the prefix-sufficiency count of critical seeds, no overlapping cells, ceiling clearances. Failure regenerates from a derived seed. (b) Offline sweep: `tests/reach.lua` physical search over hundreds of seeds per difficulty, asserting the exit is unreachable with no crops and reachable with the intended crops.
7. **Uproot to make mistakes recoverable.** Plots keep accepting any seed (the puzzle stays "which crop goes where"), so a wrong planting would soft-lock without a way out. Uprooting frees the plot and refunds nothing; extras replace the lost seed. Refused on the demo crop and while the player stands on or inside the crop. Alternative: typed plots, rejected because it removes the puzzle.
8. **Seed stock.** Generated levels start with zero seeds and nothing carries over; the farm top-up applies only to the tutorial. Keeps scarcity local to the level and verification per-level. Reset restores the starting stock, respawns pickups and clears crops, and rebuilds from the same seed.
9. **HUD seed types.** Rooms get a `seedTypes` list (types the chain uses). `visibleSeedTypes` uses it when present, else the allotment as today, because generated levels start with zero seeds.
10. **Sequence.** Level 1 stays the authored tutorial. Levels 2..N are generated with obstacles counts rising (default 2, 3, 4 for N = 4) and type mix widening. Counts live in one constants table. Ending unchanged.
11. **Feedback.** Pickups render as bobbing seed-bag billboards; collecting plays the existing message line (`say`) and bumps the HUD count. Pickup radius is a constant; collection is automatic on contact.

## Risks / Trade-offs

- [Generated layouts feel samey] → Randomize cell footprints, loop/branch counts and chain order; add props and later the visual pass.
- [Physical solvability differs from graph solvability] → Offline physics sweep over many seeds; keep module dimensions unchanged.
- [Player strands a needed seed by planting wrongly] → Uproot plus extras; reset is the last fallback.
- [Uprooting a bridge while standing on it] → Refuse under the player; falling respawns at spawn anyway.
- [Ceiling collisions after ledges] → Module declares min ceiling; generator checks clearance.
- [Scope vs jam time] → Tutorial stays authored; generated level count is one constant, and a minimal pass (pit/gap only) can ship first.

## Migration Plan

Replace `rooms.lua` rooms 2-3 usage with the level sequence; keep their module data as module templates. Keep the old rooms reachable by a test-only override so existing tests still run. No data migration.

## Open Questions

- Exact default obstacle counts and level count (start with tutorial + 3 generated); tune after playtests.
- Whether secret-nook props need a distinct sprite.
