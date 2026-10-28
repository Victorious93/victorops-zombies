class_name GameSettings
extends RefCounted
## Player settings + graphics presets (pure data; saved to user://settings.cfg by the game).

const PRESETS := {
	"low": {"label": "Low (30 fps phones)", "scale": 0.6, "shadows": false, "glow": false, "fog": true, "particles": 0.4, "max_lights": 6, "msaa": 0, "dust": false, "ragdolls": 3},
	"medium": {"label": "Medium (60 fps mid-range)", "scale": 0.75, "shadows": false, "glow": true, "fog": true, "particles": 0.7, "max_lights": 10, "msaa": 0, "dust": true, "ragdolls": 5},
	"high": {"label": "High", "scale": 1.0, "shadows": true, "glow": true, "fog": true, "particles": 1.0, "max_lights": 16, "msaa": 2, "dust": true, "ragdolls": 8},
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
var starter_gun := "smg"   ## Armory pick: which wall-buy is discounted at the spawn room
var tutorial_done := false
var button_scale := 1.0    ## touch HUD button size 0.7 - 1.4
var button_opacity := 0.6  ## touch HUD opacity 0.15 - 1.0
var left_fire := false     ## second FIRE button on the left
var show_fps := false      ## HUD performance readout (fps + draw calls)
var layout := {}           ## layout editor: button name -> Vector2 fraction of the safe area
const STARTER_GUNS := ["smg", "scatter", "rifle"]
const GYRO_MODES := ["off", "ads", "always"]

static func default_preset(is_mobile: bool) -> String:
	return "low" if is_mobile else "high"

func set_sensitivity(v: float) -> void: sensitivity = clampf(v, 0.2, 3.0)
func set_preset(id: String) -> void: preset = id if PRESETS.has(id) else "medium"
func data() -> Dictionary: return PRESETS[preset]

static func linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func to_dict() -> Dictionary:
	return {sensitivity = sensitivity, preset = preset, aim_assist = aim_assist, music = music, sfx = sfx, auto_fire = auto_fire, gyro = gyro, look_curve = look_curve, joystick = joystick, fire_size = fire_size, starter_gun = starter_gun, tutorial_done = tutorial_done, button_scale = button_scale, button_opacity = button_opacity, left_fire = left_fire, show_fps = show_fps, layout = _layout_out()}

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
	starter_gun = str(d.get("starter_gun", "smg"))
	if not STARTER_GUNS.has(starter_gun): starter_gun = "smg"
	tutorial_done = bool(d.get("tutorial_done", false))
	button_scale = clampf(float(d.get("button_scale", 1.0)), 0.7, 1.4)
	button_opacity = clampf(float(d.get("button_opacity", 0.6)), 0.15, 1.0)
	left_fire = bool(d.get("left_fire", false))
	show_fps = bool(d.get("show_fps", false))
	layout = {}
	var lo = d.get("layout", {})
	if lo is Dictionary:
		for k in lo:
			var v = lo[k]
			if v is Vector2: layout[str(k)] = v
			elif v is Array and v.size() == 2: layout[str(k)] = Vector2(clampf(float(v[0]), 0, 1), clampf(float(v[1]), 0, 1))

func _layout_out() -> Dictionary:
	var o := {}
	for k in layout: o[k] = [layout[k].x, layout[k].y]
	return o
