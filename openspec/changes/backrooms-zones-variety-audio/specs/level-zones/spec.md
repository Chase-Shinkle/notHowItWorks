# Spec Delta

## Purpose

Defines zones: contiguous volumes of a level where wallpaper, carpet, ceiling, lighting and fog stay the same, while different zones differ, so areas feel like distinct places.

## ADDED Requirements

### Requirement: Consistent materials within a zone
The system SHALL give every surface in a zone (walls, floors and ceilings of its halls and rooms) the same material theme.

#### Scenario: Walking inside a zone
- **WHEN** the player walks between rooms and halls of one zone
- **THEN** the wallpaper, carpet and ceiling textures do not change

### Requirement: Zones differ across a level
The system SHALL assign different material themes and lighting to neighbouring zones, and a generated level SHALL contain at least three zones.

#### Scenario: Neighbouring zones
- **WHEN** two adjacent zones of a level are compared
- **THEN** their material themes differ and their lighting presets differ

#### Scenario: Zone count
- **WHEN** a generated level is built
- **THEN** it has at least three zones

### Requirement: Contiguous zones
The system SHALL make each zone a connected area of the maze, so a zone is not split into separate pieces by another zone.

#### Scenario: One piece
- **WHEN** the cells of any zone are examined
- **THEN** they form one connected set

### Requirement: Changes happen at thresholds
The system SHALL place zone changes at doorways, halls or other thresholds, never in the middle of a room.

#### Scenario: Rooms are whole
- **WHEN** a multi-cell room is built
- **THEN** all of its cells belong to one zone

### Requirement: Zone lighting
The system SHALL light each zone with its own lighting condition (ambient, fixture colour, flicker mix and fog), consistent throughout the zone and different between neighbouring zones, sometimes bright and sometimes dim or nearly dark.

#### Scenario: Lighting differs across a level
- **WHEN** a level is toured
- **THEN** at least two lighting presets appear and the preset is constant within each zone

### Requirement: Smooth transition
The system SHALL blend ambient light and fog over a short distance as the camera crosses between zones, so the change is not a hard pop.

#### Scenario: Crossing a doorway
- **WHEN** the player walks across a zone boundary
- **THEN** ambient light and fog change gradually over a short distance, not in one frame

### Requirement: Gameplay readability is kept
The system SHALL keep obstacles, plots, pickups, crops and the exit visible in every zone's lighting.

#### Scenario: Dark zone
- **WHEN** the player is in the darkest zone
- **THEN** plots, pickups and the exit remain distinguishable

### Requirement: Reproducible zones
The system SHALL produce the same zones, themes and lighting from the same level seed, without changing the layout.

#### Scenario: Same seed
- **WHEN** a level is generated twice from the same seed
- **THEN** zones, themes and lighting match, and the layout is identical to one generated before this feature
