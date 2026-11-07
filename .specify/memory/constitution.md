<!--
Sync Impact Report
- Version change: (unfilled template) → 1.0.0
- Modified principles: none renamed (initial adoption)
- Added sections: Core Principles I–V, Technical Constraints, Jam Workflow, Governance
- Removed sections: none
- Deferred TODOs: none. Game-specific design (2D opening game, backrooms loop) is intentionally
  left to /speckit-specify.
-->
# Not Supposed To Work That Way Constitution

## Core Principles

### I. Jam-Scope First (NON-NEGOTIABLE)
Every task MUST serve a shippable game by the jam deadline. Prompts and effort are scarce, so each
feature MUST be the smallest version that delivers its intended player experience. Features that
are not required for the core arc (2D game → break → backrooms) MUST be cut or deferred.
Rationale: an unfinished ambitious game loses to a finished small one.

### II. Theme Is the Design Spine
Every design decision MUST reinforce the theme "It's Not Supposed to Work That Way". The game
MUST present a clear arc: a simple, believable 2D game; a glitch or break the player notices; a
transition into a 3D backrooms game. The break MUST feel like the game itself failing, not a
scripted cutscene. Mechanics SHOULD subvert expectations the 2D game established.

### III. Always Playable
The `main` branch MUST launch and be playable end to end at all times with `love .`. Work MUST
land in small increments, each leaving the game runnable. Placeholder art, sound, and text are
acceptable; a crashing build is not.

### IV. Reuse Before Build
The existing structure MUST be used: `StateMachine` and `states/` for game phases, `Entity` for
actors, `constants.lua` for tunables, `Dependencies.lua` for requires, `g3d` for 3D, and `push`
for 2D scaling. New libraries or abstractions MUST NOT be added unless existing ones demonstrably
cannot do the job.

### V. Decide Late, Prototype Fast
The 2D game's design and the backrooms gameplay loop are undecided. Specs MUST propose the
simplest candidate loop and keep it swappable behind state boundaries. Playtesting beats
speculation: when a design question can be answered by a quick prototype, prototype it.

## Technical Constraints

- Engine: LÖVE (Lua). Dependencies live in `lib/` and `g3d/`; no build step or external services.
- Assets (art, models, sound, shaders) MUST be original, jam-permitted, or properly licensed, and
  MUST be credited in the README.
- Target 60 FPS on a typical laptop. Avoid per-frame allocations in hot paths.
- The 2D and 3D phases MUST be separate states with a clean hand-off so that either can be
  developed and tested in isolation.
- Tunable values (speeds, sizes, timings) MUST live in `constants.lua`, not scattered inline.

## Jam Workflow

- Use the Spec Kit flow lightly: `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` →
  `/speckit-implement`, skipping optional steps (checklist, analyze) unless risk justifies them.
- Each spec MUST be scoped to one playable slice (e.g., "2D game", "the break", "backrooms
  loop"), and each MUST list a manual playtest check as its acceptance test.
- Automated tests are OPTIONAL; a manual run-through of the affected slice before commit is
  REQUIRED.
- Commit after each working slice with a descriptive message.

## Governance

This constitution supersedes other practices for this project. Amendments MUST be made via
`/speckit-constitution`, with a version bump: MAJOR for removed or redefined principles, MINOR
for new principles or materially expanded guidance, PATCH for clarifications. Plans and specs
MUST be checked against these principles; any deviation MUST be justified in writing in the
plan. During the jam, compliance review is informal and happens at each slice commit.

**Version**: 1.0.0 | **Ratified**: 2026-11-06 | **Last Amended**: 2026-11-06
