# Spec Delta

## Purpose

Defines the backrooms in-game HUD: a Minecraft-style hotbar showing the seeds the player holds, and light overlays for room name, prompts and controls that keep the view clear.

## ADDED Requirements

### Requirement: Seed hotbar
In the backrooms the HUD SHALL show a hotbar centred at the bottom of the screen with one slot per seed type, each slot showing that seed's icon, its key number and the number of seeds held.

#### Scenario: All slots shown
- **WHEN** the player is in any backrooms room
- **THEN** the hotbar shows a slot for every seed type, including types the room does not use or the player holds none of

#### Scenario: Count matches holdings
- **WHEN** the player plants a seed or collects a seed pickup
- **THEN** the count on that seed's slot changes immediately to the new number held

#### Scenario: Empty slot
- **WHEN** the player holds zero of a seed type
- **THEN** its slot is shown dimmed with a count of 0 and is not hidden

### Requirement: Selected slot highlight
The hotbar SHALL visibly mark exactly one slot as selected, the seed type that planting would use.

#### Scenario: Selection follows input
- **WHEN** the player selects a different seed with 1-3, Q/Tab or the mouse wheel
- **THEN** the selection highlight moves to that slot and planting uses that seed type

### Requirement: Mouse-wheel selection
The player SHALL be able to cycle the selected seed with the mouse wheel while the mouse is captured, in addition to the existing number and Q/Tab keys. Scrolling past the last slot wraps to the first, and the reverse.

#### Scenario: Scroll cycles
- **WHEN** the player scrolls one notch in one direction, repeatedly
- **THEN** the selection advances one slot per notch and wraps around

#### Scenario: Wheel when mouse is free
- **WHEN** the mouse is not captured
- **THEN** wheel input does not change the selection

### Requirement: Clear-view overlays
The backrooms HUD SHALL NOT draw full-width opaque or dark bands over the 3D view. The room name and level counter, the plant prompt, messages and the controls hint SHALL remain readable over bright and dark surfaces, and the controls hint SHALL fade away after the player has had time to read it.

#### Scenario: No full-width bands
- **WHEN** the backrooms HUD is drawn
- **THEN** only the hotbar and compact text plates cover the 3D view

#### Scenario: Hint fades
- **WHEN** a room has been active for several seconds with the mouse captured
- **THEN** the controls hint is no longer shown, and it returns when the mouse is released

#### Scenario: Plant prompt unchanged
- **WHEN** the player aims at a plot
- **THEN** the same prompt as before (plant, wrong seed, no seeds, plot in use) is shown near the crosshair

### Requirement: Hotbar scales with window
The hotbar SHALL scale with the window height and stay fully on screen at the supported window sizes.

#### Scenario: Small and large windows
- **WHEN** the window is resized between its minimum and fullscreen sizes
- **THEN** the hotbar remains fully visible, centred, with legible counts
