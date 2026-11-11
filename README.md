# VICTOR ZOMBIES
**By Victorious Framework**

Original offline, single-player, first-person, round-based zombie survival for **Android** (first-class) and desktop.
Engine: **Godot 4.7.2 stable**, GDScript only, Mobile renderer (GL Compatibility fallback). Version **10.0.0**, package `com.victorious.zombie`.

This README is the project's living guide (Victorious Framework): status, controls, architecture, how to run, export and verify, attribution, and what is left.

## Status (v10.0.0 — final implementation run)

| Area | State | Evidence |
|---|---|---|
| Main menu → How to play → match → pause → results → restart / menu | Done | scene check (headless) + desktop screenshots |
| Three districts, seven buyable doors, two closed loops | Done | scene check: navigation before and after every door, both loops walked by the player capsule |
| **Power objective** (crank the generator) with signs, cable, beacon and an on-screen objective line | Done (new in v10) | scene check + screenshots |
| Wall weapons, ammunition, Mystery Crate, three tonics, Overcharge Forge, timed pickups | Done; purchase-safety fixes in v10 | scene check |
| Shambler, jogger / sprinter, Bloater, **Brute elite with a telegraphed slam** (new behaviour in v10), Warden boss | Done | scene check + 10-round bot run |
| Settings (graphics, audio, sensitivity, invert look, shake, touch layout) saved to disk | Done | unit tests (round trip) |
| Best round, best score, **lifetime kills / headshots / matches / Brutes** (new in v10) | Done | scene check + unit tests |
| Restart clears match state and keeps settings and records | Done | scene check (15 assertions on the new match) |
| Touch (three simultaneous fingers), keyboard + mouse, gamepad | Implemented | touch: synthetic events in the scene check. **No hardware test.** Gamepad: not exercised by any automated check |
| Android APK | See *Export an Android APK* | built and inspected with `aapt` / `apksigner`; **never installed or run on a device or emulator** |
| Frame rate, thermals, audio output, touch feel on a phone | **Not measured** | needs a device |
| Co-op, more maps | Deferred (out of scope) | — |

Not production-ready: nothing in this repository has been run on Android hardware.

## The game loop

Menu → **START MATCH** → a 4 s countdown → round 1. Kill zombies for points (+10 hit, +60 kill, +100 headshot kill, +130 knife kill), spend them, survive the 10 s break (health refills, countdown on screen), repeat until you bleed out. The results screen shows the run (rounds, kills, headshots, points, districts opened, power, Brutes), **best round**, **best score** and **lifetime totals** (all in `user://highscore.cfg`), then *Play again* or *Main menu*.

**Map — Ashgrove, Main Street.** An abandoned town at blue-gray dusk. Six rooms form **three districts** (`Facility.DISTRICTS`); the first time you enter a room its name and district are called out on screen, and every door label names the district behind it.

| District | Rooms | Landmarks | How it opens |
|---|---|---|---|
| **Diner Block** (start) | Victory Diner, Back Alley | red-banded diner, generator trailer with the strobing beacon | Back Alley door 750 |
| **Workshop Row** | Mercer's General Store, Hollis Auto Repair | store mezzanine and Mystery Crate, the Overcharge Forge's spinning rings | Store 1000, Garage shutter 1250, Service Door 1000 |
| **Main Street** | Main Street, Courtyard | army container blockade, evacuation tent | Street 1250, Side Alley 1000, Courtyard gate 1250 |

```
        Sealed Annex (hidden)                         army container blockade
              |                                              |
   Back Alley ──(Garage 1250)── Hollis Auto Repair      MAIN STREET ── storefronts
   GENERATOR (power objective)  Overcharge Forge             |   (pharmacy, barber, hotel)
     750 |                          | Service Door 1000      |
   Victory Diner ──(1000)── Mercer's General Store ──(1250)──┘
     start                  mezzanine, Mystery Crate         |
                                    | Side Alley 1000    (Courtyard gate 1250)
                                    └────────────── COURTYARD (Evacuation Point B)
```

