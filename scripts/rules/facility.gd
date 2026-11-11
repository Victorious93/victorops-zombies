class_name Facility
extends RefCounted
## Map progression state: buyable doors open areas, the power switch, and which windows spawn.
## Pure data so it can be unit tested; the 3D map reads it.

const DOORS := {
	"north": {"cost": 750, "opens": "generator", "label": "Back Alley"},
	"east": {"cost": 1000, "opens": "lab", "label": "General Store"},
	"cold": {"cost": 1250, "opens": "cold", "label": "Garage"},
	"yard": {"cost": 1250, "opens": "yard", "label": "Main Street"},
	"pump": {"cost": 1250, "opens": "pump", "label": "Courtyard"},
	## v8: closes the loop Diner -> Back Alley -> Garage -> General Store -> Diner. Buyable from either side,
	## so it opens both rooms it joins.
	"service": {"cost": 1000, "opens": "cold", "also": "lab", "label": "Service Door"},
	## v9: the store's back door onto the Side Alley closes a second loop Store -> Main Street -> Courtyard
	## -> Side Alley -> Store. Buyable from either side.
	"alley": {"cost": 1000, "opens": "pump", "also": "lab", "label": "Side Alley"},
}
## Window id -> area it belongs to (only opened areas spawn zombies).
const WINDOWS := {"w_west": "intake", "w_south": "intake", "w_gen": "generator", "w_lab": "lab", "w_cold": "cold", "w_yard_n": "yard", "w_yard_s": "yard", "w_pump_s": "pump", "w_pump_e": "pump"}

var open_areas := {"intake": true}
var open_doors := {}
var power_on := false

func buy_door(door_id: String, economy: Economy) -> String:
	if open_doors.get(door_id, false): return "Already open"
	if not economy.spend(DOORS[door_id].cost): return "Not enough points"
	open_doors[door_id] = true
	open_areas[DOORS[door_id].opens] = true
	if DOORS[door_id].has("also"): open_areas[DOORS[door_id].also] = true
	return ""

## Returns true the first time the switch is thrown.
func throw_power() -> bool:
	if power_on: return false
	power_on = true
	return true

func active_windows() -> Array:
	var out := []
	for w in WINDOWS:
		if open_areas.get(WINDOWS[w], false): out.append(w)
	return out
