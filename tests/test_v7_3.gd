extends GutTest

func test_support_basis_palm_up_fingers_across():
	var b := FpsArms.support_basis()
	assert_almost_eq(b.determinant(), 1.0, 0.001, "right-handed orthonormal")
	assert_gt(b.x.y, 0.8, "palm faces up into the fore-end")
	assert_gt(b.y.x, 0.6, "fingers wrap across under the gun")
	assert_lt(b.z.z, -0.4, "index finger points down the barrel")

func test_support_wrist_puts_palm_on_fore_point():
	var b := FpsArms.support_basis(); var fore := Vector3(0, 0.03, -0.15)
	var palm := FpsArms.support_wrist(fore, b) + b.y * FpsArms.PALM_FROM_WRIST
	assert_almost_eq(palm.distance_to(fore), FpsArms.PALM_GAP, 0.001)

func test_every_two_handed_gun_has_tuned_fore_grip():
	for id in Weapons.MODELS:
		var m: String = Weapons.MODELS[id]
		if ModelLib.GUN_LEN.get(m, 0.4) > 0.3:
			assert_true(Viewmodel.FORE_GRIP.has(m), "%s needs a measured fore-end grip" % m)

func test_support_hand_reaches_fore_end_on_every_gun():
	var cam := Camera3D.new(); add_child_autofree(cam)
	var vm := Viewmodel.new(); vm.setup(Color(0.4, 0.4, 0.45)); cam.add_child(vm)
	var fa := FpsArms.new(); cam.add_child(fa); vm.fps_arms = fa
	for id in ["smg", "rifle", "scatter", "lmg", "cannon", "nova"]:
		vm.set_weapon(Weapons.by_id(id))
		await wait_frames(3); await fa.skel.skeleton_updated
		var sk := fa.skel
		var w := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("wrist.l"))).origin
		assert_lt(w.distance_to(fa.target_l.global_position), 0.02, "%s: left wrist reaches its fore-end target" % id)
