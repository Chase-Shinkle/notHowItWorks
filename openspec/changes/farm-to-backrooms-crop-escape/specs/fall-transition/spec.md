# Spec Delta

## Purpose

Defines the short glitch-and-fall presentation that moves the player from the 2D farm into the 3D backrooms.

## ADDED Requirements

### Requirement: Glitch sequence plays without input
The system SHALL play a short, non-interactive glitch presentation (such as screen shake, visual corruption, and a falling player) when the break starts, and SHALL ignore player input while it plays.

#### Scenario: Input locked during glitch
- **WHEN** the break sequence is playing
- **THEN** player input has no effect on the farm

### Requirement: Sequence ends in the backrooms
The system SHALL switch to the 3D backrooms when the glitch sequence finishes, and SHALL play it only once per game.

#### Scenario: Fall completes
- **WHEN** the glitch presentation ends
- **THEN** the backrooms' first room is shown in first person
