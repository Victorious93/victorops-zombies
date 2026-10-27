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

## Hit points of each zombie: linear to round 9, then +10% per round.
static func zombie_health(round: int) -> int:
	assert(round >= 1)
	if round <= 9:
		return 100 + (round - 1) * 50
	var hp := 500.0
	for i in range(round - 9):
		hp *= 1.1
	return int(hp)

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
