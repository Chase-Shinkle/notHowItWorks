# Spec Delta

## Purpose

Lets the player sell harvested crops to villagers for coins, completing the farm loop.

## ADDED Requirements

### Requirement: Sell a crop to a villager
The system SHALL let the player sell a harvested crop to a villager in exchange for coins.

#### Scenario: Sell a crop
- **WHEN** the player interacts with a villager while holding at least one harvested crop
- **THEN** one crop is removed from the inventory and coins increase by the crop's sale value

### Requirement: Quick first cycle
The system SHALL start the player with enough seeds, a visible plot, and a visible villager to finish one plant, harvest, and sell cycle within the first few minutes, without text-heavy instruction.

#### Scenario: First cycle is possible immediately
- **WHEN** a new game starts on the farm
- **THEN** the player has at least one seed, an empty plot, and a villager on screen
