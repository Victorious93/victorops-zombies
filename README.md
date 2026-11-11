# VICTOR ZOMBIES
**By Victorious Framework**

Original offline, single-player, first-person, round-based zombie survival for **Android** (first-class) and desktop.
Engine: **Godot 4.7.2 stable**, GDScript only, Mobile renderer (GL Compatibility fallback). Version **9.0.0**, package `com.victorious.zombie`.

This README is the project's living guide (Victorious Framework): status, controls, architecture, how to run, export and verify, attribution, and what is left.

## Status (v9.0.0)

| Area | State |
|---|---|
| Main menu → match → results → restart | Done |
| **Map art direction: abandoned town (v9)** | Done: the quarantine facility is replaced by Ashgrove's Main Street. Reviewed from the first-person camera in 16 views × 2 lighting states (software OpenGL, desktop) |
| Pistol / automatic rifle / pump-action shotgun (+ SMG, LMG, rail, wonder weapons) | Done |
| Rounds, points, doors, wall weapons, ammo, upgrade station, pickups, records | Done; carried over unchanged onto the new map |
| Looping routes | Two loops: Diner–Back Alley–Garage–Store (v8) and Store–Main Street–Courtyard–Side Alley (new in v9) |
| Walls stop bullets **and zombie melee** | Melee wall check new in v9 |
| Touch, keyboard + mouse, gamepad | Done in code and in the scripted scene check; **not tested on hardware** |
| Settings | Look sensitivity, look curve, camera shake (new in v9), graphics preset, touch button size / opacity / layout, gyro, volumes |
| Android APK | See *Export an Android APK* for what was built in this pass; **never run on a phone or emulator** |
| Measured performance on a phone | **Not measured.** Desktop draw-call counts are listed under *Remaining work and limits* |
| Co-op, more maps | Deferred |

## The game loop

Menu → **START MATCH** → a 4 s countdown → round 1. Kill zombies for points (+10 hit, +60 kill, +100 headshot kill, +130 knife kill), spend them, survive the 10 s break (health refills, countdown on screen), repeat until you bleed out. The results screen shows the run, **best round** and **best score** (saved in `user://highscore.cfg`), then *Play again* or *Main menu*.

**Map — Ashgrove, Main Street.** An abandoned town at blue-gray dusk, mid-evacuation. You start in the **Victory Diner** (two boarded windows, a wall weapon, the Tech Locker). Doors are bought with points and each opens exactly once:

```
        Sealed Annex (hidden)                         army container blockade
              |                                              |
   Back Alley ──(Garage 1250)── Hollis Auto Repair      MAIN STREET ── storefronts
   generator + power switch     Overcharge Forge             |   (pharmacy, barber, hotel)
     750 |                          | Service Door 1000      |
   Victory Diner ──(1000)── Mercer's General Store ──(1250)──┘
     start                  mezzanine, Mystery Crate         |
                                    | Side Alley 1000    (Courtyard gate 1250)
                                    └────────────── COURTYARD (Evacuation Point B)
```

Two closed loops: Diner → Back Alley → Garage → Store → Diner, and Store → Main Street → Courtyard → Side Alley → Store. Zombies enter only through the boarded windows of areas you have opened: from the parking lot into the diner, and out of the neighbouring buildings everywhere else. The diner and store also have shattered display windows you can see through but not pass or shoot through.

The rule ids for the areas are unchanged from v8 (`intake`, `generator`, `cold`, `lab`, `yard`, `pump`), which is why the economy, spawns and tests carried over; only the labels and the scenery changed, plus the one new `alley` door.

**Weapons** (tuning in `scripts/rules/weapons.gd`):

