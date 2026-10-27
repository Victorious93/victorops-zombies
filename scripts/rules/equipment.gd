class_name Equipment
extends RefCounted
## Knife and grenades (pure rules).

const KNIFE_DAMAGE := 150
const KNIFE_RANGE_M := 1.9
const KNIFE_COOLDOWN := 0.65
const GRENADE_START := 2
const GRENADE_MAX := 4
const GRENADE_PER_ROUND := 2
const GRENADE_FUSE := 2.2
const GRENADE_RADIUS_M := 4.5

var grenades := GRENADE_START

static func grenade_damage(round: int) -> int:
	return 200 + 60 * maxi(round, 1)

## Damage falls off linearly from full at the centre to 25% at the edge; 0 outside.
static func grenade_falloff(dist_m: float) -> float:
	if dist_m > GRENADE_RADIUS_M: return 0.0
	return lerpf(1.0, 0.25, dist_m / GRENADE_RADIUS_M)

func throw_one() -> bool:
	if grenades <= 0: return false
	grenades -= 1
	return true

func on_round_start() -> void:
	grenades = mini(GRENADE_MAX, grenades + GRENADE_PER_ROUND)
