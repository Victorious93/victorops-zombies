class_name ArmorState
extends RefCounted
## Armor soaks damage before health, caps at 200, persists between rounds.

const PACKS := {
	"light": {"name": "Light Plating", "cost": 500, "armor": 50},
	"medium": {"name": "Reinforced Vest", "cost": 1000, "armor": 100},
	"heavy": {"name": "Bulwark Suit", "cost": 1800, "armor": 150},
}
const DROP_CHANCE := 0.06

var max_value := 200
var value := 0.0

func is_full() -> bool: return value >= max_value

func add(amount: int) -> bool:
	assert(amount >= 0)
	if is_full(): return false
	value = minf(max_value, value + amount)
	return true

func buy(pack_id: String, economy: Economy) -> bool:
	var p: Dictionary = PACKS[pack_id]
	if is_full() or p.cost > economy.points: return false
	economy.spend(p.cost)
	add(p.armor)
	return true

## Returns the damage that reaches health.
func absorb(damage: float) -> float:
	assert(damage >= 0.0)
	var soaked := minf(value, damage)
	value -= soaked
	return damage - soaked
