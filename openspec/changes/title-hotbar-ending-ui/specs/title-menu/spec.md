# Spec Delta

## Purpose

Defines the game's title screen: a farm-themed first screen named "Back to Farming" with Play Game and Exit Game buttons, usable by mouse and keyboard.

## ADDED Requirements

### Requirement: Title and farm backdrop
The title screen SHALL show the game title "Back to Farming" over an animated farm scene built from the game's farm art, and the window title SHALL read "Back to Farming".

#### Scenario: Title shown on launch
- **WHEN** the game starts
- **THEN** the title screen shows "Back to Farming" over a farm scene (ground, crops, fence, barn) and the window title is "Back to Farming"

#### Scenario: Scene is alive
- **WHEN** the title screen has been open for several seconds
- **THEN** the scene shows motion (for example swaying crops or drifting clouds) without any player input

### Requirement: Play Game and Exit Game buttons
The title screen SHALL offer a "Play Game" button and an "Exit Game" button. Play Game SHALL start a new game on the farm with fresh game data; Exit Game SHALL close the game.

#### Scenario: Play starts the farm
- **WHEN** the player activates "Play Game"
- **THEN** the farm state starts with new game data

#### Scenario: Exit closes the game
- **WHEN** the player activates "Exit Game"
- **THEN** the game quits

### Requirement: Mouse and keyboard menu input
Buttons SHALL be activatable with the mouse (hover highlights, left click activates) and with the keyboard (Up/Down or W/S move the highlight, Enter or Space activates). Exactly one button is highlighted at any time, and Play Game is highlighted when the screen opens.

#### Scenario: Keyboard play
- **WHEN** the title screen opens and the player presses Enter
- **THEN** the game starts, as it does for Play Game

#### Scenario: Keyboard navigation
- **WHEN** the player presses Down then Enter
- **THEN** Exit Game is activated

#### Scenario: Mouse hover and click
- **WHEN** the pointer moves over a button and the player left-clicks
- **THEN** that button is highlighted on hover and activated on click

#### Scenario: Click outside buttons
- **WHEN** the player clicks where no button is
- **THEN** nothing is activated

### Requirement: Layout at any window size
The title, scene and buttons SHALL stay fully visible, undistorted and clickable at the supported window sizes, including after the window is resized.

#### Scenario: Resized window
- **WHEN** the window is resized or fullscreened
- **THEN** the buttons remain on screen and a click on a drawn button activates it
