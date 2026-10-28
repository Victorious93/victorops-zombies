class_name WonderQuest
## Buildable wonder weapon: find three hidden parts, then assemble them at the workbench.
## The weapon is the Gloam Harp (original design: a string-coil resonator that fires piercing sound waves).

const WEAPON := "gloam"
const PARTS := ["frame", "core", "coil"]
const PART_NAMES := {"frame": "Harp Frame", "core": "Gloam Core", "coil": "String Coil"}
## Hidden spots per part (map-local positions). One is chosen per game so the hunt changes.
const SPOTS := {
	"frame": [Vector3(-8.6, 0.35, 8.6), Vector3(8.6, 0.35, -8.6), Vector3(-3.0, 0.35, 8.8)],     # intake
	"core":  [Vector3(-8.5, 0.35, -16.0), Vector3(7.5, 0.35, -21.0), Vector3(4.0, 0.35, -12.0)], # generator wing
	"coil":  [Vector3(23.0, 0.35, 7.5), Vector3(13.0, 0.35, -7.5), Vector3(22.0, 0.35, -2.0)],   # lab corridor
}
const BENCH := Vector3(5.5, 0.0, -9.1)
const STONE := Vector3(6.0, 0.0, 3.5)
var chosen := {}       ## part -> spot index
var found := {}        ## part -> true
var built := false
var taken := false

func pick_spots(rng: RandomNumberGenerator) -> void:
	chosen.clear()
	for p in PARTS: chosen[p] = rng.randi() % SPOTS[p].size()

func spot(part: String) -> Vector3: return SPOTS[part][chosen.get(part, 0)]

## Returns true if the part was newly collected.
func collect(part: String) -> bool:
	if not part in PARTS or found.has(part): return false
	found[part] = true
	return true

func count() -> int: return found.size()
func has_all() -> bool: return count() == PARTS.size()
func can_build() -> bool: return has_all() and not built

func build() -> bool:
	if not can_build(): return false
	built = true
	return true

## Pick the finished weapon up off the bench (once per game).
func take() -> bool:
	if not built or taken: return false
	taken = true
	return true

func prompt() -> String:
	if taken: return ""
	if built: return "Take the Gloam Harp"
	if has_all(): return "Assemble the Gloam Harp"
	return "Workbench: %d / %d parts" % [count(), PARTS.size()]
