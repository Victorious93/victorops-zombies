class_name RiftBench
extends RefCounted
## v7.12 second gun-upgrade station, hidden in the Sealed Annex. Not a copy of the Overcharge Forge:
## it only does the FIRST overcharge (Mk.2), costs 3000 instead of 5000 and runs without power.
## Mk.3 still needs the Forge.

const NAME := "Rift Bench"
const COST := 3000

static func cost_for(w: WeaponDef) -> int:
	return -1 if w.tier >= 1 else COST

static func upgrade(w: WeaponDef, economy: Economy) -> WeaponDef:
	var c := cost_for(w)
	if c < 0 or not economy.spend(c): return null
	return w.upgraded_version()
