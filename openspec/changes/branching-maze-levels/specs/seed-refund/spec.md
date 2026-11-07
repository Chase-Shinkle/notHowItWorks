# Spec Delta

## Purpose

Defines how uprooting a planted crop returns its seed, so experimenting with plots is cheap while seed holdings stay small.

## ADDED Requirements

### Requirement: Uprooting refunds the seed
The system SHALL return one seed of the crop's type to the player's stock when the crop is uprooted, whether it is growing or fully grown.

#### Scenario: Refund a grown crop
- **WHEN** the player uproots a grown crop
- **THEN** their count of that seed type increases by one and the plot becomes free

#### Scenario: Refund a growing crop
- **WHEN** the player uproots a crop still growing
- **THEN** the seed is returned and the pending growth is cancelled

### Requirement: Refund limits
The system SHALL still refuse to uproot the tutorial demo crop and a crop the player is standing on or inside, and SHALL NOT refund in those cases.

#### Scenario: Standing on a crop
- **WHEN** the player is on a grown crop and tries to uproot it
- **THEN** nothing is removed and no seed is returned

### Requirement: Stock never exceeds what was collected
The system SHALL NOT let refunds raise a seed type's count above the number of that type the player has collected plus any starting stock.

#### Scenario: Plant and uproot repeatedly
- **WHEN** the player plants and uproots the same seed many times
- **THEN** their count of that type returns to the same value each time
