# Blackout Royale (design)

An additional, self-contained mode: a top-down battle royale, free-for-all or in **squads with revives** (see "Squads" below). Up to **12 fighters** (1-4 humans, bots fill the rest) drop onto a 3200x3200 map. The **Dead Zone** closes in; the horde walks out of it. Last fighter (or squad) standing wins. A match against bots lasts about 3-4 minutes (the zone schedule caps it at 5.4 minutes).

All names, shapes and numbers are original placeholders, like the rest of the game. Zombie Survival is untouched: Royale has its own sim (`core/.../br`), its own weapon table and its own screen.

## Pillars
1. **Every fight is a decision.** Cover, reload timing, heal channels and a per-character ability reward thinking, not just aim.
2. **The map is never idle.** The zone, airdrops and zombies keep pushing fighters together.
3. **Fair and readable.** Bots obey the same rules as humans (same input struct, no cheating). Damage numbers, a kill feed, a minimap and a zone arrow explain what is happening.
4. **Short.** About 3-4 minutes, then instant rematch.

## Flow
`LOBBY` (humans join, host presses USE to start; solo starts at once) -> `DEPLOY` (5 s countdown, frozen, invulnerable) -> `LIVE` -> `ENDED` (placement, kills, tap to rematch).
Joining after the match starts is refused ("full"). Eliminated humans spectate (killer first, then anyone alive).

## Map
- 3200 x 3200, procedural from a seed shared with clients (the seed is in every snapshot, so the layout is never sent).
- 5 points of interest (Foundry, Depot, Market, Harbor, central Plaza), each a cluster of 3 buildings with one doorway each, plus crates. Scattered cover and rocks between.
- Walls stop bodies and bullets. A coarse navigation grid (40 px) lets bots path around walls.

## Fighters
- 160 HP (Martha 175) + up to 100 shield. Shield absorbs damage first. Zone damage ignores shield.
- Speed 230 (Snoop x1.1). Slowed while healing.
- Controls: move, **aim** (mouse / right stick), **fire**, **USE** (swap weapon), **HEAL** (hold), **SKILL**, **RELOAD**.
- **Abilities** (30-35 s): *Bass Drop* (Snoop) knocks back and damages nearby fighters and zombies and interrupts heals. *Fortify* (Martha) gives +35 shield and halves damage for 3 s.

## Weapons (PvP table, separate from zombie balance)
| Gun | Role | Dmg | Rate | Mag | Notes |
|---|---|---|---|---|---|
| Volt Sidearm | start | 11 | 3.6/s | 12 | accurate, weakest gun |
| Buzzsaw SMG | close | 6.5 | 13/s | 32 | wide spread, short range |
| Pulse Rifle | mid | 12 | 7/s | 28 | best all-rounder |
| Scatterbolt | burst | 6.5x8 | 1.1/s | 5 | devastating at point blank |
| Rail Lancer | long | 58 | 0.9/s | 4 | pierces through fighters, fast bullet |
| Nova Disruptor | zone control | 48 + splash | 0.8/s | 3 | slow explosive, no self-damage |

Nominal damage per second sits in a 37-87 band (tested), so no gun is strictly best at every range. A test also checks that no gun can delete a full-health fighter in one trigger pull.

Rarity (Common / Rare / Epic): damage x1 / x1.15 / x1.3, bigger magazine, faster reload; Epic also fires faster.

## Loot
- ~75 items placed at match start. Points of interest roll better rarity and spawn two items per spot.
- Medkit (+50 HP, 2.2 s channel), Shield Cell (+50 shield, 1.6 s channel). Carry 3 of each. Damage, firing or an ability interrupts a channel.
- Weapons are swapped manually with USE; the old gun drops. Eliminated fighters drop their gun and a shield cell.
- **Airdrops** land inside the next safe zone at the start of zone phases 2-4: an Epic weapon, 2 medkits and 2 shield cells. A smoke marker shows from the moment the drop is announced.

## Dead Zone
| Phase | Hold | Shrink | End radius | Damage/s |
|---|---|---|---|---|
| 1 | 40 s | 40 s | 1450 | 1.5 |
| 2 | 35 | 35 | 920 | 3 |
| 3 | 30 | 30 | 540 | 5 |
| 4 | 25 | 25 | 260 | 8 |
| 5 | 20 | 20 | 100 | 12 |
| 6 | 10 | 15 | 0 | 20 |
The opening circle (radius 2270) reaches the map corners.
The next circle is always inside the current one and inside the map. It is shown during the hold so fighters can plan.

