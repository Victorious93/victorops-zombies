class_name Economy
extends RefCounted
## Points economy: earn by hitting/killing/repairing, spend at machines, doors and wall-buys.

const HIT := 10
const KILL := 60
const KILL_CRIT := 100
const REPAIR := 10
const START := 500

var points: int

func _init(starting_points: int = START) -> void:
	points = starting_points

func on_hit() -> void:
	points += HIT

func on_kill(headshot: bool = false) -> void:
	points += KILL_CRIT if headshot else KILL

func on_repair(planks: int = 1, multiplier: int = 1) -> void:
	points += REPAIR * planks * multiplier

## Deducts only if affordable.
func spend(cost: int) -> bool:
	assert(cost >= 0)
	if cost > points:
		return false
	points -= cost
	return true

func can_afford(cost: int) -> bool:
	return cost <= points
