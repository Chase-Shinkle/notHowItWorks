# Spec Delta

## Purpose

Teaches the crop-as-structure idea by showing it: the first room starts with a half-grown crop the player finishes with one seed.

## ADDED Requirements

### Requirement: Half-grown demo crop
The system SHALL start the first room with a half-grown crop already present, reaching toward the exit.

#### Scenario: Demo visible on arrival
- **WHEN** the player enters the first room
- **THEN** a half-grown crop and the unreachable exit it leads toward are visible

### Requirement: One seed finishes the demo
The system SHALL make the first room solvable by planting a single seed to complete the demo structure.

#### Scenario: Finish the demo
- **WHEN** the player plants the required seed to complete the half-grown structure
- **THEN** the exit becomes reachable