## The horde
From phase 2, zombies spawn just outside the zone edge (max 12), chase the nearest fighter and bite for 14/s. They drop heals 20% of the time. They make camping at the edge costly and give bots and humans something to shoot.

## Bots
Same input struct as humans, no extra knowledge. Priorities: leave the zone (and stay out of its margin) -> back off when badly hurt -> fight a visible enemy -> heal when out of sight -> loot -> wait or rotate.

- **Personality:** each bot has an aggression (0.35 cautious .. 1.0 hunter) and its own gun tastes. Cautious bots only fight inside a short range unless shot first, and keep to their landing area until they must rotate; hunters roam and look for fights. This is what makes the opening a loot phase instead of a brawl.
- **Landing areas:** the world gives every bot a distinct area to loot first (hunters prefer towns), so neighbours do not all pick the same building.
- **Rotation:** a bot leaves for the next circle only when the margin is tight (when the edge will reach it versus how long the walk takes), aiming for the nearest point of the circle, so they arrive spread out.
- **Skill:** EASY / NORMAL / HARD set aim error, reaction time, turn rate and sight range.
- **Navigation:** A* over a 20 px grid (visible lanes at least 56 px wide), line-of-sight path smoothing, waypoints only count as reached when close *and* visible, committed steering around walls, stuck detection with a loot blacklist.

Measured on 16 bot-only matches per level (all finish): EASY first kill 54 s / match 213 s, NORMAL 33 s / 202 s, HARD 24 s / 171 s. Tests guard the pacing band, zero stuck bots and a low jitter rate.

## Squads and revives
`BrWorld.squadSize` is 1 (free-for-all, the original rules, unchanged) or 2..4. The host picks it in the lobby (tap the green button, or `T`); the menu remembers the choice (`BrPrefs`, default **3**) and the solo game uses it. Clients learn the mode from the snapshot.

