# Spec Delta

## Purpose

Gives the player first-person movement and mouse-look in the 3D backrooms.

## ADDED Requirements

### Requirement: Move with the keyboard
The system SHALL move the player through the 3D world in response to movement keys.

#### Scenario: Walk
- **WHEN** the player holds a movement key
- **THEN** the camera moves in the matching direction

### Requirement: Look with the mouse
The system SHALL turn the camera in response to mouse movement while the mouse is captured.

#### Scenario: Look around
- **WHEN** the player moves the mouse
- **THEN** the camera turns accordingly
