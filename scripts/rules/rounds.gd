class_name Rounds
## Pure round-scaling rules, ported 1:1 from the libGDX Rounds.kt (original tuning).
## Distances: the 2D game used ~60 world units per metre, so speeds are converted with UNITS_PER_METRE.

const MAX_ALIVE := 24
const UNITS_PER_METRE := 60.0
const SPECIAL_EVERY := 5

## Total zombies spawned in a round (round starts at 1). Frenzy rounds spawn 75%.
static func zombie_count(round: int) -> int:
	assert(round >= 1)
	var n: int = mini(6 + (round - 1) * 3 + (round - 1) * (round - 1) / 4, 120)
	if is_special(round):
		n = int(n * 0.75)
	return n

const INTERMISSION := 10.0

## Hit points of each zombie: 150 on round 1, +100 per round to round 9, then x1.1 per round.
static func zombie_health(round: int) -> int:
	assert(round >= 1)
	if round <= 9:
		return 150 + (round - 1) * 100
	var hp := 950.0
	for i in range(round - 9):
		hp *= 1.1
	return int(hp)

## Share of a round's zombies that run: everyone shambles until round 4, then runners phase in.
static func runner_chance(round: int) -> float:
	if round < 5: return 0.0
	return clampf(0.35 + (round - 5) * 0.25, 0.0, 1.0)

const WALK_SPEED := 1.05   ## m/s shamble
const RUN_SPEED := 3.6     ## m/s sprint (player walks 4.2, sprints 6.3)

## Speed in the original 2D units/s, capped.
static func zombie_speed_units(round: int) -> float:
	return minf(60.0 + round * 6.0, 150.0)

## Speed in metres/s for the 3D game (frenzy rounds run 40% faster).
static func zombie_speed(round: int) -> float:
	var s := zombie_speed_units(round) / UNITS_PER_METRE * 1.1
	if is_special(round):
		s *= 1.4
	return s

## Seconds between spawns, getting faster but floored.
static func spawn_interval(round: int) -> float:
	return maxf(2.0 - round * 0.1, 0.4)

## Every 5th round is a "Frenzy" special round: fewer but faster zombies.
static func is_special(round: int) -> bool:
	return round >= SPECIAL_EVERY and round % SPECIAL_EVERY == 0
