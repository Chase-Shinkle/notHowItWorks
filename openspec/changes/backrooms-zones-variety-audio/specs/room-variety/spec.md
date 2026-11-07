# Spec Delta

## Purpose

Defines the range of room shapes in generated levels, beyond hallways and 2x2 rooms, so spaces feel varied while staying solvable.

## ADDED Requirements

### Requirement: More room shapes
The system SHALL generate, in addition to hallways and 2x2 rooms, wide rectangular rooms, L-shaped rooms, pillared halls, crossroads atriums with a higher ceiling, long galleries, and small closets or alcoves.

#### Scenario: Shape variety
- **WHEN** a larger generated level is built
- **THEN** it contains at least three distinct room shapes

### Requirement: Existing shapes kept
The system SHALL keep hallways and 2x2 rooms in generated levels.

#### Scenario: Familiar shapes present
- **WHEN** a generated level is built
- **THEN** hallways and at least one 2x2 room are present when the grid has space for one

### Requirement: Variety does not break solvability
The system SHALL keep every level solvable and its obstacles, plots and pickups reachable and unobstructed when new shapes are used.

#### Scenario: Sweep with shapes
- **WHEN** many seeds are generated and checked
- **THEN** the exit is unreachable without the intended crops and reachable with them

### Requirement: Rooms never contain obstacles or the spawn and exit cells
The system SHALL NOT turn obstacle-module cells, the start cell or the exit cell into multi-cell shapes.

#### Scenario: Module cells stay straight
- **WHEN** a level is built with room shapes
- **THEN** each obstacle module sits in a straight passage as before

### Requirement: Pillars never trap or block
The system SHALL leave at least player-width clearance between pillars and walls, and SHALL NOT place pillars on plots, pickups, doorways or the exit.

#### Scenario: Pillared hall
- **WHEN** a pillared hall is built
- **THEN** the player can walk through it and reach every doorway

### Requirement: Shape choice is reproducible
The system SHALL choose room shapes deterministically from the level seed.

#### Scenario: Same seed
- **WHEN** a level is generated twice from the same seed
- **THEN** the same shapes appear in the same places
