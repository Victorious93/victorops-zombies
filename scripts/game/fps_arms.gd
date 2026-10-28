class_name FpsArms
extends Node3D
## First-person arms: the CC0 "WRAD" rigged arms (github.com/wwwriks/wrad-arms) driven by two
## TwoBoneIK3D chains whose targets ride on the current gun (right hand on the grip, left on the
## fore-end or support-gripping the pistol), plus a small modifier that orients the wrists and curls
## the fingers around the grip. Parented to the player camera, so the shoulders stay put while the
## gun sways/bobs/recoils and the hands follow it.

const SCALE := 0.1
const FORE_REACH := 0.5
const GLOVE_COLOR := Color(0.17, 0.16, 0.12)
var skel: Skeleton3D
var ik: TwoBoneIK3D
var hands: HandPose
var target_r := Node3D.new()
var target_l := Node3D.new()
var pole_r := Node3D.new()
var pole_l := Node3D.new()
var mat: StandardMaterial3D

func _init() -> void:
	name = "FpsArms"
	var scn: Node3D = load("res://assets/models/fps_arms.glb").instantiate()
	scn.scale = Vector3.ONE * SCALE
	scn.position = Vector3(0, -0.24, -0.04)   # head bone sits ~at the eye; shoulders a little behind/below
	add_child(scn)
	skel = scn.find_children("*", "Skeleton3D", true, false)[0]
	mat = StandardMaterial3D.new()
	# olive tactical sleeves + gloves: a flat dyed-fabric albedo (the pale skin map multiplied by a tint
	# still read as bare skin under the viewmodel fill light, so it is not used)
	mat.albedo_color = GLOVE_COLOR
	mat.roughness = 0.85; mat.rim_enabled = true; mat.rim = 0.3; mat.rim_tint = 0.5
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).custom_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))   # skinned: rest-pose AABB hangs below the view and got frustum-culled once IK lifted the hands
	for n in [target_r, target_l, pole_r, pole_l]: add_child(n)
	pole_r.position = Vector3(0.45, -0.45, 0.1); pole_l.position = Vector3(-0.45, -0.45, 0.1)
	ik = TwoBoneIK3D.new(); ik.set_setting_count(2)
	for i in 2:
		var s := "r" if i == 0 else "l"
		ik.set_root_bone_name(i, "bicep." + s); ik.set_middle_bone_name(i, "forearm." + s); ik.set_end_bone_name(i, "wrist." + s)
	skel.add_child(ik)
	hands = HandPose.new(); skel.add_child(hands)

func _ready() -> void:
	ik.set_target_node(0, ik.get_path_to(target_r)); ik.set_target_node(1, ik.get_path_to(target_l))
	ik.set_pole_node(0, ik.get_path_to(pole_r)); ik.set_pole_node(1, ik.get_path_to(pole_l))
	hands.targets = [target_r, target_l]

## Points (in the gun's local space) the wrists reach for, and the hand basis there.
func attach(gun: Node3D, grip: Vector3, fore: Vector3, two_handed: bool) -> void:
	for t in [target_r, target_l]:
		if t.get_parent(): t.get_parent().remove_child(t)
		gun.add_child(t)
	# wrist sits behind/below the palm: the palm wraps the grip, fingers point across the gun (-X for the right hand)
	target_r.position = grip + Vector3(0.035, 0.03, 0.035)
	target_r.rotation = Vector3(-0.25, 0.0, 0.0)
	if two_handed:
		# support hand on the near half of the fore-end: the far end is beyond the rig's arm reach,
		# which left the hand stretched out and floating beside the barrel
		target_l.position = grip.lerp(fore, FORE_REACH) + Vector3(-0.03, 0.02, 0.0)
		target_l.rotation = Vector3(-0.1, 0.0, 0.0)
	else:   # pistol: support hand cups the firing hand
		target_l.position = grip + Vector3(-0.04, 0.035, 0.045)
		target_l.rotation = Vector3(-0.25, 0.0, 0.0)
	if is_inside_tree():
		ik.set_target_node(0, ik.get_path_to(target_r)); ik.set_target_node(1, ik.get_path_to(target_l))
	hands.curl = [0.9, 0.75 if two_handed else 0.85]
