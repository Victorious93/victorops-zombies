class_name Characters
## Playable characters from PR #2 (display names only; drawn as original stylised models).
## See README: real-person names need permission before any public release.

const ALL := {
	"snoop": {"name": "Snoop Dogg", "tagline": "Fast and smooth. Bass Drop knocks the horde back.",
		"max_health": 100.0, "speed_mult": 1.12, "fire_interval_mult": 0.85, "start_weapon": "smg",
		"repair_planks_per_use": 1, "repair_points_mult": 1, "ability": "bass_drop", "ability_name": "Bass Drop", "ability_cooldown": 25.0},
	"martha": {"name": "Martha Stewart", "tagline": "Tough and tidy. Repairs fast, Fortify rebuilds every window.",
		"max_health": 130.0, "speed_mult": 1.0, "fire_interval_mult": 1.0, "start_weapon": "scatter",
		"repair_planks_per_use": 2, "repair_points_mult": 2, "ability": "fortify", "ability_name": "Fortify", "ability_cooldown": 35.0},
}
const DEFAULT := "snoop"

const BASS_RADIUS_M := 4.0      # 240 units / 60
const BASS_KNOCKBACK_M := 2.33  # 140 units / 60

static func by_id(id: String) -> Dictionary:
	return ALL.get(id, ALL[DEFAULT])

static func bass_damage(round: int) -> int:
	return 100 + 40 * round
