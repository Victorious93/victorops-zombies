class_name FpsArms
extends Node3D
## First-person arms: the CC0 "WRAD" rigged arms (github.com/wwwriks/wrad-arms) driven by two
## TwoBoneIK3D chains whose targets ride on the current gun (right hand on the grip, left on the
## fore-end or support-gripping the pistol), plus a small modifier that orients the wrists and curls
## the fingers around the grip. Parented to the player camera, so the shoulders stay put while the
## gun sways/bobs/recoils and the hands follow it.

const SCALE := 0.1
## Support-hand grip in gun space: fingers run across under the fore-end, palm faces up at it.
const SUPPORT_FINGERS := Vector3(0.85, 0.2, -0.45)
const SUPPORT_PALM := Vector3(0.25, 1.0, 0.0)
const PALM_FROM_WRIST := 0.045   ## metres from the wrist joint to the palm centre along the fingers
const PALM_GAP := 0.012          ## palm surface below the fore-end underside
const SHOULDER_POS := Vector3(0, -0.24, -0.14)
const GLOVE_COLOR := Color(0.17, 0.16, 0.12)
var skel: Skeleton3D
var ik: TwoBoneIK3D
var hands: HandPose
var target_r := Node3D.new()
var target_l := Node3D.new()
var pole_r := Node3D.new()
var pole_l := Node3D.new()
var mat: StandardMaterial3D
## v7.8 ADS support hand: when aiming, the left hand rolls out to the left of the handguard (thumb over,
## C-clamp style) and the elbow drops, so the glove peeks out beside the gun instead of hiding behind it
## and the forearm angles up from the bottom-left instead of jutting out flat like a pole.
const POLE_L_HIP := Vector3(-0.45, -0.45, 0.1)
const POLE_L_ADS := Vector3(-0.2, -0.95, 0.05)
const ADS_SUPPORT_SHIFT := Vector3(-0.045, -0.012, 0.02)   ## gun space: left, a touch lower, slightly back
const ADS_SUPPORT_ROLL := 0.55                              ## rad about the barrel: palm turns in on the left side
var two_handed := false
var support_rest := Transform3D.IDENTITY
var ads_k := 0.0

func _init() -> void:
	name = "FpsArms"
	var scn: Node3D = load("res://assets/models/fps_arms.glb").instantiate()
	scn.scale = Vector3.ONE * SCALE
	scn.position = SHOULDER_POS   # head bone sits ~at the eye; shoulders a little behind/below
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
		# v7.3: the palm (not the wrist) sits under the fore-end, palm up, fingers wrapping across to the
		# far side and the index finger pointing down the barrel. The wrist basis is built straight from
		# the rig's hand axes (fingers +Y, palm +X, index side +Z in wrist space).
		var b := support_basis()
		target_l.basis = b
		target_l.position = support_wrist(fore, b)
		support_rest = target_l.transform
		hands.wrist_offset[1] = Basis.IDENTITY
	else:   # pistol: support hand cups the firing hand
		target_l.position = grip + Vector3(-0.04, 0.035, 0.045)
		target_l.rotation = Vector3(-0.25, 0.0, 0.0)
		hands.wrist_offset[1] = Basis.from_euler(Vector3(1.57, 0.0, 0.0))
	if is_inside_tree():
		ik.set_target_node(0, ik.get_path_to(target_r)); ik.set_target_node(1, ik.get_path_to(target_l))
	hands.curl = [0.9, 0.75 if two_handed else 0.85]
	self.two_handed = two_handed
	set_ads(ads_k)

## Blend the support hand between the hip grip and the ADS C-clamp (k = 0..1).
func set_ads(k: float) -> void:
	ads_k = clampf(k, 0.0, 1.0)
	pole_l.position = POLE_L_HIP.lerp(POLE_L_ADS, ads_k)
	if not two_handed: return
	target_l.transform = ads_support(support_rest, ads_k)

static func ads_support(rest: Transform3D, k: float) -> Transform3D:
	var t := rest
	t.basis = Basis(Vector3.BACK, ADS_SUPPORT_ROLL * k) * rest.basis
	t.origin = rest.origin + ADS_SUPPORT_SHIFT * k
	return t

## Wrist basis for the support hand: X = palm normal, Y = fingers, Z = index side.
static func support_basis() -> Basis:
	var n := SUPPORT_PALM.normalized()
	var f := (SUPPORT_FINGERS - n * SUPPORT_FINGERS.dot(n)).normalized()
	return Basis(n, f, n.cross(f))

## Wrist position that puts the palm centre just under `fore` (the fore-end underside point).
static func support_wrist(fore: Vector3, b: Basis) -> Vector3:
	return fore - b.y * PALM_FROM_WRIST - b.x * PALM_GAP
