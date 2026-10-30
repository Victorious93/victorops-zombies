class_name ArmorState
extends RefCounted
## Armor soaks damage before health, caps at 200, persists between rounds.

const PACKS := {
	"light": {"name": "Light Plating", "cost": 500, "armor": 50},
	"medium": {"name": "Reinforced Vest", "cost": 1000, "armor": 100},
	"heavy": {"name": "Bulwark Suit", "cost": 1800, "armor": 150},
}
const DROP_CHANCE := 0.06
## v7.12 Vault Plating (Sealed Annex station): three buyable tiers. Each raises the cap,
## refills to it and cuts the damage that gets through the plate.
const TIERS := [
	{"name": "Vault Plating I", "cost": 2000, "cap": 250, "resist": 0.10},
	{"name": "Vault Plating II", "cost": 3500, "cap": 300, "resist": 0.20},
	{"name": "Vault Plating III", "cost": 5500, "cap": 400, "resist": 0.30},
]
var tier := 0

func next_tier_cost() -> int: return -1 if tier >= TIERS.size() else int(TIERS[tier].cost)

func buy_tier(economy: Economy) -> bool:
	var c := next_tier_cost()
	if c < 0 or c > economy.points: return false
	economy.spend(c)
	max_value = int(TIERS[tier].cap)
	tier += 1
	value = max_value
	return true

func resist() -> float: return 0.0 if tier == 0 else float(TIERS[tier - 1].resist)

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
	if soaked > 0.0 and value > 0.0: return (damage - soaked) * (1.0 - resist())
	return damage - soaked
