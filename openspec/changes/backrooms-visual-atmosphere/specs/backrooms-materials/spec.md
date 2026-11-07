# Spec Delta

## Purpose

Defines the surface variety of backrooms spaces: a catalogue of wall, floor and ceiling textures and per-room material themes.

## ADDED Requirements

### Requirement: Texture variety
The system SHALL provide multiple wall, floor and ceiling textures and use them across the rooms of a level.

#### Scenario: Different walls in one level
- **WHEN** a generated level with several rooms is toured
- **THEN** at least two different wall textures and two different floor textures appear

### Requirement: Per-room material themes
The system SHALL assign each room a material theme (a consistent set of wall, floor and ceiling textures and tint), chosen reproducibly from the level seed.

#### Scenario: Reproducible theme
- **WHEN** a level is regenerated from the same seed
- **THEN** every room has the same theme as before

### Requirement: Obstacle readability
The system SHALL keep obstacle modules (pits, ledges, gaps), plots and exits visually distinct from room surfaces in every theme.

#### Scenario: Pit edge visible
- **WHEN** a pit is viewed in any theme
- **THEN** its edge and floor level are distinguishable from the surrounding floor

### Requirement: Missing textures degrade gracefully
The system SHALL fall back to a flat colour for a missing texture and keep playing.

#### Scenario: Texture file absent
- **WHEN** a theme's texture file is missing
- **THEN** the surface renders in the theme's fallback colour
