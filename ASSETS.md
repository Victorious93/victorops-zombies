# Assets & licenses

VictorOps Zombies is 100% original IP. No assets, audio, names, maps or code from any other game franchise are used or referenced.

| Asset | Source | License |
|---|---|---|
| All 3D geometry (facility map, zombies, weapons, machines, crate) | Built procedurally in GDScript from Godot primitives (`scripts/game/*.gd`) | Original, same license as repo |
| All textures (wall/floor grime) | Generated at runtime with Godot `FastNoiseLite` | Original |
| All sound effects + ambient loop + round stings (`audio/*.wav`) | Synthesized by `tools/gen_audio.py` (Python + numpy DSP, no samples) | Original, same license as repo |
| Logo / launcher icon (`assets/victorops-zombies-logo.jpg`, `icons/*`) | Project's own logo (pre-existing in repo); icons resized from it | Project-owned |
| UI font | Godot default font (bundled in engine) | Engine: MIT / font: OFL (ships with Godot) |
| GUT 9.7.1 (`addons/gut/`, tests only, excluded from APK; bundles AnonymousPro/CourierPrime/LobsterTwo fonts) | https://github.com/bitwes/Gut | MIT (fonts: SIL OFL 1.1, `addons/gut/fonts/OFL.txt`) |
| Godot Engine 4.7.2 runtime | https://godotengine.org | MIT |

No other third-party assets are included.
