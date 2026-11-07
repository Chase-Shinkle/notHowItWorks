# Spec Delta

## Purpose

Gives coins a use on the farm by letting the player buy seeds, so seed counts can rise as well as fall and the farming loop can be sustained.

## ADDED Requirements

### Requirement: Seed stall
The farm SHALL contain a seed stall on its own tile, reachable and usable the same way as plots and the villager (face it and press the use key, or click it).

#### Scenario: Stall is visible and hinted
- **WHEN** the player faces or hovers the seed stall
- **THEN** the hint bar shows the selected seed type and its price

### Requirement: Buy seeds with coins
The system SHALL let the player buy one seed of the currently selected type per use, deducting that type's price from coins and adding one seed. Each seed type SHALL have a fixed price lower than the coins a harvested crop of that type sells for.

#### Scenario: Successful purchase
- **WHEN** the player uses the stall with coins at least equal to the selected seed's price
- **THEN** coins decrease by the price, that seed count increases by one, and feedback is shown

#### Scenario: Not enough coins
- **WHEN** the player uses the stall with fewer coins than the price
- **THEN** nothing is bought, coins and seeds are unchanged, and a denial cue and message are shown

#### Scenario: Sustainable loop
- **WHEN** the player plants, harvests and sells one crop, then buys a seed of the same type
- **THEN** the player has more coins than before the plant

### Requirement: Shopping does not affect the break
Buying seeds SHALL NOT start the break, reset the idle break timer, or change whether over-selling triggers the break.

#### Scenario: Buying after the first sale
- **WHEN** the player has sold at least once and then buys seeds
- **THEN** the idle break countdown continues from the last sale and selling with zero crops still starts the break

#### Scenario: Carry-over unchanged
- **WHEN** the break completes
- **THEN** only seeds carry into the backrooms, with the existing Room 1 top-up, and coins are dropped
