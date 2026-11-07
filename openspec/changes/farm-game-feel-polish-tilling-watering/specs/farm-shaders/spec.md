# Spec Delta

## Purpose

Gives the farm a lit, polished look through a post-process shader pass (sun, bloom, glimmer, day tint) that can never prevent the game from rendering.

## ADDED Requirements

### Requirement: Farm post-process pass
The farm view SHALL be drawn through a shader pass that adds a warm sun tint with soft light shafts, a gentle bloom on bright areas, a glimmer on mature crops and the pond, and the day-cycle tint. The pass SHALL animate over time.

#### Scenario: Pass active
- **WHEN** the farm is shown on a machine where the shader compiles
- **THEN** the sun tint, bloom, glimmer and day tint are visible and animate

### Requirement: Safe fallback
If the shader fails to compile or the canvas cannot be created, the farm SHALL render without it, with no crash and no blank screen, and SHALL log the reason once.

#### Scenario: Compile failure
- **WHEN** the shader cannot be compiled
- **THEN** the farm renders normally without the pass

#### Scenario: Placeholder-assets launch
- **WHEN** the game is launched with `--placeholder-assets`
- **THEN** the farm still renders and is playable

### Requirement: Tunable without editing shader code
Intensities, colours and day length used by the pass SHALL be read from named constants, so the look can be tuned without editing the shader source.

#### Scenario: Tuning
- **WHEN** a constant such as bloom strength is changed to zero
- **THEN** that effect disappears and nothing else changes

### Requirement: Pixel-art fidelity
The pass SHALL keep the farm at its virtual resolution and keep pixel art crisp; effects SHALL NOT blur sprite edges beyond the bloom glow.

#### Scenario: Crisp sprites
- **WHEN** the pass is active
- **THEN** sprite and text edges remain sharp apart from bloom around bright areas

### Requirement: Break and backrooms unaffected
During the break the pass SHALL NOT hide or soften the corruption, shake and fade. The backrooms SHALL NOT use this pass.

#### Scenario: Break visible
- **WHEN** the break sequence plays
- **THEN** the corruption blocks and the fade to black are fully visible
