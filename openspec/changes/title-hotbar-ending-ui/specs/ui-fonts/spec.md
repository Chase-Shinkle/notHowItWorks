# Spec Delta

## Purpose

Defines the display font used for the title, buttons and ending text, how text sizes stay legible at any window size, and how a missing font degrades safely.

## ADDED Requirements

### Requirement: Display font for headline UI
The title, the menu buttons and the ending headline SHALL be drawn with the supplied display font (`fonts/SaH1Outline.ttf`). Small functional text (hotbar counts, hints, prompts) SHALL use a font that stays legible at its size.

#### Scenario: Title uses the font
- **WHEN** the title screen is shown with the font file present
- **THEN** the title and buttons are drawn in the supplied font

### Requirement: Font fallback
If the font file is missing or fails to load, every screen SHALL fall back to the built-in font without error and remain usable.

#### Scenario: Missing font file
- **WHEN** the game starts with the font file absent
- **THEN** the title, hotbar and ending are still drawn and no error occurs

### Requirement: Legible at any window size
Text on native-resolution screens SHALL scale with the window height so it remains legible and does not overflow its plate or button.

#### Scenario: Large window
- **WHEN** the window is enlarged
- **THEN** hotbar counts, button labels and ending text grow with it and still fit their frames

### Requirement: Font attribution
The repository SHALL record the supplied font's source and licence in the third-party notices.

#### Scenario: Notice present
- **WHEN** the third-party notices file is read
- **THEN** it names the font, its author and its licence terms
