# Dev tooling (not part of the build)

Everything here is a recipe, not code the Gradle build compiles. Files ending in `.txt` are Kotlin sources to copy into a
source set **temporarily** and delete again before committing.

## Building the Android APK in this container (this is the product)
A fresh container has no Android SDK and only JDK 21. Outbound access to `dl.google.com` and Google Maven works. One-time setup (about 3 min):

    apt-get update -q && apt-get install -y -q openjdk-17-jdk-headless          # the build pins a JDK 17 toolchain
    mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk
    curl -sS -o /tmp/cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
    unzip -q /tmp/cmdtools.zip -d cmdline-tools && mv cmdline-tools/cmdline-tools cmdline-tools/latest
    export ANDROID_HOME=~/android-sdk
    yes | cmdline-tools/latest/bin/sdkmanager --licenses
    cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

Then, from the repo root (the system `gradle` works; with JDK 17 installed the toolchain override below is not needed):

    export ANDROID_HOME=~/android-sdk
    gradle :android:assembleDebug --console=plain
    # APK: android/build/outputs/apk/debug/android-debug.apk

The APK is signed with the default debug key unless `VOZ_KEYSTORE_*` secrets are set (see `android/build.gradle.kts`). CI additionally
verifies v2/v3 signatures and the arm64-v8a / armeabi-v7a native libraries; the same checks can be run with
`$ANDROID_HOME/build-tools/35.0.0/apksigner verify --verbose` and `unzip -l`. There is no emulator or device here, so touch
input and performance on a phone remain unverified until someone installs the APK.

## Build and test in this container
If you did not install JDK 17 (see above) the build cannot find its pinned toolchain; override it from outside the repo instead:

    gradle :core:test --console=plain -I tools/dev/jdk-override.init.gradle

Add `-I tools/dev/test-output.init.gradle` to see `println` output and pass/fail lines (it also caps the test heap at 96 MB,
which is what made the old unbounded-line bug visible). The wrapper's Gradle is not needed; the system `gradle` works.
`:lwjgl3:compileKotlin` compiles the desktop harness.

Summarise results from the XML (`core/build/test-results/test/*.xml`) rather than scrolling Gradle output.

## Balance and bot probes
Copy `BrProbe.kt.txt` to `core/src/test/kotlin/com/victorious/zombie/br/BrProbe.kt` and run:

    gradle :core:test --tests 'com.victorious.zombie.br.BrProbe' --console=plain \
        -I tools/dev/jdk-override.init.gradle -I tools/dev/test-output.init.gradle

It plays bot-only matches per skill level and prints average match time, first kill, deaths by cause, and a list of bots that
"want to move but have not for 15 s" (with `brainDebug` text). `MapProbe.kt.txt` shows the pattern for one-off investigations
(trace one bot tick by tick, dump walls near it). **Delete probes before committing**; real checks belong in `BrTest.kt`.

## Looking at real frames (Xvfb + software GL)
Works in this container. Steps:

1. Copy `ShotLauncher.kt.txt` to `lwjgl3/src/main/kotlin/com/victorious/zombie/desktop/ShotLauncher.kt`. Edit its scenarios.
2. `gradle :lwjgl3:classes :lwjgl3:printCp -q -I tools/dev/jdk-override.init.gradle -I tools/dev/print-classpath.init.gradle`
   and keep the `CPLINE=` value as the classpath.
3. Run:

        export LIBGL_ALWAYS_SOFTWARE=1 MESA_GL_VERSION_OVERRIDE=3.3 MESA_GLSL_VERSION_OVERRIDE=330
        xvfb-run -a -s "-screen 0 1280x720x24" java -cp "<classpath>" com.victorious.zombie.desktop.ShotLauncherKt <outdir>

4. Open the PNGs with the Read tool. Delete the launcher afterwards.

The launcher pre-advances a `BrWorld` by N ticks, protects the human, and parks the camera near the busiest bots. It forces
the PNG alpha to 255: the framebuffer keeps alpha from translucent HUD panels, so an unmodified capture shows them as light
grey when they are really dark. Measure pixels with `convert shot.png -format "%[pixel:p{x,y}]" info:` before calling a
rendering bug. Touch controls cannot be exercised this way (`Gdx.app.type` is Desktop).

## Pitfalls that already cost time
- `pkill -f "<pattern>"` inside a Bash call matches the shell running it and kills it. Use `pgrep`/`ps` with a `[x]yz` pattern.
- Kotlin `init {}` blocks run in textual order: in `BrMap` `init { generate() }` must sit **below** the grid fields.
- A bot goal that flips between two branches on a knife-edge boundary makes the bot dance in place. Every boundary the AI
  uses needs hysteresis (see `advancing`, `burned`, `EDGE_MARGIN` and the ETA rule in `BrBots.kt`). Check reversals in **both**
  axes, not only `dx`.
- Arrival radii must be smaller than pickup radii, and loot hugging a wall must be approached via a *standable* point
  (`map.nearestFree`), because line-of-sight tests inflate walls by the body radius.
- Waypoints count as reached only when close **and** visible.
- A match with a single fighter ends immediately (`checkEnd`). Tests that use one human add an invulnerable parked dummy
  (see `liveWorld` in `BrTest.kt`).
- Measure before tuning: kill logs (killer, weapon, range, distance to zone edge) and per-5-second spread logs explained
  pacing far better than guessing at constants.
