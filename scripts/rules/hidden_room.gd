class_name HiddenRoom
extends RefCounted
## v7.12 Sealed Annex: a cracked wall in the generator room's north wall hides a small vault room.
## Shoot it, blast it or knife it to break through.

const NAME := "Sealed Annex"
const CRACK_HP := 900.0
const MELEE_DAMAGE := 300.0
const CRACK_POS := Vector3(-8.2, 1.5, -26.0)
const CRACK_W := 2.0
const VAULT_POS := Vector3(-9.6, 0, -30.0)
const RIFT_POS := Vector3(-2.4, 0, -30.0)
const PEDESTAL_POS := Vector3(-6.0, 0, -32.2)
const ROOM_MIN := Vector2(-10.0, -33.0)   ## x, z
const ROOM_MAX := Vector2(-2.0, -26.0)

var hp := CRACK_HP
var revealed := false

## Returns true exactly once: on the hit that breaks the wall.
func hit(dmg: float) -> bool:
	if revealed or dmg <= 0.0: return false
	hp = maxf(0.0, hp - dmg)
	if hp <= 0.0:
		revealed = true
		return true
	return false

func damage01() -> float: return 1.0 - hp / CRACK_HP

static func inside(p: Vector3) -> bool:
	return p.x > ROOM_MIN.x and p.x < ROOM_MAX.x and p.z > ROOM_MIN.y and p.z < ROOM_MAX.y
