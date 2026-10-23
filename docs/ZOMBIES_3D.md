# Zombies 3D (design and status)

The default game since this change: a **first-person, round-based zombie survival** mode in the spirit of the classic
"survive the rounds" zombie co-op genre. Everything is original: names, map, models (boxes built in code), and sound (synthesised
in code). Nothing is taken from Call of Duty or any other game. **Solo and offline only** for now.

Code: `core/.../fps/` (headless sim: `FpsMap`, `FpsWorld`, `FpsGuns`; rendering helpers `FpsArt`, `FpsSounds`) and `FpsScreen.kt`.
Tests: `core/src/test/.../fps/FpsTest.kt`.

## The loop
- **Rounds.** Zombie health 150 at round 1, +100 per round to round 9, then +10% per round. Count 6, 8, 13, 18, 24, then +4 per round
  (cap 90). At most 24 alive. Walkers at first; joggers from round 2, runners from round 5. 10 s break between rounds.
- **Windows.** Zombies spawn outside the boarded windows of rooms you have opened (the closest ones to you), tear off the 6 boards one at
  a time, climb in and chase you over a flow field. Hold USE at a window to rebuild it (+10 points a board, up to 500 a round). A zombie
  at a broken window can swipe you through it.
- **Points.** Start with 500. +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Guns.** P9 Sidearm (start), wall buys Ranger M1 (500), Trench 12 shotgun (500), Kestrel SMG (1000), Harrow AR (1200); buying again
  refills ammo for half price. Two guns at a time. Mystery Box (950): rolls a random box gun you do not hold (Vulcan LMG, Sabre .50,
  Thunder Ray and the wall guns), take it within 10 s.
- **Doors.** Start room -> hall 750, start room -> workshop 1000, hall -> power room 1250.
- **Power.** The switch is in the power room, behind two doors. It turns on the perk machines and the forge.
- **Perks.** Ironhide 2500 (250 health instead of 100), Quickhand 3000 (reload twice as fast), Rapidfire 2000 (fire 33% faster), Second
  Wind 500 (no power needed; when you go down you get back up after 4 s, up to 3 buys).
- **Forge** (5000, needs power): doubles the current gun's damage (the Thunder Ray x1.5), bigger magazine and reserve; 2500 refills a
  forged gun.
- **Power-ups** (3% per kill, up to 4 a round, 25 s on the floor): Max Ammo, Insta-Kill (30 s), Double Points (30 s), Nuke (+400),
  Carpenter (all boards back, +200).
- **Health.** Zombie hits do 50. Health regenerates after 3.5 s without damage. At 0 you go down: Second Wind or game over.
- **Knife.** 150 damage, 1.7 m, in a cone in front of you; kills round 1-2 zombies in one hit.

## Map: Station 9
A bunker on a 24 x 18 grid of 2 m tiles (`FpsMap.STATION`): start room (2 windows, Ranger and Trench on the walls, Second Wind, the
forge), hall (3 windows, Kestrel, Quickhand, mystery box), workshop (3 windows, Harrow, Rapidfire), power room (2 windows, Ironhide, the
switch). Tests check that every floor tile is reachable once doors open, that windows open onto floor with spawn room outside, and
that props face floor.

## Controls
- **Touch:** left 45% of the screen is a floating move stick; drag anywhere else on the right to look; FIRE (bottom right, drag it to
  aim while firing), USE (pulses green when something can be bought or used), R (reload), KNIFE, and tap the ammo readout (top right)
  to swap guns. Light aim assist while firing (eases toward a visible zombie within ~4 degrees).
- **Desktop:** WASD, mouse look (click to capture), left click fire, E use, R reload, V/F knife, Q/1/2 swap, Esc release mouse / menu.

## Rendering
libGDX `ModelBatch` with the default shader: per-vertex lighting from ambient, one dim directional "moon" and 6 point lights (a torch
above and behind the player plus the nearest ceiling bulbs, window lights, the box beam or the powered forge), fog to 30 m. Level
geometry is three static meshes (floor+ceiling, outside ground, walls with window holes and door lintels); zombies are box figures with
animated legs and arms, glowing eyes, hit flashes, death falls and headshot decapitation. The held gun is drawn after clearing depth,
with its own steady lighting, recoil, reload dip, swap and knife animations and a muzzle flash.

## Measured
- 20 sim tests, including: zombies reach a standing player through the windows within 120 s on every seed tried, never end up inside
  walls, and are never stuck (no inside zombie still for 8 s without attacking); one pistol headshot kills on round 1; walls stop bullets;
  purchases, box, perks, power, forge, power-ups, Second Wind and game over.
- A crude scripted player (stands in the start room, shoots the nearest visible zombie, rebuilds windows, buys the Ranger) reaches
  **round 5 in all 6 seeds** (51-56 kills), then dies: early rounds are survivable and the ramp bites. A human with doors, perks and the
  box should go further; that is not measured.
- Frames rendered under Xvfb with software GL at 1280x720 and 1170x540 (touch HUD) were inspected: windows with zombies tearing
  boards, a zombie closing in, a wall buy, the box rolling, the power room, the forge, game over and the menu.

## Not verified
- **Anything on a phone:** frame rate, touch feel (look sensitivity, stick size, button reach), heat, audio playback. The renderer was
  only seen through software GL on a desktop. The draw-call count (roughly 15 parts per zombie, up to 24 zombies, plus the level and
  props) is untested on low-end devices.
- Sound: the effects are generated and loaded, but the container has no audio device, so nobody has heard them.
- Balance beyond the scripted player.

## Not built yet (ideas)
Wi-Fi co-op in 3D, aim-down-sights, sprint, grenades, more maps, real models and textures, music, a pause menu, settings
(sensitivity, invert), the box moving after some uses.
