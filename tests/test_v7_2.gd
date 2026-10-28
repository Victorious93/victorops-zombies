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
