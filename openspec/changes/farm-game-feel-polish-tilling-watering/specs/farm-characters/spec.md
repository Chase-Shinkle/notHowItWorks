# Spec Delta

## Purpose

Makes the player and the villager instantly distinguishable and gives the buyer personality, and shows the tool the farmer is about to use.

## ADDED Requirements

### Requirement: Distinct villager sprite
The villager SHALL use its own sprite that differs from the player's in hair colour and clothing (a hat and an apron). It SHALL NOT rely on a draw-time tint of the player's sprite.

#### Scenario: Told apart in a screenshot
- **WHEN** the player and villager are both on screen
- **THEN** their hair colour and clothing differ clearly, without relying on a tint

### Requirement: Player sprite unchanged
The player's sprite SHALL remain the hero sprite, so existing recognisability is kept.

#### Scenario: Player look
- **WHEN** the farmer is drawn
- **THEN** it uses the hero sprite

### Requirement: Tool on the farmer
While the farmer faces a plot that can be tilled, planted, watered or harvested, the matching tool icon (shovel, seed bag, watering can, sickle) SHALL be shown beside the farmer. No icon SHALL show when nothing usable is faced.

#### Scenario: Tool changes with state
- **WHEN** the farmer faces an untilled plot, then a tilled one, then an unwatered growing one, then a mature one
- **THEN** the icon is a shovel, the selected seed bag, a watering can and a sickle in turn

### Requirement: Villager reacts
The villager SHALL react to a sale with a small bounce, and its speech bubble SHALL keep working as it does today.

#### Scenario: Sale reaction
- **WHEN** the player sells a crop
- **THEN** the villager bounces briefly and its line is shown
