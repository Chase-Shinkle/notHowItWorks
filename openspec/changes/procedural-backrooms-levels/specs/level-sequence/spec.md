# Spec Delta

## Purpose

Defines the order of backrooms levels, how difficulty rises, how seeds are stocked per level, how reset behaves, and how the game ends.

## ADDED Requirements

### Requirement: Tutorial first, then generated levels
The system SHALL play an authored tutorial level first, followed by generated levels in rising difficulty, then the ending.

#### Scenario: Tutorial is stable
- **WHEN** the backrooms start
- **THEN** the first level is the authored tutorial with its half-grown demo crop

#### Scenario: Generated levels follow
- **WHEN** the player reaches the tutorial exit
- **THEN** the next level is generated, and the ending shows after the last level's exit

### Requirement: Rising difficulty
The system SHALL increase the number of chain obstacles and the variety of obstacle types with each generated level.

#### Scenario: Later levels are harder
- **WHEN** generated levels are compared in order
- **THEN** each has at least as many chain obstacles as the one before and the last has more than the first

### Requirement: Reproducible level seeds
The system SHALL derive each level's seed from a run seed, log the run seed, and allow it to be overridden for debugging.

#### Scenario: Override the run seed
- **WHEN** a run seed is supplied
- **THEN** every generated level of that run is identical to every earlier run with that seed

### Requirement: Seed stock per level
The system SHALL start each generated level with no seeds and SHALL NOT carry leftover seeds from the previous level; the tutorial keeps the existing farm carry-over and top-up.

#### Scenario: Fresh stock
- **WHEN** a generated level begins
- **THEN** the player holds zero seeds of every type

### Requirement: Reset rebuilds the same level
The system SHALL, on reset, rebuild the current level from its seed, restore its starting seeds, respawn all collected pickups and remove all planted crops.

#### Scenario: Reset after collecting
- **WHEN** the player resets a generated level after collecting seeds and planting crops
- **THEN** the layout is unchanged, pickups are back, crops are gone and the seed stock is the level's starting stock