| Weapon | Damage | Fire | Mag / reserve | Reload | Spread | Cost |
|---|---|---|---|---|---|---|
| Volt Sidearm (starter pistol) | 80 | semi, 0.28 s | 8 / 80 | 1.3 s magazine | 0.5° | — |
| Pulse Rifle (automatic) | 110 | auto, 0.11 s | 30 / 180 | 2.0 s magazine | 1.0° | 1400 |
| Scatterbolt (pump-action shotgun) | 6 × 60 | pump, 0.75 s | 6 / 54 | 0.4 s per shell | 5.0° | 1200 |

Headshots ×2 (the top of the zombie's body, hit by the bullet ray itself). Walls stop bullets. Ammo refills at the wall for half the gun's price.
Reload rules: a magazine reload is all-or-nothing and is abandoned if you switch weapons; the shotgun loads one shell at a time and firing interrupts it; a gun inside the Forge cannot be used; an empty gun in hand starts reloading by itself.

**Upgrade station:** the Overcharge Forge in the garage (needs the generator in the Back Alley running): 5000 points → Mk.2 with ×2 damage, ×2 magazine, faster fire and reload, a new name and tracer colour.
**Pickups** (dropped by kills, 30 s): RESTOCK (all ammo), DOUBLE PAY (points ×2), ONE TOUCH, BLACKOUT, HANDYMAN.
**Zombies:** shamblers only in rounds 1–2, joggers from 3, sprinters from 5–6, Bloaters and a Brute every 8 rounds; at most 24 alive; the last one of a round crawls. Each swing has a wind-up, and hits landing within 0.4 s of each other count once, so a stacked pack cannot delete your health in one frame. Health regenerates 4 s after the last hit.

## Controls

| Action | Touch | Keyboard + mouse | Gamepad |
|---|---|---|---|
| Move | left stick (floating or fixed) | WASD | left stick |
| Look | drag anywhere on the right half (FIRE also steers) | mouse | right stick |
| Fire / Aim | FIRE / ADS toggle | LMB / RMB | RT / LT |
| Reload / Switch | buttons | R / 1, 2, X, wheel | RB / Y |
| Use, buy (hold to rebuild) | contextual USE button | E | X |
| Sprint / Jump / Crouch-slide | buttons | Shift / Space / C or Ctrl | L3 / A / B |
| Knife / Grenade / Ability / Gadget | buttons | V / G / Q / F | R3 / LB / D-pad up / D-pad right |
| Pause | pause button, Android back, or leaving the app | Esc, or the window losing focus | Start |

Settings (menu and pause): look sensitivity, graphics Low / Medium / High, music and effects volume, aim assist, auto-fire, gyro, stick mode, button size and opacity, and a drag-to-place touch layout editor (safe-area aware).

## Run

```bash
godot --path . --import            # first time: import assets (Godot 4.7.2)
godot --path .                     # play on desktop
godot --path . -- --touch          # desktop with the touch HUD forced on
```
In the Android Godot editor: open the folder, let it import, press Play.

## Verify

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit      # 263 rule tests (pure logic)
godot --headless --fixed-fps 60 -- --check              # 74 scene checks, exit code 0 = all passed
godot --headless --fixed-fps 60 -- --sim=10             # a bot plays rounds 1-10 and prints a report
```
`--check` (`scripts/game/self_check.gd`) drives the real scene without a renderer: countdown and three rounds, exact single damage, headshot region, walls blocking shots, shotgun pellets, reload and switch rules, ammo never negative, door bought once and not by holding the button, navigation before and after each door, the loop, wall weapons and ammo, the Forge, pickups, hit grace and regeneration, pause and resume, three simultaneous touches (move + aim + fire), death, saved records and restart.
New in v9: a zombie's swing through a wall does no damage, the Side Alley loop opens the Courtyard and closes onto Main Street, every window has a walkable spawn lane and a way in, every purchase / machine / pick-up can be walked up to, and the player capsule travels both loops without snagging on scenery.

Review sheets from this pass (desktop, software OpenGL, with test walkers): `docs/v9_town_dusk.jpg`, `docs/v9_town_power.jpg`.

Visual review (needs a display or `xvfb-run`; software OpenGL is enough): `godot --rendering-driver opengl3 -- --town=<dir>` saves 16 first-person views (diner, back alley, garage, store, Main Street, courtyard, Side Alley) before and after the power is on and prints draw calls per view. `VOZ_TOWN_ZOMBIES=1` stands walkers in each view, `VOZ_PRESET=low` uses the phone preset.

None of these prove rendering on a phone GPU, sound, frame rate or how the touch controls feel in the hand; those need a device.

## Export an Android APK

Needs: Godot 4.7.2 export templates, JDK 17 or 21, Android SDK (`platform-tools`, `platforms;android-35`, `build-tools;35.0.0`).

```bash
# 1. tell Godot where the SDK and JDK are (editor: Editor Settings > Export > Android)
# 2. install the Gradle build template once
mkdir -p android/build && unzip -q ~/.local/share/godot/export_templates/4.7.2.stable/android_source.zip -d android/build
printf '4.7.2.stable' > android/.build_version && touch android/build/.gdignore
# 3. debug APK (any debug keystore)
GODOT_ANDROID_KEYSTORE_DEBUG_PATH=debug.keystore GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey \
GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android godot --headless --export-debug Android build/victor-zombies-debug.apk
```
Release: `--export-release` with `GODOT_ANDROID_KEYSTORE_RELEASE_*`, then `tools/sign_apk.sh`. CI (`.github/workflows/godot.yml`) runs the tests and the scene check, exports a release APK and uploads it as the `victor-zombies-apk` artifact on every push. Signing keys are never committed. minSdk 24, targetSdk 35, arm64-v8a + armeabi-v7a, landscape, immersive.

## Architecture

- `scripts/rules/` — pure, unit-tested rules and **all tuning values**: `rounds.gd` (counts, health, speed, spawn pace, cap), `weapons.gd` / `weapon_def.gd`, `economy.gd`, `facility.gd` (doors, areas, windows), `forge.gd`, `power_ups.gd`, `ammo.gd`, `loadout.gd`, `high_score.gd`, `game_settings.gd` (quality presets), `zombie_types.gd`, `gait.gd`.
- `scripts/game/` — the 3D game: `game.gd` (match, round director, purchases, pause), `player.gd` (movement, input, guns), `zombie.gd` (navmesh AI, attacks, death), `facility_map.gd` (town shell: walls, roofs, facades, lamps, machines; navmesh rebaked when a door opens) + `town_kit.gd` (mesh batcher and building / furniture pieces) + `scenery.gd` (dressing, vehicles, signage, skyline), `hud.gd`, `touch_controls.gd`, `viewmodel.gd` / `fps_arms.gd`, `fx.gd`, `sfx.gd`, `self_check.gd`.
- `scripts/main.gd` — menu and command-line modes (`--check`, `--sim`, `--shots`, `--clip`, `--views`, `--hud`, `--v8shots`, `--town`).
- `tests/` — GUT tests. `tools/` — audio generators and APK signing. `legacy/libgdx/` — the earlier 2D Kotlin/libGDX version, kept as the backup of the original project.

Decisions in v9 (town rebuild):
- **Same coordinates, new town.** Every wall line, door gap, window and station keeps its v8 position, so collision, navigation, spawn safety, purchases and progression were preserved by construction rather than re-tuned. The cost: room proportions are inherited (the diner is 20 × 20 m).
- **Batched architecture.** `TownKit` merges static boxes into one mesh per material per 10 m cell (structure) or 20 m cell (small detail, distance-culled at 36 m). 10 m cells keep every lit surface under the renderer's 8-lights-per-object limit. Collision is separate invisible boxes, so visuals never change the navmesh.
- **Indoor render layer.** Roofed geometry is on render layer 3 and the dusk directional light skips it, so the skylight cannot leak indoors when shadows are off (the Low and Medium presets).
- **Occlusion culling** is on (`rendering/occlusion_culling`): every solid wall run and roof is a `BoxOccluder3D`.
- **Atmosphere without murk.** Fog density went from 0.055 to 0.008 (thin aerial haze), ambient is a readable blue-gray, the sky is a procedural gradient instead of the night HDRI, and the ground-mist and fog cards were removed. Mood comes from warm lanterns, red emergency lamps, firelight and the skyline.
- **Original art, generated.** `tools/gen_town_art.py` draws the facades, skyline, signs, broken glass, road paint, corrugated steel and booth vinyl deterministically; no new third-party assets were added (the sandbox has no access to asset sites).
- GL Compatibility only: shadowed omni lamps directly overhead rendered the first-person arms black through the viewmodel overlay; omni shadows are now off on that renderer (the dusk light keeps its shadow).

Decisions in v8: the loop was closed with one extra door rather than re-cutting rooms; the per-shell reload keeps the old 2.4 s full-reload time (6 × 0.4 s); hit grace lives in the player so every damage source obeys it; records are stored beside the existing best run so old save files still load.

## Maintenance

- Balance: edit `scripts/rules/*.gd`, run the three commands under *Verify*.
- New door or room: add it to `Facility.DOORS` / `WINDOWS`, cut the gap in `facility_map.gd`, extend `_t_purchases_and_nav` in `self_check.gd`.
- New weapon: `Weapons.make`, a model name in `Weapons.MODELS`, optionally `WALL_PRICES`.
- After any gameplay change: bump `config/version` in `project.godot` and `version/*` in `export_presets.cfg`, update this file.

## Remaining work and limits

- Not yet run on a physical phone: frame rate, thermals, touch feel, gyro, safe-area insets, focus-loss pause and gamepad mapping are untested on hardware.
- **Draw calls are over the project's own 300 budget in the widest views.** Measured on desktop software OpenGL at the Low preset (no shadows), 16 first-person views: 130–550 per frame, median about 270; the worst are looking the length of the Back Alley or across the diner with doors open. At High (shadows on) the same views are 330–1340. Occlusion culling and detail batching brought Low down from 160–730. Next steps if a phone shows a problem: merge the small Quaternius props per area, and atlas the kit materials.
- Occlusion culling needs the engine's Embree module, which Godot ships for arm64 and x86_64; on a 32-bit ARM phone it silently does nothing and the draw-call numbers are the higher ones.
- The town's room proportions are inherited from the v8 layout (see *Decisions in v9*).
- The main-menu backdrop still shows the old concrete bay.
- APK size: about 203 MB with both ABIs because the engine libraries are stored uncompressed; an arm64-only build with `gradle_build/compress_native_libraries=true` is about 80 MB. Texture and audio trimming is open.
- Lighting is real-time with fake light pools, not baked.
- Later: co-op (design in `docs/VICTORLINK64.md`), a second map, more controller polish (rebinding, menu navigation by pad).

## Assets

All third-party assets are CC0; sources and licences are listed file by file in `ASSETS.md` (Quaternius and Kenney models, ambientCG textures). The town art in `assets/town/` is original, generated by `tools/gen_town_art.py`. Sounds and music are original and synthesised by the scripts in `tools/`. Game code is under the licence in `LICENSE`.

---

# History (earlier passes)

## How it plays (feel pass, v3)
- Round 1: 6 slow shamblers at 150 HP (2 sidearm body shots or 1 knife). +100 HP per round to round 9, then ×1.1 per round. Runners from round 5, max 24 alive, 10 s break with sting + tally marks. The last zombie of a round crawls.
- Points: +10 hit, +60 kill, +100 headshot kill, +130 knife kill, plank repairs (capped 500/round). Doors 750–1250, wall guns 1000–1400 (ammo half price), crate 950, perks 2000–2500, Forge 5000 (~5 s, renamed gun, ×2 damage/mag).
- Zombies come through windows: rip planks, reach in and swipe (2–3 hits downs you). Health regenerates after ~4 s. Downed = last stand with the sidearm and a 10 s bleed-out; solo game over unless you hold Lazarus Fizz.
- Power-ups (30 s, max 4/round): RESTOCK (ammo), ONE TOUCH (insta-kill), DOUBLE PAY, BLACKOUT (kill all), HANDYMAN (rebuild windows).
- Mystery Crate: slowing roll, 9 s take timer, and sometimes **The Phantom** takes the crate (refund) and it moves.

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

## v7 single-player polish

- **Scenery:** CC0 ambientCG PBR materials (concrete, brick, asphalt, plaster, rust, wood), CC0 Quaternius props (wrecked cars, dumpsters, debris, dead trees, barriers, street lights), Poly Haven night HDRI sky, layered depth fog + mist cards, fire barrels, procedural blood/grime decals.
- **Viewmodel:** CC0 rigged WRAD arms on a separate viewmodel layer/camera (no wall clipping, fixed 60° FOV), two-bone IK to grip and fore-end, sway/bob/sprint/ADS/reload/swap motion.
- **Zombies:** rotting skin with wounds and blood runs, glowing eyes, procedural hunch/limp/head-twitch, reaching arms when close, arm dismemberment on heavy hits; distinct silhouettes per type.
- **Touch HUD:** floating left stick, right-half look, big FIRE (+ optional left FIRE), thumb arc (ADS, reload, jump, crouch, grenade, swap, knife, skill), contextual Use/Buy, neon icons, safe-area aware. **Settings → Controls…** has size/opacity/fire-size sliders and a drag layout editor (saved locally; overlapping or off-screen drops are rejected).
- **Movement:** jump (Space / touch), crouch toggle (C / Ctrl / touch); crouch while sprinting still slides.
- Also in v7: Pact Stone quest, alt-ammo, boss round, run stats + high score, announcer.

## v6 single-player polish (classic round-based feel)
- **Gunfeel** (`scripts/rules/gun_feel.gd`): per-weapon ADS zoom (Rail Lancer zooms hardest, Scatterbolt least) with zoom-matched aim sensitivity, extra camera kick scaled by weight (softer when aiming) and weight-based recovery, coloured hitmarkers (body / head / armor / kill / head-kill) with a hit tick, two-frame muzzle flash flicker, flesh/metal/wall impact and ricochet sounds, heavier reload beats.
- **Zombies**: gait tiers by round (`scripts/rules/gait.gd`: walkers only on rounds 1-2, joggers from round 3, sprinters from round 6, mostly sprinters by round 12), planks visibly yanked off windows one by one, a two-stage climb-in over the sill, directional hit reactions (`scripts/rules/hit_react.gd`: head snap, left/right twist, leg stumble, knockback).
- **Map flow**: buyable doors now judder, slide down with dust, rumble and a chain rattle; new atmospheric round-start and round-end stings with the music ducked underneath.
- **Mobile**: touch buttons re-laid on two thumb arcs around FIRE (`scripts/rules/touch_layout.gd`, tested for no overlaps from 4:3 to 20:9); AIM on touch snaps toward the nearest zombie in a 12 degree cone when aim assist is on.

## v5 single-player polish
- Special zombies (`scripts/rules/zombie_types.gd`): **Sprinter** (lean, shriek), **Brute** every 8 rounds (armor plates, body-shot armor, guaranteed RESTOCK), **Bloater** (glowing pustules, bursts into a damaging gas cloud).
- PhysicalBone3D ragdolls (capped by quality preset) and gibs on explosive kills.
- Neon cyan->magenta HUD with a painted tally, points tick-up, screen blood; round-start rumble, last-kill slow-mo, crate/forge jingles.
- 30 s skippable first-run tutorial (move, shoot, rebuild, buy) - replay it from the menu Armory.
- **Pump Station** expansion south of the Loading Yard (1250) with the new **Marksman Mist** perk (2500: headshots x3 instead of x2, tighter ADS).
- Menu **Armory**: choose which wall gun hangs in the spawn room.
