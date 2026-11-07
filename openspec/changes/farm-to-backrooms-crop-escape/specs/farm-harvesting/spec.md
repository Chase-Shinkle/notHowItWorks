# Spec Delta

## Purpose

Lets the player harvest mature crops on the 2D farm so they have goods to sell.

## ADDED Requirements

### Requirement: Harvest a mature crop
The system SHALL let the player harvest a mature crop, adding it to the inventory and clearing the plot.

#### Scenario: Harvest mature crop
- **WHEN** the player interacts with a plot holding a mature crop
- **THEN** one harvested crop is added to the inventory and the plot becomes empty

### Requirement: Immature crops cannot be harvested
The system SHALL NOT harvest a crop that has not reached its mature stage.

#### Scenario: Interact with immature crop
- **WHEN** the player interacts with a plot holding an immature crop
- **THEN** the crop stays planted and the inventory is unchanged
