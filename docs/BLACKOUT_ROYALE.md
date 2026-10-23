# Blackout Royale (design)

An additional, self-contained mode: a top-down free-for-all battle royale. Up to **12 fighters** (1-4 humans, bots fill the rest) drop onto a 3200x3200 map. The **Dead Zone** closes in; the horde walks out of it. Last fighter standing wins. A match against bots lasts about 3-4 minutes (the zone schedule caps it at 5.4 minutes).

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

## Networking
Host-authoritative, reusing `HostSession`/`ClientSession` through the `Sim` interface. Clients send the extended `PlayerInput` (aim, fire, heal, reload); the host streams ~15 Hz snapshots filtered to what is near each viewer (fog of war), including damage numbers and the kill feed.

## Verification status
- Simulation, bots, codec and networking: covered by 118 automated tests (reachability of every loot spot over 60 seeds, bot-match invariants, pacing band, stuck/jitter limits, session layer over loopback).
- Rendering: the desktop build was run under a virtual display with software GL and frames were inspected (menu, lobby, deploy, early, mid and late match). **Not yet verified:** touch controls and the Android build (no SDK or device here), real two-device Wi-Fi play, and Bluetooth.

## Out of scope for v1 (ideas)
Squads with revives, vehicles, a lobby with map voting, sound, real art.
