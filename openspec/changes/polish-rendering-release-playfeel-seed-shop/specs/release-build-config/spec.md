# Spec Delta

## Purpose

Ensures the shipped jam build contains no debug shortcuts or debug overlays, while keeping them available for development.

## ADDED Requirements

### Requirement: Packaged build has debug mode off
The packaged `.love` SHALL start with debug mode disabled by default, with no state-skip key and no debug text on screen.

#### Scenario: F1 does nothing
- **WHEN** the player presses F1 in any state of the packaged build
- **THEN** the game state does not change

#### Scenario: No debug text
- **WHEN** the farm or backrooms HUD is drawn in the packaged build
- **THEN** it shows no "debug skip" line, FPS counter or F1 marker

### Requirement: Debug mode is an explicit opt-in
The system SHALL allow debug mode to be enabled for development runs only by an explicit, documented action, and the packaging script SHALL NOT enable it.

#### Scenario: Development run
- **WHEN** a developer launches the game from source with the documented debug opt-in
- **THEN** F1 skips to the next state and the debug HUD text is shown

#### Scenario: Release notes match the build
- **WHEN** the package is built
- **THEN** `RELEASE.md` in the package describes how debug mode is enabled and does not claim it is on
