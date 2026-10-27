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
