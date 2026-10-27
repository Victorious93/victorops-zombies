class_name WeaponDef
extends RefCounted
## One weapon (original roster). Same Forge upgrade maths as the libGDX Weapon.kt.

const MAX_TIER := 2
const DAMAGE_STEP := [2.0, 1.5]
const INTERVAL_STEP := [0.8, 0.8125]
const SPLASH_UNITS_PER_METRE := 60.0

var id: String
var name: String
var damage: int
var fire_interval: float
var pellets: int = 1
var pierce: int = 0
var splash: float = 0.0  ## radius in original units; see splash_m()
var tier: int = 0
var mag_size: int = 12
var reload_time: float = 1.5
var reserve_mags: int = 8
## Feel: aim-down-sights time (s) and a repeating recoil pattern of (up, right) kicks in degrees-scale units.
var ads_time := 0.2
var recoil_pattern: Array = [Vector2(1, 0)]
var upgrade_name := ""
## Handling mass: 0.6 = light pistol/SMG, 1.6 = LMG/rail. Drives kick, camera punch, move speed and ADS feel.
var weight := 1.0
## 3D feel (not part of the ported rules)
var automatic := false
var spread_deg := 0.6
var recoil := 1.5
var color := Color(0.6, 0.6, 0.65)

func _init(p_id := "", p_name := "", p_damage := 0, p_interval := 0.3) -> void:
	id = p_id; name = p_name; damage = p_damage; fire_interval = p_interval

func setup(opts: Dictionary) -> WeaponDef:
	for k in opts:
		set(k, opts[k])
	return self

func move_mult() -> float: return clampf(1.08 - 0.1 * weight, 0.85, 1.05)
func kick_mult() -> float: return 0.55 + 0.65 * weight
## Extra punch on the first shot after a pause (seconds since last shot) - makes single taps feel heavy.
func first_shot_mult(since_last: float) -> float:
	return 1.0 + 0.8 * clampf((since_last - fire_interval * 1.5) / 0.35, 0.0, 1.0)

func is_upgraded() -> bool: return tier > 0
func is_maxed() -> bool: return tier >= MAX_TIER
func splash_m() -> float: return splash / SPLASH_UNITS_PER_METRE

func display_name() -> String:
	if tier == 0: return name
	var n := upgrade_name if upgrade_name != "" else name
	return n if tier == 1 else "%s Mk.III" % n

func duplicate_def() -> WeaponDef:
	var w := WeaponDef.new(id, name, damage, fire_interval)
	for k in ["pellets", "pierce", "splash", "tier", "mag_size", "reload_time", "automatic", "spread_deg", "recoil", "color", "reserve_mags", "ads_time", "recoil_pattern", "upgrade_name", "weight"]:
		w.set(k, get(k))
	return w

## One Forge step. Mk.II: x2 damage, faster fire. Mk.III: x1.5 more, faster again, +1 pierce.
## Multi-pellet weapons gain 2 pellets per step; blast radius +50%; mags x1.5; reload x0.85.
func upgraded_version() -> WeaponDef:
	if is_maxed():
		return self
	var w := duplicate_def()
	w.tier = tier + 1
	w.damage = int(damage * DAMAGE_STEP[tier])
	w.fire_interval = fire_interval * INTERVAL_STEP[tier]
	if pellets > 1:
		w.pellets = pellets + 2
	if w.tier == MAX_TIER:
		w.pierce = pierce + 1
	w.splash = splash * 1.5
	w.mag_size = int(mag_size * (2.0 if w.tier == 1 else 1.5))  ## big mag boost on the first overcharge
	w.reload_time = reload_time * 0.85
	w.color = Color(0.55, 0.3, 1.0) if w.tier == 1 else Color(1.0, 0.35, 0.9)
	return w
