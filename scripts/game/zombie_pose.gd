class_name ZombiePose
extends SkeletonModifier3D
## Procedural zombie layer on top of the keyframed clips: hunched spine, a jerky head twitch, an
## asymmetric limp/lurch that sways the torso with the gait, and an "arms-out" reach while chasing.
## Every zombie gets its own random gait parameters so a horde never moves in lockstep.

var hunch := 0.35          ## radians of forward bend spread over abdomen/torso/neck
var reach := 0.0           ## 0..1, arms raised toward the target (driven by the zombie while chasing)
var reach_target := 0.0
var lurch := 0.12          ## torso roll amplitude
var gait_hz := 1.6
var twitch_rate := 0.6     ## twitches per second (Poisson)
var _t := randf() * 10.0
var _tw := Quaternion.IDENTITY
var _tw_goal := Quaternion.IDENTITY
var _tw_cd := 0.0
var _limp_side := 1.0 if randf() < 0.5 else -1.0
var bones := {}

func configure(type: String) -> void:
	match type:
		"sprinter": hunch = 0.6; lurch = 0.08; gait_hz = 2.6; twitch_rate = 1.2
		"brute", "warden": hunch = 0.2; lurch = 0.06; gait_hz = 1.2; twitch_rate = 0.3
		"bloater": hunch = 0.15; lurch = 0.18; gait_hz = 1.1; twitch_rate = 0.4
		_: hunch = randf_range(0.25, 0.5); lurch = randf_range(0.08, 0.18); gait_hz = randf_range(1.3, 1.9)

func _bone(n: String) -> int:
	if not bones.has(n): bones[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
	return bones[n]

func _add(n: String, axis: Vector3, ang: float) -> void:
	var b := _bone(n)
	if b < 0 or absf(ang) < 0.0001: return
	var sk := get_skeleton()
	sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(axis, ang))

func _process_modification_with_delta(dt: float) -> void:
	var sk := get_skeleton()
	if sk == null: return
	_t += dt
	reach = move_toward(reach, reach_target, dt * 2.5)
	# hunch: forward bend (bone-local +X pitches the Quaternius spine forward)
	_add("Abdomen", Vector3.RIGHT, hunch * 0.35); _add("Torso", Vector3.RIGHT, hunch * 0.45); _add("Neck", Vector3.RIGHT, -hunch * 0.3)
	_add("Body", Vector3.RIGHT, hunch * 0.6)   # simple rig (zombie_b)
	# lurch: torso rolls toward the bad leg on every other step
	var ph := sin(_t * gait_hz * TAU * 0.5)
	_add("Torso", Vector3.FORWARD, lurch * (ph * 0.6 + 0.4 * _limp_side)); _add("Body", Vector3.FORWARD, lurch * ph)
	# head twitch: hold a pose, then snap to a new random tilt
	_tw_cd -= dt
	if _tw_cd <= 0.0:
		_tw_cd = -log(maxf(randf(), 0.01)) / twitch_rate
		_tw_goal = Quaternion.from_euler(Vector3(randf_range(-0.35, 0.25), randf_range(-0.5, 0.5), randf_range(-0.6, 0.6)))
	_tw = _tw.slerp(_tw_goal, clampf(dt * 22.0, 0, 1))
	var hb := _bone("Head")
	if hb >= 0: sk.set_bone_pose_rotation(hb, sk.get_bone_pose_rotation(hb) * _tw)
	# reach: both arms swing forward/up toward the player, a little asymmetric
	if reach > 0.01:
		var sway := sin(_t * 3.0) * 0.12
		for s in [["L", 1.0], ["R", -1.0]]:
			_add("UpperArm.%s" % s[0], Vector3.RIGHT, -reach * (1.25 + sway * s[1]))
			_add("LowerArm.%s" % s[0], Vector3.RIGHT, -reach * 0.25)
			_add("Arm.%s" % s[0], Vector3.RIGHT, -reach * 1.2)
