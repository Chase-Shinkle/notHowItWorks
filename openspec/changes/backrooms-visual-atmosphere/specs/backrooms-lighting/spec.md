# Spec Delta

## Purpose

Defines how backrooms spaces are lit: light fixtures, falloff, flicker, varied lighting conditions per room, and soft shadows that ground objects.

## ADDED Requirements

### Requirement: Fixture-based lighting
The system SHALL light backrooms geometry from light fixtures placed in each room, with brightness falling off with distance, instead of flat uniform shading.

#### Scenario: Brighter near a fixture
- **WHEN** the player stands next to a fixture and then far from it in the same room
- **THEN** nearby surfaces are visibly brighter than distant ones

### Requirement: Flickering and failing lights
The system SHALL support fixtures that are steady, flickering, buzzing or dead, with flicker driven by time, and SHALL vary the mix between rooms.

#### Scenario: Flicker changes brightness
- **WHEN** a flickering fixture is observed over several seconds
- **THEN** its light intensity varies over time

#### Scenario: Dead fixture
- **WHEN** a fixture is dead
- **THEN** it contributes no light

### Requirement: Varied lighting conditions
The system SHALL give each room a lighting condition (for example bright, dim, single bulb or near-dark) so consecutive rooms do not look alike.

#### Scenario: Rooms differ
- **WHEN** a generated level with several rooms is toured
- **THEN** at least two distinct lighting conditions appear

### Requirement: Readable at the darkest setting
The system SHALL keep walls, plots, pickups, crops and the exit distinguishable in the darkest lighting condition.

#### Scenario: Near-dark room
- **WHEN** the player is in a near-dark room
- **THEN** the exit marker, plots and seed pickups remain visible and the player can navigate

### Requirement: Contact shadows
The system SHALL draw soft shadows under props, crops, pickups and billboards so they sit on the floor.

#### Scenario: Prop shadow
- **WHEN** a floor-standing prop is in view
- **THEN** a soft shadow is visible beneath it
