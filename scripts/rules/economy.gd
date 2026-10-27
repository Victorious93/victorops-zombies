class_name Economy
extends RefCounted
## Points economy: earn by hitting/killing/repairing, spend at machines, doors and wall-buys.

const HIT := 10
const KILL := 60
const KILL_CRIT := 100
const REPAIR := 10
const KILL_KNIFE := 130
const REPAIR_CAP_PER_ROUND := 500  ## plank points are capped each round (no farming)
const START := 500

var points: int
var mult := 1           ## Double Pay power-up sets 2
var repair_earned := 0  ## plank points this round

func _init(starting_points: int = START) -> void:
	points = starting_points

func earn(n: int) -> void:
	points += n * mult

func on_hit() -> void:
	earn(HIT)

func on_kill(headshot: bool = false, knife: bool = false) -> void:
	earn(KILL_KNIFE if knife else (KILL_CRIT if headshot else KILL))

## Returns the points actually paid (0 once this round's cap is reached).
func on_repair(planks: int = 1, multiplier: int = 1) -> int:
	var want := REPAIR * planks * multiplier
	var paid := clampi(REPAIR_CAP_PER_ROUND - repair_earned, 0, want)
	repair_earned += paid
	earn(paid)
	return paid * mult

func on_round_start() -> void:
	repair_earned = 0

## Deducts only if affordable.
func spend(cost: int) -> bool:
	assert(cost >= 0)
	if cost > points:
		return false
	points -= cost
	return true

func can_afford(cost: int) -> bool:
	return cost <= points
