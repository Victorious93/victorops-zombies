extends GutTest
## v7.9: perk-drink animation, power-on wave + white-out flash.

func test_drink_pose_lowers_gun_and_raises_bottle():
	var start: Array = Viewmodel.drink_pose(0.0)
	var mid: Array = Viewmodel.drink_pose(0.5)
	var done: Array = Viewmodel.drink_pose(1.0)
	assert_almost_eq(float(start[2]), 0.0, 1e-4, "gun starts in place")
	assert_gt(float(mid[2]), 0.9, "gun is out of the way mid-drink")
	assert_almost_eq(float(done[2]), 0.0, 1e-4, "gun returns")
	assert_gt(mid[0].y, start[0].y + 0.15, "bottle comes up to the mouth")

func test_drink_tips_bottle_back_then_levels():
	assert_gt(Viewmodel.drink_pose(0.58)[1].x, 1.0, "tipped back to drink")
	assert_lt(Viewmodel.drink_pose(0.9)[1].x, 0.3, "levelled before dropping away")

func test_drink_tints_bottle_and_blocks_until_done():
	var vm := Viewmodel.new(); add_child_autofree(vm); vm.setup(Color.GRAY)
	add_child_autofree(vm.bottle)
	vm.drink(Perks.ALL["fleetfoot"].color)
	assert_true(vm.drinking())
	assert_almost_eq(vm.bottle_mat.albedo_color.b, 1.0, 1e-4, "bottle takes the perk colour")
	for i in 10: vm.tick(Viewmodel.DRINK_TIME / 10.0 + 0.001, false, 0.0, false, -1.0)
	assert_false(vm.drinking())
	assert_false(vm.bottle.visible)

func test_cascade_delay_grows_with_distance_and_caps():
	assert_almost_eq(FacilityMap.cascade_delay(0.0), 0.0, 1e-5)
	assert_gt(FacilityMap.cascade_delay(20.0), FacilityMap.cascade_delay(5.0))
	assert_lte(FacilityMap.cascade_delay(500.0), FacilityMap.CASCADE_MAX)

func test_sputter_is_on_off_on():
	var s: Array = FacilityMap.SPUTTER
	for i in range(1, s.size()): assert_gt(float(s[i]), float(s[i - 1]))

func test_power_flash_fades_and_never_whites_out():
	assert_lt(Hud.power_flash_alpha(1.0), 0.6, "HUD stays readable")
	assert_gt(Hud.power_flash_alpha(1.0), 0.4, "clearly a flash")
	assert_lt(Hud.power_flash_alpha(0.3), Hud.power_flash_alpha(0.8))
	assert_almost_eq(Hud.power_flash_alpha(0.0), 0.0, 1e-5)
