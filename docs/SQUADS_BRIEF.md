# Brief: squads with revives for Blackout Royale

Status: **not started**. This is a hand-off for a fresh session. Read `docs/BLACKOUT_ROYALE.md` (current design and measured
numbers) and `tools/dev/README.md` (how to build, test, probe and screenshot in this container) first.

## Deliverable: an Android APK
This game ships as an **Android APK** (`:android` module, applicationId `com.victorious.zombie`, minSdk 24, ARM only). The desktop
module (`:lwjgl3`) exists only as a development harness, used for screenshots in this container; it is not the product.
Every feature must therefore be designed and judged for a **phone**:
- **Touch first.** Squads, revive and any new prompt must work with the on-screen controls (left stick, right aim stick, USE,
  HEAL, SKILL, RELOAD). Hold-to-revive has to be usable with a thumb while moving the other. Nothing may depend on a keyboard or mouse.
- **Readable at phone size.** Small text and thin rings that look fine in a 1280x720 desktop window can disappear on a 6-inch screen.
- **Cheap per frame.** Avoid per-tick allocations in hot paths, keep A* repaths bounded, and keep snapshots small (measure bytes).
- The CI workflow (`.github/workflows`) builds the debug APK and checks signatures and ABIs; keep it green. Build the APK
  yourself at the end with the recipe in `tools/dev/README.md` and report the path and size. Say plainly what you could not run
  on a device or emulator.

## Goal
Add a **Squads** variant of Blackout Royale: fighters are grouped into squads, a fighter whose health hits zero is **downed**
(not eliminated) while a teammate lives, and teammates can **revive** them. Last squad standing wins. The existing
free-for-all must keep working unchanged and keep passing its pacing/stuck/jitter tests.

## Where things are
- `core/.../br/BrWorld.kt`: authoritative sim. `Fighter`, `damage()`, `eliminate()`, `checkEnd()`, `startMatch()`,
  `assignLandingAreas()`, `snapshot()`. Implements `sim/Sim.kt`, so the network layer needs no changes.
- `core/.../br/BrBots.kt`: `BrBrain.think()` returns the same `PlayerInput` a human sends. Read the pitfalls in `tools/dev/README.md`.
- `core/.../br/BrSnapshot.kt`: compact codec (`BrFighterSnap`, `BrSelf`, `BrCodec`). Extend both ends together.
- `core/.../BrScreen.kt`: rendering, HUD, minimap, controls (desktop and touch). `ModeSelectScreen.kt` has the game toggle.
- `sim/Snapshot.kt`: `PlayerInput` (aim, fire, heal, reload already exist; `use` is free to mean "revive" near a downed teammate).
- Tests: `core/src/test/.../br/BrTest.kt` (helpers `liveWorld`, `openSpot`). Keep all 118 existing tests green.

## Recommended design (change it if you find a better one, and say why)
**Squads**
- Squad size 3 by default (4 squads of 3 in a field of 12); make size a world parameter (2..4). All humans join squad 0, up to
  its size; spill extra humans into squad 1. Bots fill the rest and teammates of humans are bots.
- No friendly fire (bullets, splash, Bass Drop knockback damage, zombies unaffected). Teammates never block or push each other.
- Squad colour ring around fighters, teammate names always visible, and a small squad panel in the HUD (name, HP/shield, downed state).
- Placement is per squad: the squad's placement = squads alive at the moment it is wiped. Individual `kills` still count.

**Downed and revive**
- At `hp <= 0`: if any teammate is alive and not downed, the fighter becomes **downed**: crawls at ~25% speed, cannot fire
  or use items, bleeds out over ~30 s (`downedT`), is visible and targetable. Otherwise (no teammate able to revive) they are eliminated as today.
- A living teammate within ~60 px holding `use` for ~4 s revives them to ~40% HP, no shield. Reviving is interrupted by the
  reviver taking damage (or releasing). The reviver moves at reduced speed while reviving. Progress decays if interrupted, as in the zombie mode.
- Bleed-out or a squad with no mobile members left eliminates the downed fighter (drop gun and a shield cell, as now).
  Enemy damage to a downed fighter should finish them faster (for example, bleed-out accelerates) so reviving under fire is a real risk.
- Zone damage applies to downed fighters.

**Match end**
- Match ends when one squad remains, or when no human squad member is left alive (existing rule, now per squad). Fix `checkEnd`,
  placements and the result screen ("Placed #n of 4 squads", squad kills).
- Spectating: eliminated humans follow a living teammate first.

**Bots**
- Teammates ignore each other as targets (`scan`), keep within ~350 px of the squad (follow the human or the squad leader when
  not looting or fighting), and prioritise reviving a downed teammate when no enemy is in sight or when the revive is safe
  (cover/LOS check). Downed bots crawl toward cover away from enemies.
- Avoid every known failure mode: add hysteresis to any new threshold (follow leash, revive-or-fight decision), make arrival
  radii smaller than interaction radii, approach by a standable point, no per-tick direction flips. Extend the stuck/jitter
  metrics in `BrBotMatchTest` to cover squad matches.
- Landing areas: squads land together (one home per squad, teammates within a short distance), different squads far apart.

**Networking / UI**
- Extend `BrFighterSnap` (squad id, downed, bleed progress, revive progress) and `BrSelf` (squad mates, revive prompt:
  "Hold E to revive Kade"). Keep the codec bounds-checked and garbage-safe; update `BrNetTest`.
- Lobby: squad mode and size selectable by the host (and a mode toggle in `ModeSelectScreen`). Clients learn the mode from the snapshot.
- Touch: reuse the USE button for revive; make sure the prompt appears.

## Acceptance criteria
1. Unit tests for: no friendly fire (bullets, splash, abilities), going down vs being eliminated, bleed-out, revive success,
   revive interrupted by damage, revive range, last-teammate-down elimination, squad placement and winner, humans-all-dead end rule,
   squad codec round trip, session layer (a client joins the lobby of a squad match).
2. Bot-only squad matches: all finish; pacing stays in a sensible band (state the measured numbers; target roughly 3 to 5 minutes);
   0 stuck bots; jitter within the existing 0.5% limit; revives actually happen (measure how many per match, and how many bot revives succeed).
3. Existing free-for-all tests and its pacing band still pass.
4. Look at real frames with the Xvfb recipe (a desktop render of the same code, so it shows layout and colours, not touch behaviour):
   downed state, revive progress, squad panel, squad rings, lobby options, result screen. Then build the **debug APK**
   (`:android:assembleDebug`) and report its path and size. Report what you could not verify (touch input on a device, real
   two-device play, Bluetooth).
5. Update `docs/BLACKOUT_ROYALE.md` with the rules and measured numbers. Commit in sensible steps and push.

## Out of scope
Sound, vehicles, respawn beacons from fully dead players, ping system, cross-squad alliances.
