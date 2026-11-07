# Spec Delta

## Purpose

Defines the ending screen shown after the last backrooms exit: a live 3D backrooms hallway with a slow camera drift, a text reveal and buttons to return to the title or exit.

## ADDED Requirements

### Requirement: Live 3D backrooms backdrop
The ending screen SHALL render a real-time 3D backrooms hallway using the same lighting, fog, flicker and grading as the backrooms, with the backrooms hum audible. The hallway SHALL be generated from the run's seed so it is the same for a given run.

#### Scenario: Ending shows backrooms
- **WHEN** the player reaches the last backrooms exit
- **THEN** the ending screen shows a lit 3D hallway in the backrooms style, not a flat background

#### Scenario: Reproducible hallway
- **WHEN** the ending is built twice from the same run seed
- **THEN** both hallways have identical layouts

### Requirement: Scripted camera
The camera SHALL move on its own, a slow drift along the hallway with gentle sway, and SHALL NOT respond to mouse look or movement keys. It SHALL stay inside the hallway and loop or hold at the end instead of passing through walls.

#### Scenario: Camera drifts unattended
- **WHEN** the ending is open for several seconds with no input
- **THEN** the view has moved along the hallway and remains inside it

#### Scenario: Input does not move camera
- **WHEN** the player moves the mouse or presses movement keys
- **THEN** the camera path is unaffected

### Requirement: Text reveal and buttons
The ending SHALL fade in the headline "You found a way out." and the subtitle "I don't think it's supposed to work like that." over the scene, then show two buttons, "Back to Title" and "Exit Game", operated by mouse and keyboard the same way as on the title screen. The mouse cursor SHALL be visible and free on this screen.

#### Scenario: Reveal order
- **WHEN** the ending opens
- **THEN** the scene is visible first and the headline, subtitle and buttons fade in afterwards

#### Scenario: Back to Title
- **WHEN** the player activates "Back to Title"
- **THEN** the title screen is shown

#### Scenario: Exit Game
- **WHEN** the player activates "Exit Game"
- **THEN** the game quits

#### Scenario: Held key does not skip
- **WHEN** a key held down from the final exit is still pressed as the ending opens
- **THEN** no button is activated until the buttons are shown and the player presses a fresh key or click

### Requirement: Clean hand-off
Entering the ending SHALL stop the backrooms gameplay audio and release the captured mouse, and leaving it SHALL stop the ending's audio so nothing from it plays on the title screen.

#### Scenario: No audio leak
- **WHEN** the player goes from the ending back to the title
- **THEN** the backrooms hum is no longer playing

#### Scenario: Replay is fresh
- **WHEN** the player starts a new game after the ending
- **THEN** the farm and the backrooms start from new game data and a new run seed

### Requirement: Rendering fallback
If the backrooms look pipeline (shader or post-process) is unavailable or fails, the ending SHALL still show the hallway plainly rendered with readable text and working buttons.

#### Scenario: Shader unavailable
- **WHEN** the game runs with the backrooms shader disabled
- **THEN** the ending still shows the hallway, text and buttons
