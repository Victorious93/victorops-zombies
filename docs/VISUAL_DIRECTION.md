# Visual direction: gritty, Call of Duty Zombies-like (original art)

Status: **pass 1 done for Zombie Survival** (see "Done" and "Next" below). The goal is the *feel* of that genre in a top-down 2D phone game: dark, grimy,
tense, readable. Everything is drawn procedurally. We do **not** copy Activision's art, names, logos, fonts, sounds or maps, and
we do not use their trademarks; the repo is original and GPL-licensed. Genre conventions (tally-mark round counters, boarded
windows, perk machines, a mystery box, "buy for N" prompts) are fine; exact assets and branding are not.

## Look
- **Palette:** desaturated, muddy concrete and brick; near-black shadows; blood red and sickly green as the only strong colours;
  warm yellow for muzzle light and the player's torch; each perk machine gets one saturated neon colour so it reads from far away.
- **Light:** the world is dark. A soft vignette darkens the screen edges, a warm halo lights the area around the player, muzzle flashes
  briefly light the surroundings, machines glow. Nothing beyond the lit area is fully black (the player must still read the arena).
- **Grime:** persistent blood splats where zombies die (capped and fading slowly), bullet sparks and impact flecks, scuffed floor with
  subtle tiling noise, darker edges on walls with a lighter top edge for depth.
- **Characters:** zombies are ragged shapes with a darker rim, two dim glowing eyes that face the target and arms reaching forward,
  slightly different sizes and hues so a horde does not look cloned. Survivors are a top-down soldier: shoulders, head, a gun.
- **Barricades:** nailed wooden boards that visibly break one plank at a time; torn boards lie on the floor.
- **Machines:** perk cabinet with a coloured glow, mystery crate with a vertical beam of light, the upgrade forge with a pulsing
  magenta core.

## HUD (phone first)
- **Round counter:** bottom-left white tally marks in groups of five with a diagonal strike; the current round number appears in large
  blood red at round change and fades to the tally.
- **Points:** left side list with floating "+10", "+60" popups that rise and fade.
- **Weapon and ammo:** bottom-right, large numerals (`mag / reserve`), gun name small and above.
- **Health:** no bar. Red vignette that pulses on hit and stays when low, with a faint desaturating darkness at low health. Armor is a
  thin blue arc or bar.
- **Prompts:** centre-bottom, white text with a dark outline: "Hold USE to buy Mystery Crate [950]".
- **Round banner:** large "Round N" in red that fades in and out, with a short "survived" line between rounds.
- Type must be readable on a 6-inch phone (see `ui` scale in `BrScreen`), with a dark outline or shadow for contrast.

## Performance budget (phone)
One full-screen vignette quad, at most ~150 blood decals (merge or fade the oldest), no per-frame allocations in the draw path, no
shader requirement. Measure frame cost on desktop with software GL as a rough upper bound only; real devices are unverified.

## Rollout
1. Zombie Survival (`GameScreen.kt`) with a shared `Look.kt` helper (vignette, glow, blood decals, tally counter, outlined text).
2. Re-skin Blackout Royale (`BrScreen.kt`) with the same helper, after the squads work lands.
3. Menus and character select.

## Done (pass 1: Zombie Survival, `GameScreen.kt` + `Look.kt`)
- `Look.kt` generates every texture at start-up (no image files): cracked concrete floor, soft light, vignette, blood splats, three
  zombie sprites and a survivor sprite. All are power-of-two sizes on purpose: OpenGL ES 2.0, the Android default, cannot mipmap or
  repeat non-power-of-two textures, and a 96 px splat texture would have rendered wrong on devices while looking fine on desktop.
- Brick walls, nailed boards that disappear plank by plank with torn boards left on the floor, steel lockers, a crate with a beam of
  light, a green perk cabinet, a pulsing magenta forge.
- Ambient darkness with additive lights over it (survivor torch, machine glows, muzzle flashes, bullets, cold window light),
  edge vignette, red vignette when hurt that stays and pulses at low health.
- Blood decals where zombies die (capped at 140, fading), points popups that merge, tally-mark round counter (newest mark in red),
  big ammo numerals, "ROUND N" banner in blood red with a dark outline, outlined text everywhere.
- Phone: text scale 1.6 on touch devices, translucent touch controls (blending is re-enabled before every shape pass).

Measured/verified: rendered frames at 1280x720 and a 20:9 phone-like 1170x540 window under Xvfb with software GL, touch HUD forced with `-Dzombie.touch=1`.
**Not verified:** any real device (performance, brightness outdoors, GLES2 behaviour), touch input, sound.

## Next
1. Re-skin `BrScreen` (Royale) with `Look` once the squads work has landed: same floor/grime/vignette, lit survivors, outlined text.
2. Brightness: a dark look can be unreadable under sunlight on a phone. Add a brightness setting (ambient darkness and vignette strength).
3. Floating left stick (appears where the thumb lands). The fixed stick currently sits on top of the Mystery Crate on phones.
4. Use the full width of 20:9 phones (`ExtendViewport`) instead of letterboxing 16:9 with black bars; anchor the HUD to the real screen edges.
5. Zombie variety (crawlers, heavier brutes), hit sparks and impact flecks, bullet tracers with direction, screen shake on Bass Drop.
6. Menus and character select in the same style; a real display font (an OFL-licensed font bundled with the app, not a game's font).
7. Per-device frame-cost check; reduce overdraw if needed (merge decals, skip lights outside the screen).
