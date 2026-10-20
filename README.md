# VictorOps Zombies

![VictorOps Zombies logo](assets/victorops-zombies-logo.jpg)

An **original** top-down, round-based wave-survival zombie shooter for Android.
Hold the line across ever-harder rounds, board up the windows, spend your points
at the Mystery Crate, the Iron Hide Tonic perk machine and the Overcharge Forge.

## Concept (v0 slice)
- **Rounds** – zombie count, health and speed scale each round (`core/.../logic/Rounds.kt`).
- **Points** – +10 per hit, +60 per kill, +10 per barricade plank repaired; start with 500.
- **Barricades** – four windows with 6 planks each; zombies must tear them down to get in.
- **Mystery Crate** (950 pts) – weighted random weapon (Scatterbolt, Buzzsaw SMG, Pulse Rifle, Rail Lancer, Nova Disruptor).
- **Perk machine** – *Iron Hide Tonic* (2500 pts) doubles max health.
- **Upgrade machine** – *Overcharge Forge* (5000 pts) doubles weapon damage, faster fire.
- **Controls** – Android: virtual joystick (left half), USE button (right). Desktop: WASD + E. Aiming/firing is automatic at the nearest zombie.
- Graphics are procedural placeholder shapes for now.

## Why libGDX + Kotlin
- Full control over Gradle/Android config: ABIs (arm64-v8a, armeabi-v7a), APK signing schemes, target SDK.
- Small APK (~3.6 MB debug), no heavy engine runtime.
- Code-first, diff-friendly, CI-friendly – no binary scene files.
- Excellent fit for 2D top-down games; desktop (LWJGL3) module for fast iteration.

## Project layout
| Module | Purpose |
|---|---|
| `core` | Game code + pure-logic rules with unit tests |
| `android` | Android launcher, `applicationId com.victorious.zombie`, minSdk 24, target/compile SDK 35 |
| `lwjgl3` | Desktop launcher for testing |
| `assets` | Shared assets (logo) |

## Build
Requires JDK 17 and the Android SDK (`ANDROID_HOME` or `local.properties` with `sdk.dir`).
```bash
./gradlew test                 # pure-logic unit tests
./gradlew :android:assembleDebug   # APK at android/build/outputs/apk/debug/
./gradlew :lwjgl3:run          # play on desktop
```
Debug builds are signed with a key supplied via env vars `VOZ_KEYSTORE_PATH`, `VOZ_KEYSTORE_PASSWORD`,
`VOZ_KEY_ALIAS`, `VOZ_KEY_PASSWORD` (or the same keys in git-ignored `keystore.properties`/`local.properties`).
If unset, the standard Android default debug key is used. No keystore is committed.
Keystores and signing secrets are never committed (see `.gitignore`).

CI (`.github/workflows/android.yml`) runs tests, builds the debug APK, verifies v2/v3 signatures
and both ABIs with `apksigner`, and uploads the APK as an artifact.

## Roadmap
- **v1 – single-player**: real art & audio, multiple maps/rooms with buyable doors, more perks, specials, save high scores, settings, controller support.
- **Later milestone – co-op multiplayer (scoped, not built)**: local split/shared-screen co-op, then online co-op (host-authoritative netcode, lobby, revive mechanic).

## Originality / IP statement
VictorOps Zombies is an original work. All names, code, rules and (placeholder) graphics are
created for this project. It is inspired only by the general genre of round-based survival
modes and uses **no** names, assets, audio, maps or code from Activision, Call of Duty, or any
other third-party franchise.
