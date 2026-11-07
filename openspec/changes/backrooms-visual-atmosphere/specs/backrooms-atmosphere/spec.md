# Spec Delta

## Purpose

Defines the backrooms' atmosphere: fog, faked volumetric light, the post-process look, and the safe fallback when effects are unavailable.

## ADDED Requirements

### Requirement: Distance fog
The system SHALL fog distant backrooms geometry toward a per-room fog colour, with density that varies by room.

#### Scenario: Far walls fade
- **WHEN** a long hall is viewed from one end
- **THEN** the far end is visibly fogged compared with nearby walls

### Requirement: Volumetric light shafts
The system SHALL draw soft light shafts or glow under suitable fixtures to suggest volumetric light, without per-pixel ray marching.

#### Scenario: Shaft under a fixture
- **WHEN** a lit ceiling fixture is in view in a foggy room
- **THEN** a soft shaft or glow is visible beneath it

### Requirement: Post-process look
The system SHALL apply a lightweight post-process (colour grade, vignette and optional bloom) to the 3D scene only, and SHALL draw the HUD after it so text stays sharp.

#### Scenario: HUD unaffected
- **WHEN** the post-process is enabled
- **THEN** HUD text and icons are drawn without grade, bloom or blur

### Requirement: Safe fallback
The system SHALL fall back to the plain, unshaded backrooms render, with gameplay unchanged, when shaders fail to compile, canvases cannot be created, or `--no-shader` is passed, and SHALL log the reason once.

#### Scenario: Shader compile failure
- **WHEN** the backrooms shader fails to compile
- **THEN** the backrooms still render and play normally, and the reason is logged once

### Requirement: Quality setting
The system SHALL provide a quality setting that reduces or disables fog shafts, bloom and flicker without changing gameplay.

#### Scenario: Low quality
- **WHEN** quality is set to low
- **THEN** shafts and bloom are not drawn and collision, pickups and plots behave identically

### Requirement: Effects do not affect gameplay
The system SHALL NOT let lighting, fog or post-process change collision, reachability, pickups or plot behaviour.

#### Scenario: Same level, different quality
- **WHEN** the same level is played at two quality settings
- **THEN** its geometry, plots and pickups are identical
