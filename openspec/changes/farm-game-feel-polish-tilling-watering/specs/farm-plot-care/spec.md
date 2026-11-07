# Spec Delta

## Purpose

Adds tilling and watering to the farm: plots must be prepared before planting, and watering rewards the player with faster growth, so the farm loop has more than one verb.

## ADDED Requirements

### Requirement: Plots must be tilled before planting
An empty, untilled plot SHALL NOT accept a seed. Using it SHALL till it instead. A tilled plot SHALL stay tilled after its crop is harvested.

#### Scenario: First use tills
- **WHEN** the player uses an empty untilled plot
- **THEN** the plot becomes tilled, no seed is consumed, and feedback is shown

#### Scenario: Tilled plot accepts a seed
- **WHEN** the player uses an empty tilled plot while holding a seed
- **THEN** the seed is planted and one seed is consumed

#### Scenario: Replanting after harvest
- **WHEN** a crop is harvested from a plot
- **THEN** the plot is empty but still tilled, so the next use plants without tilling again

### Requirement: Watering a crop
Using a growing, unwatered plot SHALL water it. A plot SHALL be watered at most once per crop, and the water SHALL be lost when the crop is harvested. Watering SHALL be unlimited and need no refill.

#### Scenario: Water a growing crop
- **WHEN** the player uses a growing plot that is not watered
- **THEN** the plot becomes watered, and the soil looks visibly wet

#### Scenario: Already watered
- **WHEN** the player uses a growing plot that is already watered
- **THEN** the plot is unchanged and the hint reports that it is growing

#### Scenario: Water is lost on harvest
- **WHEN** a watered crop is harvested and the plot is planted again
- **THEN** the new crop starts unwatered

### Requirement: Watered crops grow faster
A watered crop SHALL grow at the full growth rate. An unwatered crop SHALL still grow, at half that rate. Growth SHALL never be blocked.

#### Scenario: Watered timing
- **WHEN** a crop is planted and watered immediately
- **THEN** it reaches maturity in the existing full-rate time

#### Scenario: Unwatered timing
- **WHEN** a crop is planted and never watered
- **THEN** it still reaches maturity, in twice the full-rate time

#### Scenario: Watering mid-growth
- **WHEN** a crop is watered part-way through growing
- **THEN** its progress so far is kept and the remainder grows at the full rate

### Requirement: Context-sensitive use and hints
The use key and click SHALL pick the action from the plot's state (till, plant, water, harvest), and the hint bar SHALL name that action and the tool involved.

#### Scenario: Hint matches the action
- **WHEN** the player faces an empty untilled plot, a tilled plot, an unwatered growing plot, or a mature plot
- **THEN** the hint bar shows till, plant, water or harvest respectively

### Requirement: Care does not affect the break
Tilling and watering SHALL NOT start the break, reset the idle break timer, or change the over-sell trigger. The break SHALL still freeze all farm input and growth.

#### Scenario: Tilling after the first sale
- **WHEN** the player has sold once and then tills or waters
- **THEN** the idle break countdown continues from the last sale
