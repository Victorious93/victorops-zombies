# VictorOps Zombies

**Public repo.** Original first-person, round-based zombie survival shooter for Android (and desktop) built with **Godot 4.7.2 (GDScript)**.
Hold an abandoned facility against endless rounds: board up windows, buy doors, restore power, gamble at the **Mystery Crate**, drink **Iron Hide Tonic**, **Quickhand Draught**, **Fleetfoot Phial** or **Lazarus Fizz** (solo self-revive, max 3), and upgrade your gun at the **Overcharge Forge**. Play as **Rook Vance**, a night-shift sound tech (Bass Drop), or **Hollis Marrow**, the facility quartermaster (Fortify). *(v2: these original characters replace the earlier celebrity-named placeholders; abilities unchanged.)*

- `scripts/rules/` – pure game rules (rounds, economy, weapons, crate, perks, forge, armor, barricades), unit-tested
- `scripts/game/` – 3D game: player controller, zombies (navmesh AI), facility map, HUD, touch controls
- `tests/` – GUT tests · `audio/` – original synthesized sounds (`tools/gen_audio.py`)
- `legacy/libgdx/` – previous Kotlin/libGDX version (kept for VictorLink64, see `docs/VICTORLINK64.md`)

## Controls
Desktop: WASD move, mouse look, LMB fire, RMB aim, R reload, E use (hold to repair), 1/2 or wheel swap, Shift sprint (stamina), C/Ctrl slide while sprinting, V knife (lunge), Q ability.
Touch: left floating stick, swipe right side to look, FIRE/AIM/RLD/USE/SWAP/SKILL/RUN buttons.

## How it plays (feel pass, v3)
- Round 1: 6 slow shamblers at 150 HP (2 sidearm body shots or 1 knife). +100 HP per round to round 9, then ×1.1 per round. Runners from round 5, max 24 alive, 10 s break with sting + tally marks. The last zombie of a round crawls.
- Points: +10 hit, +60 kill, +100 headshot kill, +130 knife kill, plank repairs (capped 500/round). Doors 750–1250, wall guns 1000–1400 (ammo half price), crate 950, perks 2000–2500, Forge 5000 (~5 s, renamed gun, ×2 damage/mag).
- Zombies come through windows: rip planks, reach in and swipe (2–3 hits downs you). Health regenerates after ~4 s. Downed = last stand with the sidearm and a 10 s bleed-out; solo game over unless you hold Lazarus Fizz.
- Power-ups (30 s, max 4/round): RESTOCK (ammo), ONE TOUCH (insta-kill), DOUBLE PAY, BLACKOUT (kill all), HANDYMAN (rebuild windows).
- Mystery Crate: slowing roll, 9 s take timer, and sometimes **The Phantom** takes the crate (refund) and it moves.

## Bot playtest
`godot --headless --fixed-fps 60 -- --sim=10` – a bot plays rounds 1–10 in the start room (aims, fires, knifes, backs off, rebuys ammo, opens the lab + power at round 4, buys Lazarus/Iron Hide) and prints time per round, kills and downs.

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

## Single-player feel (v4)
- Zombies: wind-up swings, lunges, stagger/knockback, head and leg pops with blood, fling-and-topple deaths (animated, not physics ragdoll), varied groans, rise-from-ground and drop-over-wall spawns; a progress watchdog unsticks blocked zombies.
- Guns: weight per weapon (move speed, kick, impact force), first-shot punch, muzzle light, heavy impacts with sparks and dust, layered reload.
- Camera: sprint FOV kick, landing bob, damage direction arcs, heartbeat + desaturation at low HP.
- Mobile: auto-fire, aim slowdown + magnetism, gyro (off/ADS/always), look curve, fixed/floating stick, fire-button size (Settings).
- Performance/lighting: Medium preset at 0.75 render scale, prop visibility ranges (LOD), darker scene with rim light, gun flashlight, red alarm beacons from round 6.
- `-- --clip=DIR` runs a scripted 30 s trailer route (use with `--fixed-fps 30 --write-movie out.avi`) and saves 6 stills.

## v5 single-player polish
- Special zombies (`scripts/rules/zombie_types.gd`): **Sprinter** (lean, shriek), **Brute** every 8 rounds (armor plates, body-shot armor, guaranteed RESTOCK), **Bloater** (glowing pustules, bursts into a damaging gas cloud).
- PhysicalBone3D ragdolls (capped by quality preset) and gibs on explosive kills.
- Neon cyan->magenta HUD with a painted tally, points tick-up, screen blood; round-start rumble, last-kill slow-mo, crate/forge jingles.
- 30 s skippable first-run tutorial (move, shoot, rebuild, buy) - replay it from the menu Armory.
- **Pump Station** expansion south of the Loading Yard (1250) with the new **Marksman Mist** perk (2500: headshots x3 instead of x2, tighter ADS).
- Menu **Armory**: choose which wall gun hangs in the spawn room.
