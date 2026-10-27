# VictorOps Zombies

**Public repo.** Original first-person, round-based zombie survival shooter for Android (and desktop) built with **Godot 4.7.2 (GDScript)**.
Hold an abandoned facility against endless rounds: board up windows, buy doors, restore power, gamble at the **Mystery Crate**, drink **Iron Hide Tonic**, **Quickhand Draught** or **Fleetfoot Phial**, and upgrade your gun at the **Overcharge Forge**. Play as **Snoop Dogg** (Bass Drop) or **Martha Stewart** (Fortify).

- `scripts/rules/` – pure game rules (rounds, economy, weapons, crate, perks, forge, armor, barricades), unit-tested
- `scripts/game/` – 3D game: player controller, zombies (navmesh AI), facility map, HUD, touch controls
- `tests/` – GUT tests · `audio/` – original synthesized sounds (`tools/gen_audio.py`)
- `legacy/libgdx/` – previous Kotlin/libGDX version (kept for VictorLink64, see `docs/VICTORLINK64.md`)

## Controls
Desktop: WASD move, mouse look, LMB fire, RMB aim, R reload, E use (hold to repair), 1/2 or wheel swap, Shift sprint, Q ability.
Touch: left floating stick, swipe right side to look, FIRE/AIM/RLD/USE/SWAP/SKILL/RUN buttons.

## Build
```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gexit          # tests
# Android: install the Gradle build template into android/build (see .github/workflows/godot.yml)
GODOT_ANDROID_KEYSTORE_DEBUG_PATH=... GODOT_ANDROID_KEYSTORE_DEBUG_USER=... GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=... \
  godot --headless --export-debug Android build/victorops-zombies-debug.apk
tools/sign_apk.sh build/victorops-zombies-debug.apk         # v2+v3 sign + verify (keys from env)
```
Package `com.victorious.zombie`, minSdk 24, targetSdk 35, arm64-v8a + armeabi-v7a. Signing keys are never committed; CI uses the `VOZ_*` secrets.

## Roadmap
- **Legacy scaffold (v0, `legacy/libgdx/`)** already had Wi-Fi/LAN co-op (host-authoritative) + Bluetooth via VictorLink64 `NetLink` (not device-tested), hardened TCP networking and the Fortify cooldown fix (#4). Co-op *was* built there — just not yet in the Godot version.
- **Next (Godot):** port co-op (ENet LAN, host-authoritative, revive) and the VictorLink64 hook-up (see `docs/VICTORLINK64.md`).
- **Later:** more maps, special enemy types, high scores, settings, controller support, release build. Assets & licenses: see `ASSETS.md`.
