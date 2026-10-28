extends GutTest
## v7.1: pre-power lighting fix, glove tint, zombie readability.

func test_flashlight_shadow_only_after_power():
	assert_false(Game.flashlight_casts_shadows(true, false), "lone shadowed spot before power blew out GL Compatibility")
	assert_true(Game.flashlight_casts_shadows(true, true))
	assert_false(Game.flashlight_casts_shadows(false, true))

func test_zombie_skins_readable():
	var src := StandardMaterial3D.new()
	for ty in ZombieTypes.ALL:
		for i in Zombie.SKINS.size():
			var m := Zombie._skin_mat(src, ty, i)
			assert_true(m.emission_enabled, "%s has self-fill" % ty)
			if ty in ["walker", "sprinter", "bloater", "brute"]:
				assert_gt(m.albedo_color.get_luminance(), 0.42, "%s skin %d bright enough" % [ty, i])
	var sp := Zombie._skin_mat(src, "sprinter", 0).albedo_color.get_luminance()
	assert_gt(sp, Zombie._skin_mat(src, "walker", 0).albedo_color.get_luminance() * 0.95, "sprinter not darker than walker")

func test_glove_tint_applies():
	var a := FpsArms.new()
	assert_null(a.mat.albedo_texture, "flat dyed fabric, no skin map")
	assert_eq(a.mat.albedo_color, FpsArms.GLOVE_COLOR)
	assert_lt(a.mat.albedo_color.get_luminance(), 0.3, "dark glove, not bare skin")
	a.free()

func test_wrist_offset_wraps_grip():
	var h := HandPose.new()
	for b in h.wrist_offset: assert_almost_eq((b as Basis).get_euler().x, 1.57, 0.05)
	h.free()

func test_bounce_fill_tracks_power():
	assert_lt(FacilityMap.BOUNCE_OFF, FacilityMap.BOUNCE_ON)
	assert_lt(FacilityMap.BOUNCE_ON, 0.6, "fill stays subtle")

func test_sfx_voice_cap_and_limiter():
	var s := Sfx.new()
	for i in Sfx.MAX_VOICES: assert_true(s._claim("shot"))
	assert_false(s._claim("shot"), "capped")
	s._release("shot"); assert_true(s._claim("shot"))
	assert_eq(Sfx.vary(1.0, "music"), 1.0)
	var v := Sfx.vary(1.0, "shot"); assert_between(v, 0.96, 1.04)
	Sfx.ensure_limiter(); Sfx.ensure_limiter()
	var n := 0
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter: n += 1
	assert_eq(n, 1, "one limiter on Master")
	s.free()
