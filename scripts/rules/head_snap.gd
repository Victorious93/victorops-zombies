class_name HeadSnap
extends SkeletonModifier3D
## v7.10 headshot snap: rotates the head bone back (and a little sideways) on top of the animation,
## then springs it back with a damped wobble. Runs as a SkeletonModifier3D so the AnimationPlayer
## pose is applied first and the snap is layered over it.

const SNAP_TIME := 0.55
const SNAP_PITCH := 0.95   ## radians the head whips back at the peak
const SNAP_TWIST := 0.45   ## max sideways twist (scaled by the hit side)

var bone := -1
var age := 99.0
var side := 0.0

func snap(p_side := 0.0) -> void:
	age = 0.0; side = clampf(p_side, -1.0, 1.0)

## 0..1 snap strength over time: whips to full within ~50 ms, then a damped spring back.
static func curve(a: float) -> float:
	if a < 0.0 or a >= SNAP_TIME: return 0.0
	if a < 0.05: return a / 0.05
	var k := (a - 0.05) / (SNAP_TIME - 0.05)
	return cos(k * PI * 1.5) * (1.0 - k) * (1.0 - k)

func _process(dt: float) -> void:
	age += dt

func _process_modification() -> void:
	var s := get_skeleton()
	if s == null or bone < 0: return
	var c := curve(age)
	if absf(c) < 0.001: return
	var q := Quaternion(Vector3.RIGHT, -SNAP_PITCH * c) * Quaternion(Vector3.FORWARD, SNAP_TWIST * side * c)
	s.set_bone_pose_rotation(bone, s.get_bone_pose_rotation(bone) * q)
