class_name LastStand
extends RefCounted
## Solo downed state: you drop to the floor with your sidearm. Without Lazarus Fizz the bleed-out
## timer ends the game; with it you get back up after SELF_REVIVE seconds and lose your perks.

const BLEED_OUT := 10.0
const SELF_REVIVE := 6.0
const REVIVE_HEALTH_FRAC := 1.0

var active := false
var left := 0.0
var will_revive := false

func start(has_self_revive: bool) -> void:
	active = true; will_revive = has_self_revive
	left = SELF_REVIVE if has_self_revive else BLEED_OUT

## Returns "", "revive" or "dead" when the timer ends.
func update(dt: float) -> String:
	if not active: return ""
	left -= dt
	if left > 0.0: return ""
	active = false
	return "revive" if will_revive else "dead"
