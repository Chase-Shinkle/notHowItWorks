# Spec Delta

## Purpose

Lets the player remove a planted crop so a mistaken planting does not permanently block a plot.

## ADDED Requirements

### Requirement: Uproot a planted crop
The system SHALL let the player remove a crop they planted from a plot in reach, freeing the plot; the seed spent on it is not returned.

#### Scenario: Free a wrongly used plot
- **WHEN** the player uproots a crop on a plot in reach
- **THEN** the crop disappears, its structure no longer collides, and the plot accepts a new seed

#### Scenario: Seed is not refunded
- **WHEN** a crop is uprooted
- **THEN** the player's seed count does not change

### Requirement: Uproot limits
The system SHALL refuse to uproot the tutorial demo crop and SHALL refuse while the player is standing on or inside the crop.

#### Scenario: Standing on a pumpkin
- **WHEN** the player is on top of a grown pumpkin and tries to uproot it
- **THEN** nothing is removed and a message says why

#### Scenario: Demo crop
- **WHEN** the player tries to uproot the tutorial demo crop
- **THEN** nothing is removed
