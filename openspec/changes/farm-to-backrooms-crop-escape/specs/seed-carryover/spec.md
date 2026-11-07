# Spec Delta

## Purpose

Defines what the player keeps when falling from the farm into the backrooms: seeds only, so the farm's loop feeds the puzzle mechanic.

## ADDED Requirements

### Requirement: Seeds carry over
The system SHALL carry the player's seeds into the backrooms.

#### Scenario: Seeds survive the fall
- **WHEN** the player enters the backrooms after the break
- **THEN** the player holds the seeds they had at the break

### Requirement: Coins and crops do not carry over
The system SHALL NOT carry coins or harvested crops into the backrooms.

#### Scenario: Only seeds remain
- **WHEN** the player enters the backrooms
- **THEN** no coins or harvested crops are available

### Requirement: Minimum seeds guaranteed
The system SHALL top up the player's seeds to the amount the first room needs when they arrive with fewer.

#### Scenario: Low-seed arrival
- **WHEN** the player enters the backrooms holding fewer seeds than the first room requires
- **THEN** the player is granted enough seeds to solve the first room
