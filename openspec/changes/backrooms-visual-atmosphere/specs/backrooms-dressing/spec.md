# Spec Delta

## Purpose

Defines the furniture, props and abandoned objects that fill backrooms spaces and tell small stories, placed according to room type.

## ADDED Requirements

### Requirement: Props by room type
The system SHALL place props from a catalogue (furniture, boxes, farm tools, signs and similar) in rooms according to the room's type and theme.

#### Scenario: Different rooms, different props
- **WHEN** a hall and a filler room of the same level are compared
- **THEN** their prop selection differs

### Requirement: Environmental storytelling groupings
The system SHALL place small grouped arrangements of abandoned objects (for example a toppled chair with scattered papers or a lone farm tool by a wall) that hint at what happened.

#### Scenario: A grouping appears
- **WHEN** a generated level beyond the tutorial is toured
- **THEN** at least one storytelling grouping is present

### Requirement: Dressing never blocks play
The system SHALL NOT place props where they overlap a plot, pickup, exit, doorway, obstacle module or spawn, or hide a critical seed, and SHALL keep walkable routes clear.

#### Scenario: Clear plot
- **WHEN** props are placed in a room with a plot
- **THEN** none overlaps the plot or its planting area

#### Scenario: Concealing props are for nooks only
- **WHEN** a prop partly conceals a doorway
- **THEN** the doorway belongs to an optional secret nook and remains walkable

### Requirement: Deterministic placement
The system SHALL place dressing deterministically from the level seed.

#### Scenario: Same seed, same props
- **WHEN** a level is generated twice from the same seed
- **THEN** prop type, position and orientation match

### Requirement: Props are non-solid unless declared
The system SHALL treat props as non-colliding billboards by default, and any prop declared solid SHALL be accounted for in reachability checks.

#### Scenario: Billboard prop
- **WHEN** the player walks through a default prop
- **THEN** they are not blocked
