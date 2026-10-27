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

func is_upgraded() -> bool: return tier > 0
func is_maxed() -> bool: return tier >= MAX_TIER
func splash_m() -> float: return splash / SPLASH_UNITS_PER_METRE

func display_name() -> String:
	return name if tier == 0 else "%s Mk.%d" % [name, tier + 1]

func duplicate_def() -> WeaponDef:
	var w := WeaponDef.new(id, name, damage, fire_interval)
	for k in ["pellets", "pierce", "splash", "tier", "mag_size", "reload_time", "automatic", "spread_deg", "recoil", "color"]:
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
	w.mag_size = int(mag_size * 1.5)
	w.reload_time = reload_time * 0.85
	w.color = Color(0.55, 0.3, 1.0) if w.tier == 1 else Color(1.0, 0.35, 0.9)
	return w
