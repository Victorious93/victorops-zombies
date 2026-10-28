class_name HandPose
extends SkeletonModifier3D
## Runs after the arm IK: aligns each wrist to its target's basis (plus a fixed rest offset so the palm
## faces the grip) and curls the fingers into a fist around it.

var targets: Array = []          ## [right, left] Node3D
var curl := [0.9, 0.8]
## knuckles up/out, palm toward the grip, fingers wrapping across it (tuned per-weapon in probe renders)
var wrist_offset := [Basis.from_euler(Vector3(1.57, 0.0, 0.0)), Basis.from_euler(Vector3(1.57, 0.0, 0.0))]
const FINGERS := ["index", "middle", "ring", "pinky"]

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or targets.size() < 2: return
	var inv := sk.global_transform.affine_inverse()
	for i in 2:
		var s := "r" if i == 0 else "l"
		var t: Node3D = targets[i]
		if not is_instance_valid(t) or not t.is_inside_tree(): continue
		var w := sk.find_bone("wrist." + s)
		var gp := sk.get_bone_global_pose(w)
		var tb := (inv * t.global_transform).basis.orthonormalized()
		gp.basis = (tb * wrist_offset[i]).scaled(gp.basis.get_scale())
		sk.set_bone_global_pose(w, gp)
		for f in FINGERS:
			for k in [1, 2, 3]:
				var b := sk.find_bone("finger_%s%d.%s" % [f, k, s])
				if b < 0: continue
				var rest := sk.get_bone_rest(b).basis.get_rotation_quaternion()
				sk.set_bone_pose_rotation(b, rest * Quaternion(Vector3.RIGHT, curl[i] * (0.9 if k == 1 else 1.1)))
		var th := sk.find_bone("finger_thumb2." + s)
		if th >= 0: sk.set_bone_pose_rotation(th, sk.get_bone_rest(th).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, curl[i] * 0.5))
