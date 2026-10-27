class_name Resonance
extends RefCounted
## Original easter egg, "The Blackwater Signal": three hidden resonance fuses must be shot
## (any order) after the power is on. Completing it pays out and overcharges your gun for free.

const FUSES := ["catwalk", "yard", "cold"]
const REWARD_POINTS := 2500
var hit := {}
var done := false

## Returns "" (ignored), "progress" or "complete".
func shoot(fuse_id: String, power_on: bool) -> String:
	if done or not power_on or not FUSES.has(fuse_id) or hit.has(fuse_id): return ""
	hit[fuse_id] = true
	if hit.size() == FUSES.size():
		done = true
		return "complete"
	return "progress"

func found() -> int: return hit.size()
