# Spec Delta

## Purpose

Defines how large generated levels are and how long the path to the exit is, so levels take minutes to explore and solve.

## ADDED Requirements

### Requirement: Minimum grid and path length
The system SHALL generate levels on a grid of at least 6 by 6 cells for the first generated level and larger for later ones, with a critical path of at least 14 cells.

#### Scenario: First generated level size
- **WHEN** the first generated level is built
- **THEN** its grid is at least 6 by 6 cells and its critical path is at least 14 cells

### Requirement: Length scales with the level index
The system SHALL give each later generated level a grid and critical path no smaller than the previous one's, and the last longer than the first.

#### Scenario: Levels grow
- **WHEN** generated levels are compared in order
- **THEN** grid area and critical-path length never decrease and the last exceeds the first

### Requirement: Level size cap
The system SHALL cap generated level size so that a level fits its mesh, light and pickup budgets.

#### Scenario: Cap respected
- **WHEN** the largest level is built
- **THEN** its box count and light count are within the configured budgets

### Requirement: Expected duration
The system SHALL target a play time of several minutes per generated level for a player who explores some branches.

#### Scenario: Path walking time
- **WHEN** the critical path length is divided by walking speed
- **THEN** the pure walking time is at least 30 seconds
