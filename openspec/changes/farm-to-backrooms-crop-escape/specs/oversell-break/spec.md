# Spec Delta

## Purpose

Defines the bug the player causes by selling more than they own, which starts the farm's break and delivers the theme payoff.

## ADDED Requirements

### Requirement: Villager keeps asking for more
The system SHALL have a villager keep asking for crops after the player's crop inventory is empty.

#### Scenario: Villager keeps prompting
- **WHEN** the player has sold their last crop to a villager
- **THEN** the villager continues to prompt for another crop

### Requirement: Over-selling starts the break
The system SHALL start the break sequence when the player tries to sell with zero crops after having completed at least one normal sale.

#### Scenario: Over-sell breaks the farm
- **WHEN** the player has completed at least one sale and tries to sell with zero crops
- **THEN** the break sequence starts

#### Scenario: No break before a normal sale
- **WHEN** the player has not completed any sale and tries to sell with zero crops
- **THEN** the break sequence does not start

### Requirement: Idle fallback trigger
The system SHALL start the break sequence on its own if the player has completed a sale and then makes no over-sell attempt within a set idle time.

#### Scenario: Idle player is pushed along
- **WHEN** the idle time elapses after a completed sale without an over-sell attempt
- **THEN** the break sequence starts
