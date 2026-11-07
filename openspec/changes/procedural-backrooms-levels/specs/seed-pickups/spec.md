# Spec Delta

## Purpose

Defines the seeds scattered through generated levels: which are required, which are optional, where they may sit, and how collecting them works.

## ADDED Requirements

### Requirement: Critical seeds guarantee solvability
The system SHALL place, for every obstacle in the chain, a critical seed of the needed type in the area reachable before that obstacle, so that a player who collects only critical seeds can solve the level.

#### Scenario: Prefix sufficiency
- **WHEN** the critical seeds in the areas reachable before each obstacle are totalled per type
- **THEN** they cover every seed of that type needed by that obstacle and all earlier ones

#### Scenario: Never behind its own obstacle
- **WHEN** a critical seed is placed
- **THEN** it is not located in an area that can only be reached by passing the obstacle it is meant to solve

### Requirement: Extra seeds are optional
The system SHALL scatter additional seeds of random types in dead ends, nooks and side rooms, and no extra seed SHALL be required to solve the level.

#### Scenario: Skipping extras
- **WHEN** a player collects only the critical seeds
- **THEN** the level is still solvable

#### Scenario: Extras cover a mistake
- **WHEN** a player wastes one seed and has collected a matching extra
- **THEN** the level is still solvable after uprooting the wasted crop

### Requirement: Collection by walking over
The system SHALL add a pickup's seed to the player's stock when they walk within a short radius of it and remove the pickup.

#### Scenario: Collect a seed
- **WHEN** the player walks onto a seed pickup
- **THEN** the seed count for its type increases by one and the pickup disappears

### Requirement: Collection feedback
The system SHALL show feedback when a seed is collected, naming the seed type and the new count.

#### Scenario: Message on pickup
- **WHEN** a seed is collected
- **THEN** a message naming the seed type is shown and the seed counter updates

### Requirement: Seed types shown are the types in use
The system SHALL list in the HUD and seed selection only the seed types the current level uses.

#### Scenario: Level with two seed types
- **WHEN** a level's chain uses only pumpkin and vine
- **THEN** only pumpkin and vine appear as selectable seeds