Two closed loops: Diner → Back Alley → Garage → Store → Diner, and Store → Main Street → Courtyard → Side Alley → Store. Each loop crosses two districts, so opening a district always opens a second way out. Zombies enter only through the boarded windows of rooms you have opened.

**Power objective.** The amber line at the top of the screen is the current objective. It starts as *Restore power · open the Back Alley (750) behind the diner*. A sign over the diner's back door reads *NO POWER — GENERATOR ▸ BACK ALLEY*, a cable with amber marker lamps runs down the alley to the generator, and a beacon strobes over it. At the generator, **hold USE**: each tick is one crank (4 needed, about 1.5 s, and you are exposed while you do it). Power switches on the room lights, the **Overcharge Forge** and all five **tonic machines**; the signs, lamps and beacon turn green and the objective moves on to the districts still closed. Unpowered machines say so in their prompt and sell nothing.

**Weapons** (tuning in `scripts/rules/weapons.gd`):

| Weapon | Damage | Fire | Mag / reserve | Reload | Spread | Cost |
|---|---|---|---|---|---|---|
| Volt Sidearm (starter pistol) | 80 | semi, 0.28 s | 8 / 80 | 1.3 s magazine | 0.5° | — |
| Buzzsaw SMG | 70 | auto, 0.07 s | 32 / 224 | 1.8 s magazine | 2.2° | 1000 |
| Scatterbolt (pump-action shotgun) | 6 × 60 | pump, 0.75 s | 6 / 54 | 0.4 s per shell | 5.0° | 1200 |
| Pulse Rifle (automatic) | 110 | auto, 0.11 s | 30 / 180 | 2.0 s magazine | 1.0° | 1400 |

Headshots ×2. Walls stop bullets. Ammunition refills at the wall for half the gun's price (only when not full). Two weapon slots; a third gun replaces the one in hand.

**Mystery Crate** (950, price shown on its sign and in the prompt): a random weapon from a weighted table (Scatterbolt, SMG, Pulse Rifle, Grinder LMG, Rail Lancer, Nova Disruptor). v10: it never rolls a weapon you already carry, so it cannot overwrite an upgraded gun with a stock one.

**Enhancements (tonics, need power, bought once each):**

| Tonic | Cost | Effect |
|---|---|---|
| Iron Hide Tonic | 2500 | maximum health ×2 |
| Quickhand Draught | 3000 | reload time ×0.5 |
| Fleetfoot Phial | 2000 | sprint lasts 60% longer, move 15% faster |
| Marksman Mist | 2500 | headshots ×3, steadier aim |
| Lazarus Fizz | 2000 | get back up once when downed (costs every tonic) |

Owned tonics are listed top-right on the HUD, and the pause screen lists each one with its effect.

**Overcharge Forge** (garage, needs power, 5000): Mk.2 = ×2 damage, ×2 magazine, 20% faster fire, 15% faster reload, +2 pellets on the shotgun, a new name, a purple camouflage skin on the gun and a purple tracer. The gun is inside the machine for 5 s and cannot be fired, swapped out or traded during that time.

**Temporary pickups** (kill drops, a glowing ring with an icon; blink before they vanish after 25 s): RESTOCK (all ammunition), DOUBLE PAY (points ×2, 30 s), ONE TOUCH (every hit kills, 30 s), BLACKOUT (kills everything alive), HANDYMAN (all windows rebuilt). Each shows a banner with its effect when taken, and timed ones count down at the bottom of the screen.

**Enemies.**

| Type | From | Role |
|---|---|---|
| Shambler | round 1 | slow, 150 HP on round 1 |
| Jogger / sprinter gaits | rounds 3 / 6 | the same zombie, faster; a growing share each round |
| Sprinter | round 3 | lean, fast, 60% health |
| Bloater | round 4 | bursts into a damaging gas cloud |
| **Brute (elite)** | rounds 4, 8, 12, … (two from round 12) | 6× health, armour halves body shots |
| Warden (boss) | round 15, 30 | boss bar, same slam |

