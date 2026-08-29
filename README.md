# Skee-ball Prototype

Godot 4.7.1 desktop/mobile-input prototype for a physics-driven skee-ball-style arcade game.

## Current prototype

- Single procedurally modeled arcade cabinet based on classic skee-ball proportions.
- Fixed 3D game camera.
- Mouse and touch swipe controls: begin in the lower portion of the screen, drag upward, and release to roll.
- Horizontal drag adds left/right aim; the swipe itself adds no upward velocity. The physical ramp creates lift.
- Right-click resets the current ball. A second simultaneous touch cancels the current touch gesture and resets the ball.
- Real rigid-body ball physics with tunable launch speed and gravity.
- Basic 10/20/30/40/50/100 target scoring and score/roll counter.
- Escape pause menu with typed numeric tuning controls.
- Optional first-person no-clip debug camera: WASD, Q/E vertical movement, mouse look, Shift for faster movement.
- Enclosed, warmly lit mahogany-colored room around the machine to provide a stable visual reference.

## Model note

The cabinet is generated from Godot primitives and a custom curved runway/ramp mesh. No Sketchfab model or third-party cabinet mesh is included in the repository.

## Build

The GitHub Actions workflow imports the project with Godot 4.7.1, performs an 8-second headless smoke test, exports `SkeeBallPrototype.exe`, and uploads the Windows executable as an artifact.
