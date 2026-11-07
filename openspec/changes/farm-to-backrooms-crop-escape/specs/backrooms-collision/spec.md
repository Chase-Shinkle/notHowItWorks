# Spec Delta

## Purpose

Makes the backrooms solid: the player is blocked by walls, supported by floors and grown crops, and pulled down by gravity.

## ADDED Requirements

### Requirement: Walls block the player
The system SHALL stop the player from passing through walls.

#### Scenario: Blocked by wall
- **WHEN** the player walks into a wall
- **THEN** the player stops at the wall and can slide along it

### Requirement: Floors and grown crops support the player
The system SHALL support the player on floors and on the walkable surfaces of grown crop structures.

#### Scenario: Stand on a grown crop
- **WHEN** the player moves onto the top of a grown crop structure
- **THEN** the player stands on it and does not fall through

### Requirement: Gravity
The system SHALL make the player fall when nothing supports them.

#### Scenario: Step off an edge
- **WHEN** the player walks off the edge of a raised surface
- **THEN** the player falls until they land on a supporting surface
