# Spec Delta

## Purpose

Defines levels with many plots, including optional and decoy obstacles whose crops lead to rewards or dead ends, so growing something is a decision.

## ADDED Requirements

### Requirement: Several plots per level
The system SHALL give each generated level more plots than the critical path needs, spread across the maze.

#### Scenario: More plots than needed
- **WHEN** a generated level is built
- **THEN** it has at least two more plots than critical-path obstacles

### Requirement: Optional obstacles
The system SHALL place optional obstacle modules off the critical path that open alcoves, shortcuts or dead ends when solved.

#### Scenario: Optional alcove
- **WHEN** the player solves an optional obstacle
- **THEN** a previously unreachable area becomes reachable

### Requirement: Dead-end crops
The system SHALL include optional obstacles whose solved area is a dead end, some holding an extra seed and some empty.

#### Scenario: Grow into a dead end
- **WHEN** the player grows a crop on a decoy plot and crosses it
- **THEN** they reach a dead end with no route to the exit

### Requirement: Optional obstacles never gate the exit
The system SHALL NOT make any optional obstacle or its area necessary to reach the exit or to collect a critical seed.

#### Scenario: Skip every optional plot
- **WHEN** the player solves only the critical-path obstacles
- **THEN** the exit is reachable and every critical seed has been collectable

### Requirement: Shortcuts
The system SHALL include at least one shortcut in later levels: an optional obstacle whose crop shortens a route between two regions already reachable.

#### Scenario: Shortcut opens
- **WHEN** a shortcut obstacle is solved
- **THEN** the walking distance between its two regions decreases