- **Squads.** 12 fighters make 12 / size squads. Humans fill squad 0 first, then spill into squad 1; bots fill the gaps. Squads land together (members within ~70 px of one anchor, anchors chosen farthest-first around the spawn ring), and a squad's bots share one loot neighbourhood (each gets one of the three nearest loot spots to the squad's area; a squad with a human uses the spot nearest the human).
- **No friendly fire.** Bullets (including the Lancer's pierce, which passes through a mate and still hits the enemy behind), explosion splash, Bass Drop (no damage, no knockback) and direct `damage()` calls all skip squad mates. Zombies are unaffected by squads. Mates never push or block each other.
- **Downed.** At zero health a fighter with a teammate who can still move is **downed**, not eliminated: shield is lost, they crawl at 25% speed, cannot fire, heal, reload, use or cast, stay visible and targetable, and **bleed out in 30 s**. Enemy hits, zone damage and horde bites cost 0.25 s of bleed per point of damage (a Pulse Rifle bullet costs ~3 s, zone stage 5 about 3 s per second), so lying in the open under fire is fatal. Bleeding pauses while a mate is reviving them, and a fighter being revived holds still.
- **Revive.** A living, non-downed mate within 60 px who holds **USE** for 4 s revives them to 40% HP, no shield. While reviving you move at half speed and cannot heal; USE does not swap weapons while a mate needs you. Damage to the reviver breaks the channel for 0.8 s (zone damage does not), after which holding USE resumes it. Progress falls at half the build-up rate when nobody is working on it. Only one reviver counts at a time. Touch: the same USE button, which turns green and pulses when a revive prompt is up.
- **Last mobile mate.** A fighter who reaches zero health while no mate can move is eliminated, and so are the squad's downed members (they cannot be revived any more). Eliminated fighters drop their gun and a shield cell as before.
- **Placement and winner.** A squad's placement is the number of squads still in the match when its last member falls; all its members share it. The match ends when one squad is left (everyone in it places 1st) or when no human is left alive (a downed human is alive: their bots can still revive them). Kills stay individual; the result screen shows "Placed #n of N squads" and squad kills. Eliminated humans spectate a living mate first (one who can move before a downed one), then their killer.
- **Bots** ignore mates when scanning, and downed enemies are the last thing they shoot. Every new decision has two thresholds or a cooldown: *revive* starts only when it is safe (nobody in sight; a zombie farther than 200 px; an enemy farther than 350 px who cannot see the mate) and stops when it is clearly dangerous (hit, a zombie within 130 px, an enemy within 300 px, or within 450 px with a line to the mate), then waits 2.5 s; *leash* starts beyond 380 px from the leader (the human, otherwise the first mobile bot) and ends within 220 px, and followers only fetch loot within 330 px of the leader and wander around them. A bot walks to a standable point beside the mate (arrival radius 24 px) and holds USE inside 54 px; the hold range is 60 px. An active revive beats the soft zone states (rotating, "burned") but not standing in a deadly zone. A downed bot crawls to a spot an enemy cannot see (re-chosen at most every 1.5 s and kept for 2 s) or toward a mobile mate.
- **UI (`BrScreen`).** Squad halo under every fighter (mine green, other squads one colour each), teammate names in green, a squad panel under the stat block (name, health and shield, or the bleed-out clock and revive progress), a revive wedge around a downed fighter, a green pulse ring on the reviver, edge arrows to off-screen downed mates, a red downed overlay with the bleed clock, a progress bar for your own revive, and mates on the minimap (orange when downed). Mates are always in the snapshot, whatever the distance.

### Squad measurements
Bot-only matches, NORMAL skill, all finished, 0 stuck bots.

| Squad size | Matches | Avg length | First down / first kill | Downs per match | Revives tried / succeeded | Bleed-outs |
|---|---|---|---|---|---|---|
| 2 (6 squads) | 12 | 209 s | 50 s / 58 s | 6.0 | 2.3 / 0.5 | 3.6 |
| 3 (4 squads) | 12 | 206 s (157-241) | 78 s / 86 s | 7.5 | 4.1 / 1.2 | 4.6 |
| 4 (3 squads) | 12 | 190 s | 82 s / 94 s | 8.0 | 4.8 / 1.2 | 5.1 |

Bleed-outs here are downs that ended with a mate still able to move, i.e. missed revives. Of the downs where a revive was possible, roughly one in five is saved; the rest happen next to the fight that caused them, where a bot correctly refuses to stand still for 4 s. Free-for-all is unchanged to the digit (avg 210 s, first kill 32 s, jitter 122 of 43,428 bot-seconds). Squad jitter (12+ reversals in one second) is 0.27% of bot-seconds (limit 0.5%). The biggest snapshot in a squad match is 465 bytes (free-for-all 470 after the codec grew by 5 bytes per fighter and a few per snapshot).

## Networking
Host-authoritative, reusing `HostSession`/`ClientSession` through the `Sim` interface. Clients send the extended `PlayerInput` (aim, fire, heal, reload); the host streams ~15 Hz snapshots filtered to what is near each viewer (fog of war), including damage numbers and the kill feed.

## Verification status
- Simulation, bots, codec and networking: covered by 143 automated tests (reachability of every loot spot over 60 seeds, bot-match invariants, pacing band, stuck/jitter limits, session layer over loopback; for squads: friendly fire by bullet, splash and ability, down vs eliminated, bleed-out, revive success, interruption, range and last-mate elimination, squad placement and winner, the all-humans-dead rule, codec round trip and fuzz, a client joining a squad lobby, and squad versions of the finish, stuck, jitter and pacing bot-match tests).
- Rendering: the desktop build was run under a virtual display with software GL and frames were inspected: menu, lobby, deploy, early, mid and late match, and for squads the menu toggle, lobby option, revive progress, revive prompt, downed overlay, off-screen arrow, enemy squad rings and the result screen, at 1280x720 and at a phone-like 1170x540 with the touch HUD (`-Dzombie.touch=1`). **Not verified:** touch input on a device (a desktop render cannot press the on-screen buttons), whether hold-to-revive feels right under a thumb, frame time on a phone, real two-device Wi-Fi play, and Bluetooth.

## Out of scope for v1 (ideas)
Vehicles, a lobby with map voting, sound, real art, respawn beacons, pings, cross-squad alliances.
