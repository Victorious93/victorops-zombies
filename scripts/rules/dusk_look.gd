class_name DuskLook
extends RefCounted
## v10.1 graphics pass ("dusk pass"): the tuning numbers and pure curves behind the town's look, kept out
## of the scene code so they can be unit-tested. Everything here is cosmetic: no collision, navigation,
## damage or economy depends on it.

# ---------------------------------------------------------------- sky, fog, ambient
## Deep indigo overhead, a narrow dusty-rose band on the western horizon (the last of the light), and a
## dark ground horizon so the skyline silhouettes read against it.
const SKY_TOP := Color(0.07, 0.09, 0.17)
const SKY_HORIZON := Color(0.5, 0.36, 0.38)
const SKY_CURVE := 0.12
const GROUND_HORIZON := Color(0.22, 0.2, 0.24)
const GROUND_BOTTOM := Color(0.03, 0.035, 0.05)
const SKY_ENERGY := 0.9
## Fog: still a haze (readability first) but denser low to the ground, so the paving sits in a thin mist
## and lamp-lit areas stand out from the dark between them.
const FOG_COLOR := Color(0.19, 0.2, 0.28)
const FOG_DENSITY := 0.011
const FOG_DENSITY_LATE := 0.022      ## round 15 and later
const FOG_HEIGHT := 0.6
const FOG_HEIGHT_DENSITY := 0.16
const FOG_SKY_AFFECT := 0.3
const AMBIENT_COLOR := Color(0.36, 0.42, 0.58)
## Ambient is the floor of readability: never below this fraction of the v10 value.
const AMBIENT_SCALE := 0.92
const CONTRAST := 1.1

static func fog_density(atmos01: float) -> float:
	return lerpf(FOG_DENSITY, FOG_DENSITY_LATE, clampf(atmos01, 0.0, 1.0))

# ---------------------------------------------------------------- wet ground
## Puddles: flat glossy patches in the open-air areas (Back Alley, Main Street, Courtyard). One MultiMesh,
## so the whole set is a single draw call on every preset.
const PUDDLE_ZONES := [Rect2(-8.6, -24.6, 17.2, 13.2), Rect2(27.4, -13.0, 17.2, 21.6), Rect2(21.4, 11.4, 23.2, 17.2)]
const PUDDLE_COUNT := 34
const PUDDLE_Y := 0.022
const PUDDLE_ROUGHNESS := 0.06
## Roughness multiplier of the asphalt / cobbles after the rain (v10: 1.0).
const WET_ROUGHNESS := 0.72

## Deterministic puddle layout: [x, z, size, yaw] per puddle, all inside PUDDLE_ZONES and outside `roofed`.
static func puddle_spots(seed: int, count: int, roofed: Array) -> Array:
	var rr := RandomNumberGenerator.new(); rr.seed = seed
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < count * 40:
		guard += 1
		var zr: Rect2 = PUDDLE_ZONES[out.size() % PUDDLE_ZONES.size()]
		var p := Vector2(rr.randf_range(zr.position.x, zr.end.x), rr.randf_range(zr.position.y, zr.end.y))
		var blocked := false
		for r in roofed:
			if (r as Rect2).grow(0.8).has_point(p): blocked = true; break
		for q in out:
			if p.distance_to(Vector2(q[0], q[1])) < 1.6: blocked = true; break
		if blocked: continue
		out.append([p.x, p.y, rr.randf_range(0.9, 2.3), rr.randf() * TAU])
	return out

# ---------------------------------------------------------------- generator payoff
const POWER_BURST_ENERGY := 9.0
const POWER_BURST_TIME := 1.4
const POWER_BURST_COLOR := Color(0.75, 1.0, 0.8)
## Flash at the generator when it catches: a hard spike that decays quickly, then a short afterglow.
static func power_burst(t: float) -> float:
	if t < 0.0 or t >= POWER_BURST_TIME: return 0.0
	return POWER_BURST_ENERGY * pow(1.0 - t / POWER_BURST_TIME, 2.2)

# ---------------------------------------------------------------- Brute slam
const SHOCK_TIME := 0.55
const SHOCK_START := 0.4     ## fraction of the slam radius at impact
const SHOCK_END := 1.35      ## the wave rolls a little past the danger ring, so the ring edge is visible
static func shock_radius(t: float, slam_radius: float) -> float:
	var k := clampf(t / SHOCK_TIME, 0.0, 1.0)
	return slam_radius * lerpf(SHOCK_START, SHOCK_END, 1.0 - pow(1.0 - k, 3.0))
static func shock_alpha(t: float) -> float:
	if t < 0.0 or t >= SHOCK_TIME: return 0.0
	return 0.9 * (1.0 - t / SHOCK_TIME)

# ---------------------------------------------------------------- round transition
## Round start: a blood-red edge vignette that hits hard and bleeds out over ~1.6 s.
const ROUND_IN_TIME := 1.6
static func round_in_alpha(t: float) -> float:
	if t < 0.0 or t >= ROUND_IN_TIME: return 0.0
	if t < 0.08: return 0.75 * t / 0.08
	return 0.75 * pow(1.0 - (t - 0.08) / (ROUND_IN_TIME - 0.08), 1.5)
## Round survived: a slow cold-dark edge that settles in for the breather, never darker than 0.45.
const ROUND_OUT_TIME := 3.0
static func round_out_alpha(t: float) -> float:
	if t < 0.0 or t >= ROUND_OUT_TIME: return 0.0
	return 0.45 * sin(PI * t / ROUND_OUT_TIME)
