class_name GunFeel
## Per-weapon feel tuning: ADS zoom, camera kick and hitmarker classification.

const BASE_FOV := 75.0
## ADS field of view per weapon: scopes zoom harder, close-range guns barely zoom.
const ADS_FOV := {"sidearm": 62.0, "scatter": 66.0, "rifle": 52.0, "cannon": 38.0, "smg": 60.0, "lmg": 56.0, "nova": 58.0}
const PAP_ZOOM_BONUS := 0.95  ## upgraded guns zoom a touch further

static func ads_fov(id: String, upgraded := false) -> float:
	var f: float = ADS_FOV.get(id, 55.0)
	return f * (PAP_ZOOM_BONUS if upgraded else 1.0)

## Look sensitivity multiplier while aiming, matched to the zoom so the crosshair moves the same on screen.
static func ads_sens(id: String, upgraded := false) -> float:
	return clampf(tan(deg_to_rad(ads_fov(id, upgraded)) * 0.5) / tan(deg_to_rad(BASE_FOV) * 0.5), 0.2, 1.0)

## Camera pitch kick (radians) for one shot. Heavy guns kick harder; aiming halves it; crouch trims more.
static func camera_kick(recoil: float, weight: float, ads: bool, crouched := false) -> float:
	var k := deg_to_rad(recoil * 0.55) * lerpf(0.85, 1.25, clampf((weight - 0.6) / 1.0, 0, 1))
	if ads: k *= 0.55
	if crouched: k *= 0.8
	return k

## How fast the camera settles back after kicking (per second). Light guns recover quicker.
static func recovery_rate(weight: float) -> float:
	return clampf(11.0 - weight * 4.0, 4.0, 9.0)

enum Mark { BODY, HEAD, ARMOR, KILL, HEAD_KILL }

static func hitmarker(killed: bool, head: bool, armored := false) -> int:
	if killed: return Mark.HEAD_KILL if head else Mark.KILL
	if armored: return Mark.ARMOR
	return Mark.HEAD if head else Mark.BODY

static func hitmarker_color(mark: int) -> Color:
	match mark:
		Mark.HEAD: return Color(1, 0.85, 0.2)
		Mark.ARMOR: return Color(0.55, 0.75, 1.0)
		Mark.KILL: return Color(1, 0.15, 0.1)
		Mark.HEAD_KILL: return Color(1, 0.05, 0.35)
	return Color(1, 1, 1)

## Impact sound for what a bullet struck.
static func impact_sound(hit_zombie: bool, armored: bool, metal_surface: bool) -> String:
	if hit_zombie: return "impact_metal" if armored else "impact_flesh"
	return "ricochet" if metal_surface and randf() < 0.35 else "impact_wall"
