# Spec Delta

## Purpose

Defines the shape of generated levels: a branching maze with turns, junctions, loops and dead ends that players can get lost in, with a winding path to the exit.

## ADDED Requirements

### Requirement: Branching two-dimensional layout
The system SHALL generate generated levels as a two-dimensional network of rooms and halls with turns and junctions, not a single straight run.

#### Scenario: Not a straight line
- **WHEN** a generated level is built
- **THEN** its critical path from spawn to exit contains at least three turns and its bounding area extends in both horizontal axes

#### Scenario: Junctions exist
- **WHEN** a generated level is built
- **THEN** it contains junctions where three or more passages meet

### Requirement: Loops and multiple routes
The system SHALL include loops so that some areas can be reached by more than one route.

#### Scenario: A loop exists
- **WHEN** a generated level is built
- **THEN** at least one cycle of passages exists that does not pass through an unsolved obstacle

### Requirement: Dead ends and side areas
The system SHALL include dead ends and side areas off the critical path, including at least some reached only by growing a crop.

#### Scenario: Optional areas
- **WHEN** a generated level is built
- **THEN** it contains dead ends off the critical path

### Requirement: Solvable by construction
The system SHALL keep the exit unreachable without solving the critical path's obstacles and reachable once they are solved, in every generated level.

#### Scenario: Exit locked, then open
- **WHEN** a level is searched with no crops and then with the chain's intended crops
- **THEN** the exit is unreachable in the first search and reachable in the second

### Requirement: Recognizable landmarks
The system SHALL give junction rooms and large rooms distinguishing landmark data (a landmark id and a distinct lighting or theme hint) so players can tell places apart.

#### Scenario: Distinct junctions
- **WHEN** the junction rooms of a level are compared
- **THEN** no two adjacent junction rooms share the same landmark id

### Requirement: Obstacle placement on straight passages
The system SHALL place obstacle modules only on straight passages entered and left on opposite faces, and SHALL keep each floor elevation region self-consistent, so changing elevation happens only through a ledge module.

#### Scenario: No turning inside a module
- **WHEN** an obstacle module is placed
- **THEN** the passage leaves it on the face opposite to the entry face

### Requirement: Reproducible layout
The system SHALL produce the same layout from the same level seed and difficulty.

#### Scenario: Same seed
- **WHEN** a level is generated twice from the same seed
- **THEN** the layouts are identical
