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
	var cam := Camera3D.new(); add_child(cam)
	var vm := Viewmodel.new(); vm.setup(Color(0.4, 0.4, 0.45)); cam.add_child(vm)
	var fa := FpsArms.new(); cam.add_child(fa); vm.fps_arms = fa
	for id in ["smg", "rifle", "scatter", "lmg", "cannon", "nova"]:
		vm.set_weapon(Weapons.by_id(id))
		await wait_physics_frames(3); await fa.skel.skeleton_updated
		var sk := fa.skel
		var w := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("wrist.l"))).origin
		assert_lt(w.distance_to(fa.target_l.global_position), 0.02, "%s: left wrist reaches its fore-end target" % id)
	# v7.4: free only after leaving the skeleton_updated emission (was autofree => flaky 'freed while a signal is being emitted')
	await wait_process_frames(1); cam.queue_free(); await wait_process_frames(2)

func test_perk_machine_glow_toned_down():
	assert_lt(FacilityMap.MACHINE_PANEL_ON, 1.5, "panel must not clip to white at close range")
	assert_lt(FacilityMap.MACHINE_NEON_ON, 2.0)
	assert_lt(FacilityMap.MACHINE_LIGHT_ON, 1.2)

func test_decal_xform_lies_on_surface():
	var t := Scenery.decal_xform(Vector3(1, 0, 2), 2.0, Vector3.UP, 0.7)
	assert_almost_eq(t.basis.z.normalized().dot(Vector3.UP), 1.0, 0.001, "quad faces up off the floor")
	assert_almost_eq(t.origin.y, Scenery.DECAL_LIFT, 0.0001)
	var w := Scenery.decal_xform(Vector3(-9.75, 1, 0), 1.0, Vector3.RIGHT, 0.0)
	assert_almost_eq(w.basis.z.normalized().dot(Vector3.RIGHT), 1.0, 0.001, "wall quad faces into the room")

func test_decal_zones_cover_every_area_with_all_kinds():
	assert_eq(Scenery.DECAL_ZONES.size(), 6)
	for z in Scenery.DECAL_ZONES:
		for i in [1, 2, 3]: assert_gt(int(z[i]), 0)

func test_decal_material_is_alpha_blended():
	var m := Scenery.decal_material("blood")
	assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_not_null(m.albedo_texture)

func test_area_beds_exist_and_map_to_areas() -> void:
	assert_eq(Sfx.bed_for(Vector3(0, 0, -18)), "bed_generator")
	assert_eq(Sfx.bed_for(Vector3(36, 0, 20)), "bed_damp")
	assert_eq(Sfx.bed_for(Vector3(0, 0, 0)), "")
	for b in Sfx.AREA_BEDS: assert_true(ResourceLoader.exists("res://audio/%s.wav" % b[1]), b[1])
