# Spec Delta

## Purpose

Lets the player plant chosen seeds on fixed plots in the backrooms and watch them grow into structures.

## ADDED Requirements

### Requirement: Plant only on designated plots
The system SHALL allow seeds to be planted only on a room's designated plots.

#### Scenario: Plant at a plot
- **WHEN** the player is near an empty plot and plants a selected seed
- **THEN** that seed type is planted and one seed of that type is consumed

#### Scenario: No planting elsewhere
- **WHEN** the player tries to plant while not near a plot
- **THEN** nothing is planted and no seed is consumed

### Requirement: Choose the seed to plant
The system SHALL let the player select which seed type to plant and SHALL show the count of each type.

#### Scenario: Seed count shown
- **WHEN** the player plants a seed
- **THEN** the displayed count for that type decreases by one

### Requirement: Visible timed growth
The system SHALL grow a planted seed to its full structure over a few seconds, with its size visibly increasing, and SHALL make it collidable at its grown size.

#### Scenario: Structure grows
- **WHEN** a seed is planted
- **THEN** its structure grows to full size within a few seconds and can then be stood on or climbed
