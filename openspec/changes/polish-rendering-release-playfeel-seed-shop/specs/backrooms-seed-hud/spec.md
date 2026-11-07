# Spec Delta

## Purpose

Keeps the backrooms HUD honest by showing only the seed types the current room can use.

## ADDED Requirements

### Requirement: HUD lists usable seed types only
The backrooms HUD SHALL list only the seed types the current room has an allotment for, and SHALL NOT show coins.

#### Scenario: Room 1
- **WHEN** the player is in Room 1 with extra pumpkin and vine seeds from the farm
- **THEN** the HUD shows only the beanstalk count

#### Scenario: Room 2
- **WHEN** the player is in Room 2
- **THEN** the HUD shows the pumpkin and vine counts and not beanstalk

#### Scenario: Room 3
- **WHEN** the player is in Room 3
- **THEN** the HUD shows beanstalk, pumpkin and vine counts

### Requirement: Seed selection stays within usable types
The seed-select keys SHALL only select usable seed types for the current room; keys for hidden types SHALL do nothing.

#### Scenario: Hidden type key
- **WHEN** the player presses the key for a seed type hidden in the current room
- **THEN** the selection does not change

#### Scenario: Cycling
- **WHEN** the player cycles seeds with Q or Tab
- **THEN** only visible seed types are visited

### Requirement: Hiding does not change seed rules
Hidden seed counts SHALL still be tracked and the carry-over and per-room allotment rules SHALL be unchanged.

#### Scenario: Reset room
- **WHEN** the player resets a room
- **THEN** the seeds recorded on entering that room are restored exactly as before
