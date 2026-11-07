# Spec Delta

## Purpose

Defines the backrooms sound: rug footsteps while walking and a humming ambience, played only while the player is in the backrooms.

## ADDED Requirements

### Requirement: Hum only in the backrooms
The system SHALL play the backrooms hum as a looping ambience while the backrooms are active, and SHALL stop it when leaving them. It SHALL NOT play in the start screen, farm, fall transition or ending.

#### Scenario: Enter the backrooms
- **WHEN** the backrooms begin
- **THEN** the hum starts and loops

#### Scenario: Leave the backrooms
- **WHEN** the player reaches the ending or the state changes away
- **THEN** the hum stops

#### Scenario: Not on the farm
- **WHEN** the farm is active
- **THEN** the hum is not playing

### Requirement: Footsteps while walking
The system SHALL play a rug footstep sound each time the player has walked a stride's distance while on the ground, choosing among the five footstep sounds.

#### Scenario: Walk
- **WHEN** the player walks on the ground
- **THEN** footsteps play at a cadence matching the distance walked

#### Scenario: Standing still
- **WHEN** the player is not moving
- **THEN** no footsteps play

### Requirement: No footsteps when not walking
The system SHALL NOT play footsteps while the player is airborne, falling or climbing, or when the game is not in the backrooms.

#### Scenario: Climbing
- **WHEN** the player climbs a beanstalk
- **THEN** no footsteps play

#### Scenario: On the farm
- **WHEN** the player walks on the farm
- **THEN** no rug footsteps play

### Requirement: Footstep variation
The system SHALL avoid playing the same footstep sound twice in a row and SHALL vary pitch and volume slightly.

#### Scenario: Consecutive steps
- **WHEN** two footsteps play in succession
- **THEN** they use different footstep sounds

### Requirement: Safe with missing audio
The system SHALL keep running if a sound file is missing or audio is unavailable.

#### Scenario: Missing sound
- **WHEN** a footstep or hum file cannot be loaded
- **THEN** the backrooms still play normally in silence for that sound

### Requirement: Volumes are balanced
The system SHALL set hum and footstep volumes so footsteps are audible over the hum without being loud.

#### Scenario: Balance
- **WHEN** both play together
- **THEN** footsteps are clearly audible over the hum
