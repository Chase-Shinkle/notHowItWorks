# Spec Delta

## Purpose

Makes the farm's top bar quickly readable: seeds and harvested produce are visually separate, empty items recede, and coins and days are clear.

## ADDED Requirements

### Requirement: Seeds and produce are separated
The top bar SHALL show seed bags and harvested produce in separate groups with a visible divider between them.

#### Scenario: Divider present
- **WHEN** the farm HUD is drawn
- **THEN** a divider sits between the seed group and the produce group

### Requirement: Empty slots are dimmed
A seed slot or produce slot whose count is zero SHALL be drawn dimmed. The selected seed slot SHALL stay highlighted even when empty.

#### Scenario: Dim and restore
- **WHEN** a count goes from 0 to 1
- **THEN** its slot is drawn at normal brightness, and dimmed again when it returns to 0

### Requirement: Coin icon
The coin amount SHALL be drawn next to a coin icon rather than as a trailing "c" suffix in the HUD. Prices in hints and popups MAY still use text.

#### Scenario: Coin counter
- **WHEN** the player has coins
- **THEN** the top bar shows a coin icon beside the amount

### Requirement: Day counter
The top bar SHALL show the current day number, starting at day 1.

#### Scenario: Initial day
- **WHEN** a new farm starts
- **THEN** the HUD shows day 1

### Requirement: HUD fits
All HUD elements SHALL fit within the top bar at the virtual resolution without overlapping each other or the hint bar.

#### Scenario: Large counts
- **WHEN** coins and counts reach three digits
- **THEN** no HUD element overlaps another
