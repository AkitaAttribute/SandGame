# SandGame

A Godot 4 desktop prototype exploring a Noita-inspired principle: interactions should apply forces to a simulation instead of swapping in canned effects.

## Prototype controls

- `WASD`: move relative to the camera
- `Space`: force-based jump
- `Left click`: throw a physical blue orb
- `Mouse`: orbit the third-person camera through 360 degrees
- `Mouse wheel`: zoom
- `Esc`: release/capture the mouse

The world uses 0.7 Earth gravity (`6.867 m/s²`). The player is treated as a 20 lb / 9.07 kg body for impulses. Jump velocity is derived from the impulse required to raise that mass approximately one character height.

## Sand prototype

The current implementation uses a fixed pool of 3,072 simulated spherical grains. Each grain owns persistent position, velocity, and material color for the lifetime of the world.

There is no heightfield deformation, crater-generation function, temporary ejecta particle system, or redeposit/paint operation. The granular loop integrates gravity, constrains grains against a physical floor and world bounds, uses a spatial hash for neighboring-grain collision detection, and resolves sphere/sphere contact with restitution and friction.

The four red/blue/yellow/green regions are only initial conditions. Color belongs to each grain and never changes when the grain moves.

The grain solver now uses sleeping. The initial packed bed starts completely inactive, so an untouched desert consumes no granular integration or collision-solving work. Projectile contact and explosions wake only affected grains. Contact can propagate wakefulness into neighboring grains, and low-speed supported grains return to sleep after settling. Only grains whose transforms actually changed are resent to the MultiMesh renderer.

The projectile is still a Godot rigid body. While rolling through the granular region it transfers momentum into overlapping simulated grains. On detonation the sand interaction is only a radial velocity impulse applied to existing grains; those same grains then fly, collide, fall, and settle under the granular solver.

The player is intentionally not coupled to the grain solver in this iteration. A collision layer used only by the player supplies a temporary support plane at the original sand surface height. This lets the bomb/sand simulation be evaluated without fake load-bearing behavior being added to the grain solver.

The custom grain floor and the Godot rigid-body floor are both aligned to y=0. The rigid-body floor is collision-only and has no visible brown box or decorative geometry.

The grain pool is fixed-size, so the sand interaction cannot leak spawned debris entities into the world. Numerical invalid-state guards restore an individual grain to its original position rather than allowing it to disappear into the void.

## Character placeholder

The project uses the CC0 [KayKit Skeletons Character Pack](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) as a placeholder. Assets are fetched during CI rather than committed into this repository.

For local Windows development, run:

```powershell
./tools/fetch_assets.ps1
```

The player dynamically selects idle, walk/run, and throw/attack animation clips from the imported KayKit model. Movement transitions cross-fade back to an idle pose rather than pausing midway through a walk cycle.

## Windows builds

`.github/workflows/windows-build.yml` intentionally does **not** build on ordinary pushes. It runs for pull-request commits (open/synchronize/reopen) and optional manual dispatches, exports an embedded-PCK Windows x86-64 `SandGame.exe`, and uploads the executable as a workflow artifact.

The workflow treats Godot script compilation/runtime errors as failures and performs a short headless runtime smoke test before export.
