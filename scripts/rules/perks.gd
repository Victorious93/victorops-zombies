class_name Perks
## Perk tonics. Iron Hide Tonic is the original perk; Quickhand Draught and Fleetfoot Phial are new.
## Perk machines and the Overcharge Forge need the facility power on; the Mystery Crate does not.

const ALL := {
	"ironhide": {"name": "Iron Hide Tonic", "cost": 2500, "desc": "Doubles max health", "color": Color(0.85, 0.15, 0.1)},
	"quickhand": {"name": "Quickhand Draught", "cost": 3000, "desc": "Reloads twice as fast", "color": Color(0.1, 0.7, 0.3)},
	"fleetfoot": {"name": "Fleetfoot Phial", "cost": 2000, "desc": "+15% move speed, faster sprint", "color": Color(0.2, 0.5, 1.0)},
}

## Tries to buy [perk_id] for a player that owns [owned]. Returns an error string, or "" on success.
static func buy(perk_id: String, owned: Dictionary, economy: Economy, power_on: bool) -> String:
	if not power_on: return "Power required"
	if owned.get(perk_id, false): return "Already owned"
	if not economy.spend(ALL[perk_id].cost): return "Not enough points"
	owned[perk_id] = true
	return ""
