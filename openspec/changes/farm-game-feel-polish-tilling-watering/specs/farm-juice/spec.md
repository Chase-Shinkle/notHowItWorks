# Spec Delta

## Purpose

Gives every farm action small, immediate feedback (particles, motion, numbers and sound) so the loop feels satisfying even before any new mechanic.

## ADDED Requirements

### Requirement: Action bursts
Tilling, planting, watering, harvesting and selling SHALL each emit a short particle burst at the tile involved, with a distinct look per action, and the affected sprite SHALL pop (a brief scale bounce).

#### Scenario: Harvest burst
- **WHEN** the player harvests a mature crop
- **THEN** a particle burst appears on that plot and the crop pops before it disappears

#### Scenario: Effects clean up
- **WHEN** an effect finishes
- **THEN** it is removed and no effects remain after a few seconds without input

### Requirement: Harvested crops fly to the HUD
A harvested crop SHALL animate from its plot to its produce slot in the top bar, and the slot SHALL pulse on arrival. The stored count SHALL be correct immediately and not wait for the animation.

#### Scenario: Fly and count
- **WHEN** the player harvests a crop
- **THEN** the crop icon travels to that type's HUD slot, the slot pulses when it lands, and the count was already incremented

### Requirement: Coin ticker
The displayed coin amount SHALL move toward the real amount over a short time rather than jumping, for both gains and spending, and SHALL pulse while it changes. The real amount SHALL be unaffected.

#### Scenario: Sale ticks up
- **WHEN** the player sells a crop worth 5 coins
- **THEN** the displayed coins count up to the new total within about a second, and coin sparkles appear

#### Scenario: Spending ticks down
- **WHEN** the player buys a seed
- **THEN** the displayed coins count down to the new total

### Requirement: Growth-stage squash
When a crop advances to its next growth stage, its sprite SHALL squash and stretch briefly, and a small sparkle SHALL show on maturity.

#### Scenario: Stage change
- **WHEN** a growing crop reaches its next stage
- **THEN** the plot's sprite plays a short squash-and-stretch and then rests at normal scale

### Requirement: Sound effects
Tilling, planting, watering, harvesting, selling, buying, denial and the break SHALL each play a soft sound effect from files shipped in `sounds/`. If a sound file is missing or fails to load, the game SHALL still run silently for that sound.

#### Scenario: Distinct cues
- **WHEN** the player tills, waters, or is denied
- **THEN** each plays its own sound, and the denial sound is quiet rather than harsh

#### Scenario: Missing sound
- **WHEN** a sound file cannot be loaded
- **THEN** the action still works and nothing crashes

### Requirement: Effects respect the break
During the break sequence, new action effects SHALL NOT be created and ambient motion SHALL NOT interfere with the break's shake and corruption.

#### Scenario: Break plays cleanly
- **WHEN** the break starts
- **THEN** only the existing break effects play until the change to the backrooms
