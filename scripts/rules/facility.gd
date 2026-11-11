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

## v10: the six rooms are grouped into three districts (the three combat areas of the match).
## Each district is one closed loop with its neighbour, so there is always a second way out.
const DISTRICTS := {
	"diner": {"name": "Diner Block", "areas": ["intake", "generator"], "landmark": "the red-banded Victory Diner and the generator trailer"},
	"works": {"name": "Workshop Row", "areas": ["lab", "cold"], "landmark": "Mercer's General Store and Hollis Auto Repair (Overcharge Forge)"},
	"street": {"name": "Main Street", "areas": ["yard", "pump"], "landmark": "the army blockade and the Courtyard evacuation tent"},
}
const DISTRICT_ORDER := ["diner", "works", "street"]
const AREA_NAMES := {"intake": "Victory Diner", "generator": "Back Alley", "lab": "Mercer's General Store", "cold": "Hollis Auto Repair", "yard": "Main Street", "pump": "Courtyard"}
## Floor rectangles (x0, z0, x1, z1) used to tell which room a position is in.
const AREA_RECTS := {"intake": [-10, -10, 10, 10], "generator": [-10, -26, 10, -10], "lab": [10, -10, 26, 10], "cold": [10, -26, 26, -10], "yard": [26, -46, 46, 10], "pump": [20, 10, 46, 30]}
## Seconds-free objective: the generator is cranked POWER_CRANKS times (one per hold tick) to start it.
const POWER_CRANKS := 4

var open_areas := {"intake": true}
var cranks := 0
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

## One crank of the generator handle. Returns true on the crank that starts it (power comes on).
func crank_power() -> bool:
	if power_on: return false
	cranks += 1
	if cranks < POWER_CRANKS: return false
	return throw_power()

static func district_of(area: String) -> String:
	for id in DISTRICT_ORDER:
		if area in DISTRICTS[id].areas: return id
	return ""

## Room id for a world position (x, z), or "" between rooms.
static func area_at(x: float, z: float) -> String:
	for a in AREA_RECTS:
		var r: Array = AREA_RECTS[a]
		if x >= r[0] and x < r[2] and z >= r[1] and z < r[3]: return a
	return ""

func district_open(id: String) -> bool:
	for a in DISTRICTS[id].areas:
		if open_areas.get(a, false): return true
	return false

func districts_open() -> int:
	var n := 0
	for id in DISTRICT_ORDER:
		if district_open(id): n += 1
	return n

## The current objective line for the HUD ("" once everything is done).
func objective() -> String:
	if not power_on:
		if not open_areas.get("generator", false):
			return "Restore power  ·  open the Back Alley (%d) behind the diner" % DOORS.north.cost
		return "Restore power  ·  crank the generator in the Back Alley  %d/%d" % [cranks, POWER_CRANKS]
	if districts_open() < DISTRICT_ORDER.size():
		for id in DISTRICT_ORDER:
			if not district_open(id): return "Power on  ·  open %s" % DISTRICTS[id].name
	return ""

func active_windows() -> Array:
	var out := []
	for w in WINDOWS:
		if open_areas.get(WINDOWS[w], false): out.append(w)
	return out
