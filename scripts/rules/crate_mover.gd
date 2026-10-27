class_name CrateMover
extends RefCounted
## The Mystery Crate relocates: after a random 4-7 rolls it overloads and jumps to another spot.

const MIN_USES := 4
const MAX_USES := 7
var spots: Array = []
var current := 0
var uses_left := 0

func _init(p_spots: Array = [], rng: RandomNumberGenerator = null) -> void:
	spots = p_spots
	_reset(rng)

func _reset(rng: RandomNumberGenerator) -> void:
	uses_left = rng.randi_range(MIN_USES, MAX_USES) if rng else MAX_USES

## Call once per paid roll. True means the crate should move after this roll.
func on_roll(rng: RandomNumberGenerator) -> bool:
	uses_left -= 1
	return uses_left <= 0 and spots.size() > 1

## Picks a different spot and re-arms the counter. Returns the new index.
func relocate(rng: RandomNumberGenerator) -> int:
	if spots.size() > 1:
		var n := rng.randi_range(0, spots.size() - 2)
		current = n if n < current else n + 1
	_reset(rng)
	return current
