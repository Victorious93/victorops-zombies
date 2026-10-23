# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repo. Keep it short and true; update it when something here changes.

## What this is
VictorOps Zombies: an **original** Android game (libGDX 1.13.1 + Kotlin). The product is the **Android APK** (`:android`,
applicationId `com.victorious.zombie`, minSdk 24, target/compile 35, ARM only: arm64-v8a + armeabi-v7a). `:lwjgl3` is a
desktop dev harness only. `:core` holds all game code and the unit tests.

Game modes (picked in `ModeSelectScreen`):
- **Zombies 3D** (`core/.../fps/`, `FpsScreen.kt`): the default. First-person, round-based zombie survival (windows, wall buys,
  doors, box, power, perks, forge). Solo/offline. Design, numbers and what is unverified: `docs/ZOMBIES_3D.md`.
- **Zombie Survival** (`sim/World.kt`, `GameScreen.kt`): top-down 2D round survival, Wi-Fi co-op.
- **Blackout Royale** (`br/`, `BrScreen.kt`): top-down battle royale with bots, free-for-all or squads with revives.
  Design and measured numbers: `docs/BLACKOUT_ROYALE.md`.

## Hard rules
- **No third-party IP.** Do not copy Activision/Call of Duty (or anyone's) code, art, names, logos, fonts, sounds or maps, and do not
  ship or extract anything from commercial game binaries. Genre conventions are fine; assets and branding are not. Everything is
  drawn or generated procedurally. See `docs/VISUAL_DIRECTION.md`.
- **Phone first.** Touch controls for every action, text readable at phone size (`ui` scale 1.6 on touch), no per-frame allocations
  in draw/sim hot paths, bounded pathfinding, small snapshots.
- **Workstream boundary:** another effort owns `GameScreen.kt` and the shared `Look.kt` (visual restyle). Do not edit them unless asked.
- Keep every existing test green. Do not skip, disable or loosen tests to get green.
- Never claim something works on a device: there is no emulator or device in the cloud container. Say what was not verified.

## Build and test
A fresh container has JDK 21 only. One-time setup (JDK 17 + Android SDK) is in `tools/dev/README.md`. Then:

    gradle :core:test --console=plain                         # unit tests (~2.5 min, bot matches dominate)
    gradle :core:test --tests 'com.victorious.zombie.br.BrSquad*' --console=plain
    gradle :core:test --tests 'com.victorious.zombie.fps.*' --console=plain
    gradle :lwjgl3:compileKotlin                              # desktop harness compiles
    export ANDROID_HOME=~/android-sdk && gradle :android:assembleDebug --console=plain
    # APK: android/build/outputs/apk/debug/android-debug.apk

- Without JDK 17 installed, add `-I tools/dev/jdk-override.init.gradle`. Add `-I tools/dev/test-output.init.gradle` to see `println`.
- Summarise results from `core/build/test-results/test/*.xml`, not from scrolling Gradle output.
- Gradle does not notice environment-variable changes: use `:core:cleanTest` before re-running a probe with new env vars.
- A 429 from Maven Central during the APK build is a transient rate limit: wait and retry.
- CI (`.github/workflows/android.yml`) builds the debug APK and checks v2/v3 signatures and ABIs.

## Looking at real frames
Xvfb + software GL works here. Recipes and launchers (`*.kt.txt`, copied in temporarily, deleted before committing) are in
`tools/dev/`. Use `-Dzombie.touch=1` and a phone-like window (e.g. 1170x540) to see the touch HUD. Captures need alpha forced to 255.
Touch input itself cannot be exercised on desktop. `tools/dev/FpsShot.kt.txt` stages Zombies 3D scenes the same way
(the screen takes a pre-built `FpsWorld`).

## Conventions
- Simulations are headless and testable: `BrWorld`, `World`, `FpsWorld` take inputs and `update(dt)`; screens only render and read input.
  Network modes go through the `sim/Sim.kt` interface; codecs must be bounds-checked and garbage-safe.
- Rendering: call `beginShapes(type)` (enables blending) before every `ShapeRenderer` pass, because `SpriteBatch.end()` turns blending off.
  Lay text out with `text()` / `line()` / `lh` so it scales with `ui`.
- Bots: every decision threshold needs hysteresis or a cooldown; arrival radius < interaction radius; approach loot/targets via a
  standable point (`map.nearestFree`); waypoints count only when close **and** visible. Measure with the probes before tuning or claiming.
- Kotlin `init {}` blocks run in textual order (declare fields above `init { generate() }`).
- `pkill -f pattern` in a Bash call can kill its own shell; use a `[x]yz` pattern.
- Commit in small steps with clear messages. Don't open PRs unless asked.
