# Spec Delta

## Purpose

Defines the three hand-built backrooms rooms, their exits, the move from room to room, and the ending.

## ADDED Requirements

### Requirement: Three rooms with locked exits
The system SHALL provide three hand-built rooms in a backrooms visual style, each with an exit the player cannot reach at the start.

#### Scenario: Exit is out of reach at start
- **WHEN** the player enters any room
- **THEN** the exit cannot be reached without growing crop structures

### Requirement: Advance through exits
The system SHALL load the next room when the player reaches the current room's exit.

#### Scenario: Reach a non-final exit
- **WHEN** the player reaches the exit of a room that is not the last
- **THEN** the next room loads with its own seed allotment

### Requirement: Ending
The system SHALL show an ending when the player reaches the final room's exit.

#### Scenario: Finish the game
- **WHEN** the player reaches the final room's exit
- **THEN** the ending is shown
