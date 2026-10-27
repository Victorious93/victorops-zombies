class_name MysteryCrate
extends RefCounted
## Mystery Crate: weighted random weapon for a point cost (same table as the libGDX MysteryBox).

const COST := 950
const DEFAULT_TABLE := [["scatter", 30], ["smg", 30], ["rifle", 25], ["cannon", 10], ["nova", 5]]

var cost: int = COST
var table: Array = DEFAULT_TABLE

func total_weight() -> int:
	var t := 0
	for e in table: t += e[1]
	return t

func probability_of(weapon_id: String) -> float:
	var w := 0
	for e in table:
		if e[0] == weapon_id: w += e[1]
	return float(w) / total_weight()

## Never returns [exclude] unless it is the only entry.
func roll(rng: RandomNumberGenerator, exclude: String = "") -> String:
	var pool := table.filter(func(e): return e[0] != exclude)
	if pool.is_empty(): pool = table
	var sum := 0
	for e in pool: sum += e[1]
	var r := rng.randi_range(0, sum - 1)
	for e in pool:
		if r < e[1]: return e[0]
		r -= e[1]
	return pool[-1][0]

## Spend and roll; "" if unaffordable.
func buy(economy: Economy, rng: RandomNumberGenerator, current: String = "") -> String:
	if not economy.spend(cost): return ""
	return roll(rng, current)