The **Brute** is larger and wider than anything else, plated, with a hot orange halo around its unarmoured head (the weak point, ×2 damage), heavy footsteps that shake the camera and a name bar at the top of the screen. Its ordinary swing takes 0.5 s to wind up (a walker's takes 0.22 s). Its **slam**: inside 4.2 m it plants its feet, roars, and a red ring 3.2 m in radius flashes on the floor for 1.1 s; it stops tracking you halfway through, so walking out of the ring avoids it. Inside the ring you take 70 damage. After the slam it is **winded for 2 s**: it stands bent over and its armour does nothing, so body shots count in full. Killing it pays 500 points on top of the kill and always drops RESTOCK. The first Brute round and the first slam each show a one-line hint.

Difficulty comes from several dials, not only health: zombies per round (6 → 39 by round 8), spawn pace (2.0 s → 0.4 s), gait mix, special types, the Brute schedule and Frenzy rounds every fifth round (fewer, all sprinting). Health rises 100 per round to round 9, then 10% per round. At most 24 are alive at once; the last one of a round crawls and glows so the round always ends.

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

The same table, plus the loop and every price, is in the game under **How to play** (main menu and pause screen); a four-step tutorial runs on the first match and can be skipped.

Settings (menu and pause, saved to `user://settings.cfg`): look sensitivity, invert vertical look, look curve, camera shake, graphics Low / Medium / High, music and effects volume, music style, aim assist, auto-fire, gyro, stick mode, button size and opacity, and a drag-to-place touch layout editor (safe-area aware). The pause screen also shows the objective, both weapons with their stats, owned tonics and running timed effects, and has Resume / How to play / Restart match / Main menu.

## Run

```bash
godot --path . --import            # first time: import assets (Godot 4.7.2)
godot --path .                     # play on desktop
godot --path . -- --touch          # desktop with the touch HUD forced on
```
In the Android Godot editor: open the folder, let it import, press Play.

## Verify

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit      # 285 rule tests (pure logic)
godot --headless --fixed-fps 60 -- --check              # 138 scene checks, exit code 0 = all passed
godot --headless --fixed-fps 60 -- --sim=10             # a bot plays rounds 1-10 and prints a report
xvfb-run -a godot --rendering-driver opengl3 -- --v10shots=<dir>   # 12 review screenshots (needs a display)
```

Results of this pass (Godot 4.7.2, Linux, 2026-11-11): 285 / 285 tests, 137 / 138 scene checks, bot reached round 11 with 245 kills, 0 downs and 0 stuck zombies (it met Brutes on rounds 4 and 8).

`--check` (`scripts/game/self_check.gd`) drives the real scene without a renderer. It covers the complete flow in order: countdown and three rounds; exact damage, headshots, walls, shotgun, reload and switch rules; an unaffordable door, a door charged once, navigation after every door, both loops; wall weapon and ammunition; **the power objective through the real interaction** (prompt, one crank per press, power on, signs switch, tonics refused before power); the Forge (charged once, gun locked, stats doubled); pickups and expiry; **each tonic charged once and its effect on the player; the pause status text; the crate's price sign, refusal when short, one charge per roll, never a carried weapon; no weapon trade while the gun is in the Forge; a knock-down during an upgrade still returns the upgraded gun; self-revive removes tonic effects; the Brute's health, armour, weak point, slam telegraph, dodge, hit, winded window, bounty and drop**; hit grace and regeneration; pause, the pause menu and the focus-loss rule; three simultaneous touches; death, results text, records and **lifetime totals; then restart: power off, objective reset, no tonics, stock weapons, no enemies, no timed effects or pickups, normal time scale, zeroed statistics, settings unchanged, records kept; back to the menu and into a third fresh match**.

What the automated checks do **not** show: rendering on a phone GPU, real audio output, frame rate, how the touch controls feel, a real Android pause/resume cycle (only the pause rule and the notification handler's logic are tested), gamepad input, and the Low preset on real hardware (it was only applied in desktop software rendering).

Screenshots were reviewed by eye for the menu, How to play, the power signs and cable, the crank prompt, power on, the crate sign, the Brute (walking, slam ring, winded), the pause status and the results screen. Review sheets: `docs/v10_flow.jpg` (High preset: menu, How to play, power sign, cable and generator, crank prompt, power on, crate sign, pause status, results) and `docs/v10_low_touch_brute.jpg` (Low preset with the touch HUD: Brute, slam ring, winded, crank prompt, power on, results). Both are desktop software OpenGL at 1280 × 720, not a phone.

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
**Built in this pass (v10.0.0):** a **debug** APK, `build/victor-zombies-debug.apk`, about 227 MB, exported with the commands above on Linux (Godot 4.7.2, JDK 21, build-tools 35.0.0) and signed with a throwaway debug key. Checked with `aapt2 dump badging` and `apksigner verify`: package `com.victorious.zombie`, versionCode 10, versionName 10.0.0, minSdk 24, targetSdk 35, `arm64-v8a` + `armeabi-v7a`, APK Signature Scheme v2 verifies. v10 also drops the INTERNET, network-state and Wi-Fi permissions (left over from the co-op plan); only VIBRATE remains. The APK is **not committed** (it is over GitHub's 100 MB file limit and `*.apk` is git-ignored) and it was **not installed or launched** on any device or emulator: the sandbox has neither. A release build was not made here because no release keystore exists in this environment; CI builds one on every push (below). The first Gradle run needs network access to Google's and Maven Central's repositories; one attempt here failed with HTTP 429 from Maven Central and succeeded on retry.

Release: `--export-release` with `GODOT_ANDROID_KEYSTORE_RELEASE_*`, then `tools/sign_apk.sh`. CI (`.github/workflows/godot.yml`) runs the tests and the scene check, exports a release APK and uploads it as the `victor-zombies-apk` artifact on every push. Signing keys are never committed. minSdk 24, targetSdk 35, arm64-v8a + armeabi-v7a, landscape, immersive.

## Architecture

- `scripts/rules/` — pure, unit-tested rules and **all tuning values**: `rounds.gd` (counts, health, speed, spawn pace, cap), `weapons.gd` / `weapon_def.gd`, `economy.gd`, `facility.gd` (doors, areas, windows), `forge.gd`, `power_ups.gd`, `ammo.gd`, `loadout.gd`, `high_score.gd`, `game_settings.gd` (quality presets), `zombie_types.gd`, `gait.gd`.
- `scripts/game/` — the 3D game: `game.gd` (match, round director, purchases, pause), `player.gd` (movement, input, guns), `zombie.gd` (navmesh AI, attacks, death), `facility_map.gd` (town shell: walls, roofs, facades, lamps, machines; navmesh rebaked when a door opens) + `town_kit.gd` (mesh batcher and building / furniture pieces) + `scenery.gd` (dressing, vehicles, signage, skyline), `hud.gd`, `touch_controls.gd`, `viewmodel.gd` / `fps_arms.gd`, `fx.gd`, `sfx.gd`, `self_check.gd`.
- `scripts/main.gd` — menu and command-line modes (`--check`, `--sim`, `--shots`, `--clip`, `--views`, `--hud`, `--v8shots`, `--town`, `--v10shots`). `scripts/game/help_panel.gd` — the How to play card.
- `tests/` — GUT tests. `tools/` — audio generators and APK signing. `legacy/libgdx/` — the earlier 2D Kotlin/libGDX version, kept as the backup of the original project.

Decisions in v10 (final run):
- **Three districts by grouping, not by rebuilding.** The six rooms and seven doors of v9 are kept exactly (collision, navigation and spawn lanes were already verified); districts are a rules-level grouping that drives the door labels, the room call-outs, the objective line and the results screen. Cost: a district is two rooms with a door between them, not one open space.
- **Power is a hold interaction, not a button.** Four cranks reuse the existing hold-to-repair input, so it works identically on touch, keyboard and pad and needed no new control.
- **Elite = the existing Brute, given a real attack.** It previously hit for 99 damage after a 0.22 s wind-up, which one-shot a 100 HP player with no warning. Now: 63 on a 0.5 s swing, 70 on a 1.1 s slam with a floor ring, a winded window that rewards dodging, first appearance on round 4 instead of 8, health 6× instead of 8×.
- **Silhouettes survive being shot.** The hit flash reset every zombie's model scale to 1, so Brutes, Bloaters and Sprinters lost their shape (and Brutes their head height) on the first bullet; and the Brute's plates kept an absolute size, so they sat hidden inside the enlarged body. Both fixed; found by looking at screenshots, not by the tests.
- **Purchase safety.** Nothing can be bought from the floor (downed); a gun inside the Forge cannot be replaced by a wall gun, crate gun or bench gun; the Forge returns the gun to the loadout it left even if a last stand swapped loadouts in between (before v10 that gun stayed locked for the rest of the match); the crate excludes every carried weapon.
- **Nothing leaks between matches.** Each match is a new `Game` node; `Engine.time_scale` (the only engine-global the match touches) is reset when a match ends, exits the tree, restarts or returns to the menu.
- **Totals live beside the records** in the same file under their own section, so v8 / v9 save files load unchanged.

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
- New door or room: add it to `Facility.DOORS` / `WINDOWS` / `DISTRICTS` / `AREA_RECTS`, cut the gap in `facility_map.gd`, extend `_t_purchases_and_nav` in `self_check.gd`.
- Elite tuning: `ZombieTypes.SLAM_*`, `BRUTE_EVERY`, `ALL.brute`; behaviour in `zombie.gd` (`_slam_start`, `_slam_land`).
- Help text: `scripts/game/help_panel.gd` builds itself from the rule tables; change the rules, not the text.
- New weapon: `Weapons.make`, a model name in `Weapons.MODELS`, optionally `WALL_PRICES`.
- After any gameplay change: bump `config/version` in `project.godot` and `version/*` in `export_presets.cfg`, update this file.

## Remaining work and limits

- Not yet run on a physical phone: frame rate, thermals, touch feel, gyro, safe-area insets, focus-loss pause and gamepad mapping are untested on hardware.
- **Draw calls are over the project's own 300 budget in the widest views.** Measured on desktop software OpenGL at the Low preset (no shadows), 16 first-person views: 130–550 per frame, median about 270; the worst are looking the length of the Back Alley or across the diner with doors open. At High (shadows on) the same views are 330–1340. Occlusion culling and detail batching brought Low down from 160–730. Next steps if a phone shows a problem: merge the small Quaternius props per area, and atlas the kit materials.
- Occlusion culling needs the engine's Embree module, which Godot ships for arm64 and x86_64; on a 32-bit ARM phone it silently does nothing and the draw-call numbers are the higher ones.
- The town's room proportions are inherited from the v8 layout (see *Decisions in v9*).
- The main-menu backdrop still shows the old concrete bay.
- The Brute's weak point is a translucent orange bubble around the stock head model rather than a bespoke model: unmistakable, but crude. It was judged in screenshots at about 5 m only.
- One-line hints share the screen position of the backpack slots and can overlap them for a few seconds.
- Menus are not navigable by gamepad (buttons need touch or mouse).
- Side content from earlier passes (Sealed Annex, Pact Stone, Gloam Harp, gadgets, Upgrade Paks, armour) is still in the game and was only regression-tested in this run, not re-balanced against the new Brute schedule.
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
