# Spec Delta

## Purpose

Keeps pixel art and text crisp by loading sprites, farm tiles and fonts with nearest-neighbour filtering, while allowing large 3D surface textures to stay smooth.

## ADDED Requirements

### Requirement: Pixel art and fonts use nearest filtering
The system SHALL load every sprite, farm tile, billboard texture and font with nearest-neighbour filtering, regardless of when in startup the asset is loaded.

#### Scenario: Sprite filters
- **WHEN** the game has finished starting
- **THEN** the hero, crop, plot, well and bucket images report nearest filtering

#### Scenario: Font filters
- **WHEN** the game has finished starting
- **THEN** the default and small fonts report nearest filtering

#### Scenario: Placeholder assets
- **WHEN** the game is launched with placeholder assets forced
- **THEN** placeholder images also use nearest filtering

### Requirement: Backrooms surface textures may stay smooth
The system SHALL NOT require nearest filtering for the large tiling backrooms wall, floor and ceiling textures.

#### Scenario: Surface textures
- **WHEN** the backrooms is rendered
- **THEN** the wall, floor and ceiling textures may use linear filtering without failing this capability
