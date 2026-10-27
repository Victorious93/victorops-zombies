class_name GameSettings
extends RefCounted
## Player settings + graphics presets (pure data; saved to user://settings.cfg by the game).

const PRESETS := {
	"low": {"label": "Low (30 fps phones)", "scale": 0.6, "shadows": false, "glow": false, "fog": true, "particles": 0.4, "max_lights": 6, "msaa": 0, "dust": false},
	"medium": {"label": "Medium", "scale": 0.8, "shadows": false, "glow": true, "fog": true, "particles": 0.7, "max_lights": 10, "msaa": 0, "dust": true},
	"high": {"label": "High", "scale": 1.0, "shadows": true, "glow": true, "fog": true, "particles": 1.0, "max_lights": 16, "msaa": 2, "dust": true},
}
const ORDER := ["low", "medium", "high"]

var sensitivity := 1.0   ## 0.2 - 3.0 multiplier
var preset := "medium"
var aim_assist := true
var music := 0.7          ## 0 - 1
var sfx := 1.0

static func default_preset(is_mobile: bool) -> String:
	return "low" if is_mobile else "high"

func set_sensitivity(v: float) -> void: sensitivity = clampf(v, 0.2, 3.0)
func set_preset(id: String) -> void: preset = id if PRESETS.has(id) else "medium"
func data() -> Dictionary: return PRESETS[preset]

static func linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func to_dict() -> Dictionary:
	return {sensitivity = sensitivity, preset = preset, aim_assist = aim_assist, music = music, sfx = sfx}

func from_dict(d: Dictionary) -> void:
	set_sensitivity(float(d.get("sensitivity", 1.0)))
	set_preset(str(d.get("preset", "medium")))
	aim_assist = bool(d.get("aim_assist", true))
	music = clampf(float(d.get("music", 0.7)), 0.0, 1.0)
	sfx = clampf(float(d.get("sfx", 1.0)), 0.0, 1.0)
