class_name Facility
extends RefCounted
## Map progression state: buyable doors open areas, the power switch, and which windows spawn.
## Pure data so it can be unit tested; the 3D map reads it.

const DOORS := {
	"north": {"cost": 750, "opens": "generator", "label": "Generator Wing"},
	"east": {"cost": 1000, "opens": "lab", "label": "Lab Corridor"},
	"cold": {"cost": 1250, "opens": "cold", "label": "Cold Storage"},
	"yard": {"cost": 1250, "opens": "yard", "label": "Loading Yard"},
}
## Window id -> area it belongs to (only opened areas spawn zombies).
const WINDOWS := {"w_west": "intake", "w_south": "intake", "w_gen": "generator", "w_lab": "lab", "w_cold": "cold", "w_yard_n": "yard", "w_yard_s": "yard"}

var open_areas := {"intake": true}
var open_doors := {}
var power_on := false

func buy_door(door_id: String, economy: Economy) -> String:
	if open_doors.get(door_id, false): return "Already open"
	if not economy.spend(DOORS[door_id].cost): return "Not enough points"
	open_doors[door_id] = true
	open_areas[DOORS[door_id].opens] = true
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
