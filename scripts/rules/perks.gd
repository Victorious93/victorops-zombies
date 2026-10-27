class_name Perks
## Perk tonics. Iron Hide Tonic is the original perk; Quickhand Draught and Fleetfoot Phial are new.
## Perk machines and the Overcharge Forge need the facility power on; the Mystery Crate does not.

const ALL := {
	"ironhide": {"name": "Iron Hide Tonic", "cost": 2500, "desc": "Doubles max health", "color": Color(0.85, 0.15, 0.1)},
	"quickhand": {"name": "Quickhand Draught", "cost": 3000, "desc": "Reloads twice as fast", "color": Color(0.1, 0.7, 0.3)},
	"fleetfoot": {"name": "Fleetfoot Phial", "cost": 2000, "desc": "+15% move speed, more stamina", "color": Color(0.2, 0.5, 1.0)},
	"lazarus": {"name": "Lazarus Fizz", "cost": 2000, "desc": "Solo: get back up once when downed (max 3 buys)", "color": Color(0.35, 0.85, 1.0)},
}

## Tries to buy [perk_id] for a player that owns [owned]. Returns an error string, or "" on success.
const LAZARUS_MAX := 3

## owned may hold "_lazarus_buys" (int) to enforce the self-revive limit.
static func buy(perk_id: String, owned: Dictionary, economy: Economy, power_on: bool) -> String:
	if not power_on: return "Power required"
	if owned.get(perk_id, false): return "Already owned"
	if perk_id == "lazarus" and int(owned.get("_lazarus_buys", 0)) >= LAZARUS_MAX: return "Sold out"
	if not economy.spend(ALL[perk_id].cost): return "Not enough points"
	owned[perk_id] = true
	if perk_id == "lazarus": owned["_lazarus_buys"] = int(owned.get("_lazarus_buys", 0)) + 1
	return ""

## Perk ids held (skips bookkeeping keys).
static func held(owned: Dictionary) -> Array:
	var out := []
	for k in owned:
		if not String(k).begins_with("_") and owned[k] == true: out.append(k)
	return out
