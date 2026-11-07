# Spec Delta

## Purpose

Separates the names players read from the internal seed-type keys, so the `vine` seed can be presented as corn without renaming data or art.

## ADDED Requirements

### Requirement: Player-facing seed names
Every player-visible name of a seed type SHALL come from a single display-name mapping. The `vine` type SHALL display as "corn". The other types SHALL keep their current names.

#### Scenario: Hint and popups
- **WHEN** the player plants, harvests, buys or sells the `vine` type
- **THEN** hints, popups and the villager's lines say "corn" and never "vine"

#### Scenario: HUD and shop
- **WHEN** the farm HUD and seed stall mention the `vine` type
- **THEN** they say "corn"

### Requirement: Backrooms uses the same names
Any seed-type name shown in the backrooms HUD SHALL use the same mapping.

#### Scenario: Backrooms HUD
- **WHEN** the backrooms HUD lists the vine seed type
- **THEN** it says "corn"

### Requirement: Internal keys unchanged
Seed-type keys used by saved game data, room allotments and logic SHALL NOT change, and the sprites SHALL NOT change.

#### Scenario: Data unaffected
- **WHEN** the display name mapping is used
- **THEN** game data, allotments and carry-over still use the original keys
