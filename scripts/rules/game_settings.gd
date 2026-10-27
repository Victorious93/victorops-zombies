class_name GameSettings
extends RefCounted
## Player settings + graphics presets (pure data; saved to user://settings.cfg by the game).

const PRESETS := {
	"low": {"label": "Low (30 fps phones)", "scale": 0.6, "shadows": false, "glow": false, "fog": true, "particles": 0.4, "max_lights": 6, "msaa": 0, "dust": false},
	"medium": {"label": "Medium (60 fps mid-range)", "scale": 0.75, "shadows": false, "glow": true, "fog": true, "particles": 0.7, "max_lights": 10, "msaa": 0, "dust": true},
	"high": {"label": "High", "scale": 1.0, "shadows": true, "glow": true, "fog": true, "particles": 1.0, "max_lights": 16, "msaa": 2, "dust": true},
}
const ORDER := ["low", "medium", "high"]

var sensitivity := 1.0   ## 0.2 - 3.0 multiplier
var preset := "medium"
var aim_assist := true
var music := 0.7          ## 0 - 1
var sfx := 1.0
var auto_fire := false     ## touch: fire automatically while the crosshair is on a zombie
var gyro := "off"          ## "off" | "ads" | "always": phone gyroscope adds to touch look
var look_curve := 1.3      ## 1.0 linear - 1.8 accelerated
var joystick := "floating" ## "floating" (appears under the thumb) | "fixed" (stays in the corner)
var fire_size := 1.3       ## fire button scale 1.0 - 1.8
const GYRO_MODES := ["off", "ads", "always"]

static func default_preset(is_mobile: bool) -> String:
	return "low" if is_mobile else "high"

func set_sensitivity(v: float) -> void: sensitivity = clampf(v, 0.2, 3.0)
func set_preset(id: String) -> void: preset = id if PRESETS.has(id) else "medium"
func data() -> Dictionary: return PRESETS[preset]

static func linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func to_dict() -> Dictionary:
	return {sensitivity = sensitivity, preset = preset, aim_assist = aim_assist, music = music, sfx = sfx, auto_fire = auto_fire, gyro = gyro, look_curve = look_curve, joystick = joystick, fire_size = fire_size}

func from_dict(d: Dictionary) -> void:
	set_sensitivity(float(d.get("sensitivity", 1.0)))
	set_preset(str(d.get("preset", "medium")))
	aim_assist = bool(d.get("aim_assist", true))
	music = clampf(float(d.get("music", 0.7)), 0.0, 1.0)
	sfx = clampf(float(d.get("sfx", 1.0)), 0.0, 1.0)
	auto_fire = bool(d.get("auto_fire", false))
	gyro = str(d.get("gyro", "off"))
	if not GYRO_MODES.has(gyro): gyro = "off"
	look_curve = clampf(float(d.get("look_curve", 1.3)), 1.0, 1.8)
	joystick = "fixed" if str(d.get("joystick", "floating")) == "fixed" else "floating"
	fire_size = clampf(float(d.get("fire_size", 1.3)), 1.0, 1.8)
