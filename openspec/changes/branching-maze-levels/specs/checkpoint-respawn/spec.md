# Spec Delta

## Purpose

Defines where the player reappears after falling out of the world, so long levels do not send them back to the start.

## ADDED Requirements

### Requirement: Region checkpoints
The system SHALL record a safe checkpoint at the entrance of each region of a generated level and update the player's current checkpoint when they enter a new region.

#### Scenario: Entering a new region
- **WHEN** the player enters a region they have not been in
- **THEN** that region's checkpoint becomes their current checkpoint

### Requirement: Respawn at the checkpoint
The system SHALL respawn a player who falls below the level's kill height at their current checkpoint, keeping crops, pickups collected and seeds.

#### Scenario: Fall into a pit
- **WHEN** the player falls into a void after reaching a later region
- **THEN** they reappear at that region's checkpoint, not the level spawn, with crops and seeds intact

### Requirement: Checkpoints are safe
The system SHALL place checkpoints on solid floor that does not depend on a crop.

#### Scenario: No crop-dependent checkpoint
- **WHEN** a checkpoint is placed
- **THEN** it lies on level floor and not on a grown crop

### Requirement: Reset returns to the spawn
The system SHALL return the player to the level spawn, with the current checkpoint reset, when the level is reset.

#### Scenario: Reset
- **WHEN** the player resets the level
- **THEN** they appear at the spawn and the current checkpoint is the spawn region's
