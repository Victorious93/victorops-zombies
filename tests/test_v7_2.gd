extends GutTest

func test_flashlight_never_shadows():
	for compat in [true, false]:
		assert_false(Game.flashlight_casts_shadows(true, true, compat), "v7.3: no flashlight shadows on any renderer")

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

func test_zombie_stride_rate_tracks_speed():
	assert_almost_eq(Zombie.stride_rate("Walk", 1.1), 1.0, 0.001)
	assert_lt(Zombie.stride_rate("Run", 1.0), Zombie.stride_rate("Run", 3.0))
	assert_eq(Zombie.stride_rate("Walk", 0.0), 0.6, "never freezes mid-stride")
	assert_eq(Zombie.stride_rate("Walk", 9.0), 1.6)
