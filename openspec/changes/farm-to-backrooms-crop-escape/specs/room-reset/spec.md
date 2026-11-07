# Spec Delta

## Purpose

Lets the player recover from wasted seeds by resetting the current room.

## ADDED Requirements

### Requirement: Reset the current room
The system SHALL let the player reset the current room, removing all crops and restoring its initial plots and seed allotment.

#### Scenario: Reset after wasting seeds
- **WHEN** the player triggers a room reset
- **THEN** all crops in the room are removed and the room's original seed allotment is restored

#### Scenario: Reset the tutorial room
- **WHEN** the player resets the first room
- **THEN** the half-grown demo crop returns to its starting state
