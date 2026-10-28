extends GutTest

func test_flashlight_never_shadows_in_compat():
	assert_false(Game.flashlight_casts_shadows(true, true, true), "shared-world overlay + shadowed spot blows out GL Compatibility")
	assert_true(Game.flashlight_casts_shadows(true, true, false))

func test_support_hand_reachable():
	# left shoulder rest ~(-0.19, 0, 0) relative to the rig root; arm ~0.52 m. Keep the support target well inside reach.
	var sh := FpsArms.SHOULDER_POS + Vector3(-0.19, 0.0, 0.0)
	var tl := Vector3(0.1, -0.1275, -0.43) + FpsArms.SUPPORT_OFFSET - Vector3(-0.03, 0.02, 0.0)
	assert_lt(sh.distance_to(tl), 0.5, "support hand must not need a fully straight arm")
	assert_gt(FpsArms.SUPPORT_ROLL, 0.0)

func test_show_fps_setting_roundtrip():
	var s := GameSettings.new()
	assert_false(s.show_fps, "off by default")
	s.show_fps = true
	var t := GameSettings.new(); t.from_dict(s.to_dict())
	assert_true(t.show_fps)

func test_perf_text_flags_budget():
	assert_eq(Hud.perf_text(60, 120), "60 fps · 120 dc")
	assert_true(Hud.perf_text(30, Game.DRAW_CALL_BUDGET + 1).ends_with("!"))

func test_multimesh_helper_single_instance_node():
	var xs: Array[Transform3D] = [Transform3D(), Transform3D(Basis(), Vector3(1, 0, 0))]
	var mmi := Scenery.multimesh(BoxMesh.new(), xs, "T", 20.0)
	assert_eq(mmi.multimesh.instance_count, 2)
	assert_eq(mmi.visibility_range_end, 20.0)
	assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mmi.free()

func test_area_moods_are_distinct_and_cheap():
	assert_eq(Scenery.AREA_MOODS.size(), 4)
	for a in Scenery.AREA_MOODS: assert_lt(a[3], 10.0, "range-limited")

func test_reload_pose_starts_and_ends_at_rest():
	for t in [0.0, 1.0]:
		var r := Viewmodel.reload_pose(t)
		assert_almost_eq((r[0] as Vector3).length(), 0.0, 0.001); assert_almost_eq((r[1] as Vector3).length(), 0.0, 0.001)
	var mid := Viewmodel.reload_pose(0.55)
	assert_gt((mid[1] as Vector3).z, 0.5, "tilted mid-reload")

func test_swap_pose_drops_then_settles_with_overshoot():
	assert_eq(Viewmodel.swap_pose(0.0)[0], Vector3.ZERO)
	assert_almost_eq((Viewmodel.swap_pose(0.7)[0] as Vector3).y, -0.25, 0.01, "fully down at 30%")
	var mins := 0.0
	for i in 20: mins = maxf(mins, (Viewmodel.swap_pose(0.3 - i * 0.015)[0] as Vector3).y)
	assert_gt(mins, 0.0, "overshoots above rest before settling")
