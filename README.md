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

The current implementation renders roughly 15,500 low-poly sand orbs over a deformable heightfield. The field is split into red, blue, yellow, and green material quadrants. Color is stored as simulation state rather than calculated from current position.

Foot contacts displace/compact the heightfield and form small lips around footprints. The projectile detonates after three seconds, flashes red progressively faster, excavates a crater, builds a berm, and launches colored rigid-body sand chunks. Those chunks retain their source color and redeposit material where they settle.

This is intentionally a first simulation architecture rather than a claim that every visible orb is already an independent rigid body. Tens of thousands of individual Godot rigid bodies would be the wrong scaling model; later iterations can move the granular solver toward GPU compute while retaining the interaction APIs established here.

## Character placeholder

The project uses the CC0 [KayKit Skeletons Character Pack](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) as a placeholder. Assets are fetched during CI rather than committed into this repository.

For local Windows development, run:

```powershell
./tools/fetch_assets.ps1
```

The player dynamically searches the imported KayKit model for a walk/run animation and a throw/attack animation. If named foot/ankle bones can be identified, their animated world positions drive footprint placement; otherwise a gait-timed fallback is used.

## Windows builds

`.github/workflows/windows-build.yml` intentionally does **not** build on ordinary pushes. It runs for pull-request commits (open/synchronize/reopen) and manual dispatches, exports an embedded-PCK Windows x86-64 `SandGame.exe`, and uploads the executable as a workflow artifact.
