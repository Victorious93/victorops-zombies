class_name OverchargeForge
extends RefCounted
## Weapon upgrade machine. Tier price: cost * (tier + 1). Needs power.

const NAME := "Overcharge Forge"
var cost := 5000

## Price of the next upgrade, or -1 if maxed.
func cost_for(w: WeaponDef) -> int:
	return -1 if w.is_maxed() else cost * (w.tier + 1)

## Returns the upgraded weapon, or null if maxed/unaffordable.
func upgrade(w: WeaponDef, economy: Economy) -> WeaponDef:
	var price := cost_for(w)
	if price < 0 or not economy.spend(price): return null
	return w.upgraded_version()
