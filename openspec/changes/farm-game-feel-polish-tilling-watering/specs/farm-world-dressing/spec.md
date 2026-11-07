# Spec Delta

## Purpose

Makes the farm look like a place instead of a flat grid, using the existing art pack, without changing how the player moves or reaches things.

## ADDED Requirements

### Requirement: Fenced plots, path and landmarks
The farm SHALL show fence pieces flanking the plot block, a dirt path leading to the villager and the seed stall, the barn behind the villager, a well, berry bushes and a small pond. All art SHALL come from the shipped sprite pack or be drawn in code.

#### Scenario: Landmarks visible
- **WHEN** the farm is shown
- **THEN** the fence, path, barn, well, bushes and pond are all visible and none overlaps the HUD bars, the player start tile, a plot, the villager or the stall

### Requirement: Dressing blocks movement predictably
Tiles occupied by solid dressing (fence, barn, well, pond, bushes) SHALL NOT be walkable. Tiles with only decoration on the ground (path, tufts, stones) SHALL remain walkable.

#### Scenario: Cannot walk through the barn
- **WHEN** the player moves toward a barn, well, pond, fence or bush tile
- **THEN** the player does not enter it and only turns to face it

#### Scenario: Path is walkable
- **WHEN** the player moves onto a path tile
- **THEN** the player moves normally

### Requirement: Everything stays reachable
After dressing is placed, every plot, the villager and the seed stall SHALL still be usable from at least one walkable tile, and that tile SHALL be reachable from the player start.

#### Scenario: Reachability check
- **WHEN** the layout is checked from the player start tile
- **THEN** each plot, the villager and the stall have a reachable walkable neighbour

### Requirement: Ground variation and depth
The field SHALL vary its ground with deterministic scattered tufts and stones, and sprites on the field (farmer, villager, stall, props, crops) SHALL cast a soft shadow. The same layout SHALL appear on every run.

#### Scenario: Stable layout
- **WHEN** the farm is entered twice
- **THEN** the ground variation is identical both times

### Requirement: Gentle ambient motion
Bushes, grass tufts and crops SHALL sway slightly and the pond SHALL shimmer, with motion small enough not to distract and no effect on game rules.

#### Scenario: Idle motion
- **WHEN** the player does nothing for a few seconds
- **THEN** the scene still shows slight motion, and positions of interactive tiles do not change

### Requirement: Wet and tilled soil is visible
A tilled plot SHALL look different from an untilled one, and a watered plot SHALL look different again (darker, wet).

#### Scenario: Three soil looks
- **WHEN** plots in the untilled, tilled and watered states are on screen
- **THEN** each state has its own look
