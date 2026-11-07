# Spec Delta

## Purpose

Defines how backrooms levels are generated: reproducible from a seed, composed of known obstacle modules, and solvable by construction.

## ADDED Requirements

### Requirement: Deterministic generation
The system SHALL generate a level purely from a level seed and a difficulty, so the same inputs always produce the same layout, plots, exit and pickups.

#### Scenario: Same seed, same level
- **WHEN** a level is generated twice with the same seed and difficulty
- **THEN** both levels have identical geometry, plots, exit and pickups

#### Scenario: Different seeds differ
- **WHEN** levels are generated from different seeds at the same difficulty
- **THEN** their layouts differ in more than dressing for most seed pairs

### Requirement: Obstacles form a solution chain
The system SHALL build each level around an ordered chain of obstacles between the start and the exit, each solved by a specific crop on a specific plot, and the exit SHALL be unreachable without solving every obstacle in the chain.

#### Scenario: Exit locked without crops
- **WHEN** a generated level is searched with no crops planted
- **THEN** the exit is not reachable from the spawn

#### Scenario: Chain solves the level
- **WHEN** the intended crop is grown on each chain plot
- **THEN** the exit is reachable from the spawn

### Requirement: Obstacle modules are hand-measured
The system SHALL use only the pit, ledge and gap obstacle modules, with the dimensions the crops are sized for, and SHALL NOT generate obstacle dimensions freely.

#### Scenario: Pit module
- **WHEN** a level contains a pit obstacle
- **THEN** a grown pumpkin on its plot fills the pit level with the surrounding floor

### Requirement: Varied, connected space
The system SHALL surround the chain with filler rooms of varying size, connecting halls, and at least some loops or side branches, all connected to the chain, with no overlapping rooms.

#### Scenario: Everything connected
- **WHEN** a level is generated
- **THEN** every walkable region is reachable from the spawn once the chain obstacles preceding it are solved

#### Scenario: Branches exist
- **WHEN** a level at difficulty above the tutorial is generated
- **THEN** it contains at least one dead end or secret nook off the chain

### Requirement: Secret nooks
The system SHALL include side areas whose entrance is partly concealed by a prop but remains walkable.

#### Scenario: Concealed entrance is walkable
- **WHEN** a secret nook is generated
- **THEN** the player can walk into it without growing any crop that is not on the chain before it

### Requirement: Generation self-check
The system SHALL verify a generated level for solvability and seed sufficiency before use, and SHALL regenerate from a derived seed if the check fails.

#### Scenario: Failed check regenerates
- **WHEN** a generated candidate fails the self-check
- **THEN** a different candidate from a derived seed is checked and used instead
