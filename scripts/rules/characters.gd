class_name Characters
## Playable characters. Both are ORIGINAL characters (they replace the earlier real-person
## placeholders); the Bass Drop and Fortify abilities are unchanged.

const ALL := {
	"rook": {"name": "Rook Vance", "role": "Night-shift sound tech",
		"tagline": "Fast and loose. Bass Drop: a sub-bass shockwave that blasts the horde back.",
		"max_health": 100.0, "speed_mult": 1.12, "fire_interval_mult": 0.85, "start_weapon": "smg",
		"repair_planks_per_use": 1, "repair_points_mult": 1, "ability": "bass_drop", "ability_name": "Bass Drop", "ability_cooldown": 25.0,
		"color": Color(0.55, 0.35, 1.0)},
	"hollis": {"name": "Hollis Marrow", "role": "Facility quartermaster",
		"tagline": "Tough and tidy. Repairs fast; Fortify rebuilds every window at once.",
		"max_health": 130.0, "speed_mult": 1.0, "fire_interval_mult": 1.0, "start_weapon": "scatter",
		"repair_planks_per_use": 2, "repair_points_mult": 2, "ability": "fortify", "ability_name": "Fortify", "ability_cooldown": 35.0,
		"color": Color(1.0, 0.65, 0.2)},
}
const DEFAULT := "rook"

const BASS_RADIUS_M := 4.0      # 240 units / 60
const BASS_KNOCKBACK_M := 2.33  # 140 units / 60

static func by_id(id: String) -> Dictionary:
	return ALL.get(id, ALL[DEFAULT])

static func bass_damage(round: int) -> int:
	return 100 + 40 * round
