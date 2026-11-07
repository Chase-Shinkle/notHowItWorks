# Spec Delta

## Purpose

Makes planting on the Room 2 and Room 3 pit plots forgiving, so players can plant from solid floor well before the rim and are not punished by falling.

## ADDED Requirements

### Requirement: Pit plots are plantable from a comfortable distance
The system SHALL allow planting on a pit plot from any standing position on the floor within at least 2.5 m horizontally of the plot, including positions where the player's feet are 1.0 m or more back from the rim.

#### Scenario: Approach from spawn
- **WHEN** the player walks from the Room 2 spawn toward the pit and stops anywhere within 2.5 m of the pit plot, still on the floor
- **THEN** the plant prompt is shown and planting a pumpkin succeeds

#### Scenario: Room 3 pit
- **WHEN** the player stands on the Room 3 start floor within 2.5 m of the pit plot
- **THEN** the plant prompt is shown and planting a pumpkin succeeds

### Requirement: Larger reach does not open new shortcuts
The system SHALL keep every room solvable only by the intended seed combinations: a larger pit reach MUST NOT let a plot be used to bypass a puzzle or reach a different plot's position.

#### Scenario: Nearest plot wins
- **WHEN** two plots are both within reach
- **THEN** the nearer plot is the one planted

#### Scenario: Reachability
- **WHEN** the room reachability checks run with the new reach
- **THEN** every room is still solvable with its allotment and not solvable without the required seed types
