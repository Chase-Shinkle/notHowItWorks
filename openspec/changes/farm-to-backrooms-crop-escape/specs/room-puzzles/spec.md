# Spec Delta

## Purpose

Defines how rooms are solved: a limited seed allotment, and in later rooms a required combination of seed types.

## ADDED Requirements

### Requirement: Limited seed allotment per room
The system SHALL give the player a limited seed allotment on entering each room, enough to solve it with a small number of spares.

#### Scenario: Room starts with an allotment
- **WHEN** the player enters a room
- **THEN** their seeds equal that room's allotment

### Requirement: Later rooms need combinations
The system SHALL make the exit of the second and third rooms reachable only by combining at least two seed types.

#### Scenario: One seed type is not enough
- **WHEN** the player plants only one seed type in a later room
- **THEN** the exit remains unreachable

#### Scenario: Correct combination works
- **WHEN** the player plants the required seed types on the right plots
- **THEN** the exit becomes reachable
