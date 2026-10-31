class_name ZombieRunClip
## v7.14: original, code-authored "ZRun" clip for zombie_b. The model's stock Run is an upright human
## jog with pumping arms; this re-keys it into a hunched, lurching shamble-sprint: torso pitched forward,
## arms thrown out in front with a damped flail, head craned up, and a limp (uneven stride).
## Built from the stock clip's leg timing so feet still roughly match ground speed. No external assets.

const NAME := "ZRun"
const BODY_PITCH := 0.32      ## forward hunch (rad)
const BODY_ROLL := 0.12       ## side-to-side lurch (rad)
const ARM_REACH := 1.25       ## arms raised toward the target (rad)
const ARM_SWING_KEEP := 0.3   ## fraction of the jog's arm pump kept (flail, not pump)
const HEAD_LIFT := 0.3        ## crane the head back up so it looks ahead despite the hunch
const LIMP := 0.82            ## one leg's stride scale (other is 1.0)
const ARM_AXIS := Vector3(1, 0, 0)
const BODY_AXIS := Vector3(1, 0, 0)

## Adds (once) the ZRun animation to the player's default library and returns its full name ("" if not possible).
static func install(ap: AnimationPlayer, run_name: String) -> String:
	if ap == null or not ap.has_animation(run_name): return ""
	if ap.has_animation(NAME): return NAME
	var lib: AnimationLibrary = ap.get_animation_library(&"") if ap.has_animation_library(&"") else null
	if lib == null:
		lib = AnimationLibrary.new(); ap.add_animation_library(&"", lib)
	var a := build(ap.get_animation(run_name))
	if a == null: return ""
	lib.add_animation(NAME, a)
	return NAME

## Pure: the stock run → the shamble-sprint. Returns a new Animation (the source is untouched).
static func build(src: Animation) -> Animation:
	if src == null: return null
	var a := src.duplicate(true) as Animation
	a.loop_mode = Animation.LOOP_LINEAR
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D: continue
		var bone := bone_of(a.track_get_path(t))
		var n := a.track_get_key_count(t)
		if n == 0: continue
		var mean := _mean(a, t)
		for k in n:
			var q: Quaternion = a.track_get_key_value(t, k)
			var ph := a.track_get_key_time(t, k) / maxf(0.001, a.length) * TAU
			a.track_set_key_value(t, k, reshape(bone, q, mean, ph))
	return a

static func reshape(bone: String, q: Quaternion, mean: Quaternion, phase: float) -> Quaternion:
	match bone:
		"Body":
			var lurch := Quaternion(Vector3(0, 0, 1), sin(phase) * BODY_ROLL)
			return (Quaternion(BODY_AXIS, BODY_PITCH + 0.05 * sin(phase * 2.0)) * lurch * q).normalized()
		"Head":
			return (Quaternion(Vector3(1, 0, 0), -HEAD_LIFT) * Quaternion(Vector3(0, 1, 0), 0.08 * sin(phase * 3.0)) * q).normalized()
		"Arm.L", "Arm.R":
			var damped := mean.slerp(q, ARM_SWING_KEEP)
			var side := -1.0 if bone == "Arm.L" else 1.0
			var reach := ARM_REACH + (0.12 * side)   # uneven arms read as "dead", not athletic
			return (Quaternion(ARM_AXIS, -reach) * damped).normalized()
		"Leg.L":
			return mean.slerp(q, LIMP)
	return q

static func bone_of(path: NodePath) -> String:
	return String(path.get_concatenated_subnames())

static func _mean(a: Animation, t: int) -> Quaternion:
	var first: Quaternion = a.track_get_key_value(t, 0)
	var acc := Vector4.ZERO
	for k in a.track_get_key_count(t):
		var q: Quaternion = a.track_get_key_value(t, k)
		if q.dot(first) < 0.0: q = -q
		acc += Vector4(q.x, q.y, q.z, q.w)
	var m := acc.normalized()
	return Quaternion(m.x, m.y, m.z, m.w)
