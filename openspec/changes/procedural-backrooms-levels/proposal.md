# Proposal

## Why

The backrooms are three hand-built rooms with fixed seed allotments, so the game is short and has no replay value. We want levels that are pseudo-randomly generated but always solvable, with seeds found by exploring instead of handed out. Seeds stay tools: planting crops to cross obstacles remains the core verb.

## What Changes

- Add a seeded level generator that builds a solution first (a random chain of obstacles), then grows rooms, halls, loops, dead ends and secret nooks around it. Output uses the existing room data format, so `Room`, collision and crop code are reused.
- Obstacle modules (pit, ledge, gap) stay hand-measured; the generator composes them and never invents obstacle geometry.
- Add collectible seed pickups in two tiers: **critical** seeds (exactly what the chain needs, always reachable before the obstacle that uses them) and **extra** seeds (optional, hidden in dead ends and nooks, a buffer for mistakes). Collecting shows UI feedback.
- Add uprooting: a planted crop can be removed (its seed is lost) so a mistaken planting is recoverable with extras.
- Replace the fixed 3-room sequence with a tutorial level followed by generated levels whose difficulty (obstacle count and mix) rises, then the ending. Each level has a reproducible seed; room reset rebuilds the same layout.
- **BREAKING**: generated levels start with no seeds and do not carry leftover seeds between levels (the farm top-up applies to the tutorial only). Rooms 2 and 3 of `rooms.lua` are replaced by generated levels.
- Out of scope: HUD/objective redesign, lighting/fog/prop/texture passes (separate follow-up changes), endless mode, saving, new crop types.

## Capabilities

### New Capabilities
- `level-generation`: deterministic, seeded, always-solvable level layouts composed of obstacle modules, filler rooms, loops, dead ends and secret nooks.
- `seed-pickups`: critical and extra seeds placed in a level, collected by walking onto them, with feedback.
- `level-sequence`: tutorial level, generated levels with rising difficulty, reproducible level seeds, per-level seed stock, reset behaviour, and the ending.
- `crop-uproot`: removing a planted crop to free its plot.

### Modified Capabilities

None. The project has no archived specs; `room-progression`, `room-puzzles`, `room-reset` and `seed-carryover` exist only in the unarchived `farm-to-backrooms-crop-escape` change. This change supersedes their hand-built-room and fixed-allotment wording for levels after the tutorial; reconcile at archive time.

## Impact

- New `src/LevelGen.lua` (generator, RNG, modules, solvability check); `src/rooms.lua` keeps the authored tutorial and obstacle-module constants.
- `src/Room.lua`: validate and build `pickups` and a `seedTypes` list; plot clearing for uproot.
- `src/Crop.lua`: removal support.
- `src/GameData.lua`: seed-stock policy for generated levels.
- `src/states/game/BackroomsState.lua`: build levels from the sequence, pickup collection, uproot input, HUD seed-type visibility, same-layout reset.
- `src/constants.lua`: level count, difficulty table, pickup and uproot constants, uproot key.
- `tests/`: generator property tests over many seeds and a reachability sweep using `tests/reach.lua`.
