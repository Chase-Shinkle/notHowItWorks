# Spec Delta

## Purpose

Adds a slow rhythm to the farm: a repeating day that tints the scene and counts days, without altering rules or the break.

## ADDED Requirements

### Requirement: Repeating day
The farm SHALL run a day of fixed length that passes through dawn, day, dusk and night and then repeats, incrementing the day counter at each new dawn.

#### Scenario: Day rolls over
- **WHEN** a full day length has elapsed
- **THEN** the day counter increases by one and the cycle restarts

### Requirement: Cycle tint
The farm view SHALL be tinted by time of day (warm at dawn and dusk, neutral by day, cool and darker at night). Night SHALL stay readable: interactive tiles, the hint bar and the HUD remain legible.

#### Scenario: Night readable
- **WHEN** it is the darkest time of day
- **THEN** plots, the villager, the stall and the HUD text can still be read

### Requirement: Cycle does not change rules
The day cycle SHALL NOT change growth, prices, the villager, the break timers or carry-over, and SHALL pause during the break.

#### Scenario: Growth unaffected
- **WHEN** a crop grows across a day boundary
- **THEN** its growth timing is the same as within a day

#### Scenario: Frozen during the break
- **WHEN** the break sequence plays
- **THEN** the time of day does not advance

### Requirement: Fresh farm starts in daylight
A newly entered farm SHALL start at day 1 in daylight, so the first seconds are bright and clear.

#### Scenario: Start of run
- **WHEN** the farm is entered
- **THEN** it is day 1 and the scene is not tinted for night
