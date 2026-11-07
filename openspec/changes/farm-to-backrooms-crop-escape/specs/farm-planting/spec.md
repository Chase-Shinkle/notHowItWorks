# Spec Delta

## Purpose

Lets the player plant seeds on farm plots and watch crops grow in the 2D farm, teaching the first half of the core loop.

## ADDED Requirements

### Requirement: Plant a seed on an empty plot
The system SHALL let the player plant a seed from their inventory onto an empty farm plot, consuming one seed.

#### Scenario: Plant on empty plot
- **WHEN** the player interacts with an empty plot while holding at least one seed
- **THEN** the plot shows a planted crop and the seed count decreases by one

#### Scenario: Plant with no seeds
- **WHEN** the player interacts with an empty plot while holding no seeds
- **THEN** nothing is planted and the seed count is unchanged

### Requirement: Planted crops grow over time
The system SHALL advance a planted crop through visible growth stages over a short real-time duration.

#### Scenario: Crop matures
- **WHEN** a crop has been planted for its growth duration
- **THEN** the crop displays its mature stage
