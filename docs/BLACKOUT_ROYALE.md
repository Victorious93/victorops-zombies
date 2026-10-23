# Blackout Royale (design)

An additional, self-contained mode: a top-down free-for-all battle royale. Up to **12 fighters** (1-4 humans, bots fill the rest) drop onto a 2400x2400 map. The **Dead Zone** closes in; the horde walks out of it. Last fighter standing wins. A match lasts about 5-6 minutes.

All names, shapes and numbers are original placeholders, like the rest of the game. Zombie Survival is untouched: Royale has its own sim (`core/.../br`), its own weapon table and its own screen.

## Pillars
1. **Every fight is a decision.** Cover, reload timing, heal channels and a per-character ability reward thinking, not just aim.
2. **The map is never idle.** The zone, airdrops and zombies keep pushing fighters together.
3. **Fair and readable.** Bots obey the same rules as humans (same input struct, no cheating). Damage numbers, a kill feed, a minimap and a zone arrow explain what is happening.
4. **Short.** About 5.5 minutes, then instant rematch.

## Flow
`LOBBY` (humans join, host presses USE to start; solo starts at once) -> `DEPLOY` (5 s countdown, frozen, invulnerable) -> `LIVE` -> `ENDED` (placement, kills, tap to rematch).
Joining after the match starts is refused ("full"). Eliminated humans spectate (killer first, then anyone alive).

## Map
- Procedural from a seed shared with clients (the seed is in every snapshot, so the layout is never sent).
- 5 points of interest (Foundry, Depot, Market, Harbor, central Plaza), each a cluster of 3 buildings with one doorway each, plus crates. Scattered cover and rocks between.
- Walls stop bodies and bullets. A coarse navigation grid (40 px) lets bots path around walls.

## Fighters
- 100 HP (Martha 115) + up to 100 shield. Shield absorbs damage first. Zone damage ignores shield.
- Speed 230 (Snoop x1.1). Slowed while healing.
- Controls: move, **aim** (mouse / right stick), **fire**, **USE** (swap weapon), **HEAL** (hold), **SKILL**, **RELOAD**.
- **Abilities** (30-35 s): *Bass Drop* (Snoop) knocks back and damages nearby fighters and zombies and interrupts heals. *Fortify* (Martha) gives +35 shield and halves damage for 3 s.

## Weapons (PvP table, separate from zombie balance)
| Gun | Role | Dmg | Rate | Mag | Notes |
|---|---|---|---|---|---|
| Volt Sidearm | start | 14 | 3.3/s | 12 | accurate, short range |
| Buzzsaw SMG | close | 8 | 13/s | 32 | wide spread |
| Pulse Rifle | mid | 17 | 7/s | 28 | best all-rounder |
| Scatterbolt | burst | 7x8 | 1.2/s | 5 | devastating at point blank |
| Rail Lancer | long | 70 | 1/s | 4 | pierces through fighters, fast bullet |
| Nova Disruptor | zone control | 55 + splash | 0.8/s | 3 | slow explosive, no self-damage |

Rarity (Common / Rare / Epic): damage x1 / x1.15 / x1.3, bigger magazine, faster reload; Epic also fires faster.

## Loot
- ~75 items placed at match start. Points of interest roll better rarity and spawn two items per spot.
- Medkit (+50 HP, 2.2 s channel), Shield Cell (+50 shield, 1.6 s channel). Carry 3 of each. Damage, firing or an ability interrupts a channel.
- Weapons are swapped manually with USE; the old gun drops. Eliminated fighters drop their gun and a shield cell.
- **Airdrops** land inside the next safe zone at the start of zone phases 2-4: an Epic weapon, 2 medkits and 2 shield cells. A smoke marker shows from the moment the drop is announced.

## Dead Zone
| Phase | Hold | Shrink | End radius | Damage/s |
|---|---|---|---|---|
| 1 | 40 s | 40 s | 1100 | 1.5 |
| 2 | 35 | 35 | 700 | 3 |
| 3 | 30 | 30 | 400 | 5 |
| 4 | 25 | 25 | 200 | 8 |
| 5 | 20 | 20 | 80 | 12 |
| 6 | 10 | 15 | 0 | 20 |
The next circle is always inside the current one and inside the map. It is shown during the hold so fighters can plan.

## The horde
From phase 2, zombies spawn just outside the zone edge (max 12), chase the nearest fighter and bite for 14/s. They drop heals 20% of the time. They make camping at the edge costly and give bots and humans something to shoot.

## Bots
Same input struct as humans. Priorities: leave the zone -> fight a visible enemy (strafe, burst fire, aim error and reaction delay from a skill setting) -> heal when safe -> loot (better gun, missing heals) -> advance with the zone. A* over the nav grid with line-of-sight smoothing, stuck detection and separation steering.

## Networking
Host-authoritative, reusing `HostSession`/`ClientSession` through the `Sim` interface. Clients send the extended `PlayerInput` (aim, fire, heal, reload); the host streams ~15 Hz snapshots filtered to what is near each viewer (fog of war), including damage numbers and the kill feed.

## Out of scope for v1 (ideas)
Squads with revives, vehicles, a lobby with map voting, sound, real art.
