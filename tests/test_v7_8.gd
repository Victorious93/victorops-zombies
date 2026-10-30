extends GutTest
## v7.8: brighter floor light pools, ADS support-hand C-clamp, Mystery Crate reveal drama.

func test_light_pools_bright_but_below_white():
	assert_gt(FacilityMap.POOL_STRENGTH, 0.8, "clearly visible")
	var c := FacilityMap.pool_material(Color(1, 0.9, 0.75)).albedo_color
	assert_lt(maxf(c.r, maxf(c.g, c.b)), 1.0, "additive peak stays below white (no blow-out)")
	assert_gt(FacilityMap.POOL_FRACTION, 0.6)

func test_ads_support_moves_hand_left_and_rolls_it():
	var rest := Transform3D(FpsArms.support_basis(), Vector3(0, -0.04, -0.2))
	var hip := FpsArms.ads_support(rest, 0.0)
	var ads := FpsArms.ads_support(rest, 1.0)
	assert_almost_eq(hip.origin.distance_to(rest.origin), 0.0, 1e-5, "hip pose unchanged")
	assert_lt(ads.origin.x, rest.origin.x - 0.03, "ADS hand peeks out on the gun's left")
	assert_gt(ads.basis.x.angle_to(rest.basis.x), 0.4, "palm rolls in around the handguard")

func test_ads_elbow_drops():
	assert_lt(FpsArms.POLE_L_ADS.y, FpsArms.POLE_L_HIP.y - 0.3, "elbow hangs low in ADS: forearm rises from bottom-left")

func test_viewmodel_fill_moves_toward_eye_in_ads():
	assert_gt(Viewmodel.FILL_ADS.z, Viewmodel.FILL_HIP.z)

func _crate() -> CrateNode:
	var c := CrateNode.new(); add_child_autofree(c); c.build(); return c

func test_crate_beam_shows_while_rolling_and_hides_on_close():
	var c := _crate()
	assert_false(c.beam.visible)
	c.start("rifle"); assert_true(c.beam.visible)
	assert_eq(c.light.light_color, CrateNode.ROLL_COLOR)
	c.close(); assert_false(c.beam.visible); assert_eq(c.light.light_color, CrateNode.ROLL_COLOR)

func test_crate_reveal_flashes_gold():
	var c := _crate()
	c.start("rifle"); c.t = 0.01
	c._process(0.05)
	assert_eq(c.state, CrateNode.State.READY)
	assert_eq(c.light.light_color, CrateNode.REVEAL_COLOR)
	assert_gt(c.light.light_energy, 8.0, "reveal flash")
	assert_gt(c.display.scale.x, 1.2, "gun punches in")

func test_beam_texture_fades_upward():
	var t := CrateNode.beam_texture()
	assert_eq(t.gradient.colors[0], Color(0, 0, 0, 1))
