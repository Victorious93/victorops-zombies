class_name AimAssist
## Touch aim assist: gently pulls the view toward the nearest target inside a small cone.

const CONE_DEG := 7.0
const STRENGTH := 0.35  ## fraction of the remaining angle removed per second

## Returns the index of the best target (smallest angle from [fwd] within the cone), or -1.
static func pick(origin: Vector3, fwd: Vector3, targets: Array, max_range := 30.0) -> int:
	var best := -1
	var best_ang := deg_to_rad(CONE_DEG)
	for i in targets.size():
		var to: Vector3 = targets[i] - origin
		var d := to.length()
		if d < 0.01 or d > max_range: continue
		var ang := fwd.normalized().angle_to(to / d)
		if ang < best_ang:
			best_ang = ang; best = i
	return best

## Yaw/pitch nudge (radians) for this frame toward [target]. Yaw is around +Y; positive pitch looks up.
static func nudge(origin: Vector3, fwd: Vector3, target: Vector3, dt: float) -> Vector2:
	var to := (target - origin).normalized()
	var f := fwd.normalized()
	var yaw_err := wrapf(atan2(-to.x, -to.z) - atan2(-f.x, -f.z), -PI, PI)
	var pitch_err := asin(clampf(to.y, -1, 1)) - asin(clampf(f.y, -1, 1))
	var k := clampf(STRENGTH * dt * 10.0, 0.0, 1.0)
	return Vector2(yaw_err, pitch_err) * k

const SLOW_CONE_DEG := 10.0
const SLOW_MIN := 0.45    ## look speed multiplier when the crosshair sits on a target
const AUTOFIRE_RADIUS := 0.42  ## metres around the target point that count as "on target" for auto-fire

## Look slowdown ("friction"): 1.0 far from any target, down to SLOW_MIN right on one.
static func slowdown(origin: Vector3, fwd: Vector3, targets: Array, max_range := 30.0) -> float:
	var best := 1.0
	for t in targets:
		var to: Vector3 = t - origin
		var d := to.length()
		if d < 0.01 or d > max_range: continue
		var ang := rad_to_deg(fwd.normalized().angle_to(to / d))
		if ang < SLOW_CONE_DEG:
			best = minf(best, lerpf(SLOW_MIN, 1.0, ang / SLOW_CONE_DEG))
	return best

## Auto-fire: true when the aim ray passes within AUTOFIRE_RADIUS of a target point (in range).
static func on_target(origin: Vector3, fwd: Vector3, targets: Array, max_range := 35.0) -> bool:
	var f := fwd.normalized()
	for t in targets:
		var to: Vector3 = t - origin
		var along := to.dot(f)
		if along <= 0.3 or along > max_range: continue
		if (to - f * along).length() <= AUTOFIRE_RADIUS: return true
	return false

## Touch look response curve: small drags are precise, fast flicks turn quickly.
## d = drag delta in pixels this frame; curve 1.0 = linear, 1.5 = strongly accelerated.
static func look_curve(d: Vector2, curve: float, ref_px := 12.0) -> Vector2:
	var l := d.length()
	if l < 0.0001: return d
	return d * pow(clampf(l / ref_px, 0.25, 4.0), curve - 1.0)

## Joystick shaping: radial dead zone, then a soft curve so half-tilt walks and full tilt runs.
static func stick(v: Vector2, deadzone := 0.12) -> Vector2:
	var l := v.length()
	if l < deadzone: return Vector2.ZERO
	var k := (minf(l, 1.0) - deadzone) / (1.0 - deadzone)
	return v / l * pow(k, 1.3)

const SNAP_CONE_DEG := 12.0
const SNAP_TIME := 0.14

## Touch ADS snap: when aim is pressed, swing toward the best target inside a wider cone over SNAP_TIME.
## Returns the total yaw/pitch (radians) to apply, or ZERO if nothing qualifies.
static func ads_snap(origin: Vector3, fwd: Vector3, targets: Array, max_range := 25.0) -> Vector2:
	var best := -1
	var best_ang := deg_to_rad(SNAP_CONE_DEG)
	for i in targets.size():
		var to: Vector3 = targets[i] - origin
		var d := to.length()
		if d < 0.01 or d > max_range: continue
		var ang := fwd.normalized().angle_to(to / d)
		if ang < best_ang: best_ang = ang; best = i
	if best < 0: return Vector2.ZERO
	var to: Vector3 = (targets[best] - origin).normalized()
	var f := fwd.normalized()
	return Vector2(wrapf(atan2(-to.x, -to.z) - atan2(-f.x, -f.z), -PI, PI), asin(clampf(to.y, -1, 1)) - asin(clampf(f.y, -1, 1)))
