extends GutTest
## v7.7: brighter light pools, window repair slam feel.

func test_light_pools_are_visible_but_soft():
	assert_gt(FacilityMap.POOL_STRENGTH, 0.45, "clearly visible")
	assert_lt(FacilityMap.POOL_STRENGTH, 0.8, "not blown out")
	var c := FacilityMap.pool_material(Color(1, 0.9, 0.75)).albedo_color
	assert_lt(c.r, 1.0, "additive glow stays below white")

func _window() -> WindowBarricade:
	var w := WindowBarricade.new(); add_child_autofree(w); w.build(1.6)
	return w

func test_rest_transforms_recorded_per_plank():
	var w := _window()
	assert_eq(w.rest.size(), w.planks.size())

func test_slam_plank_starts_off_frame_and_settles():
	var w := _window()
	w.bar.damage(w.bar.max_hp()); w.refresh()
	var hit := w.slam_plank(0)
	var p: MeshInstance3D = w.planks[0]
	assert_true(p.visible)
	assert_gt(p.position.distance_to(w.rest[0].origin), 0.5, "plank starts in the player's hands")
	assert_almost_eq(hit.distance_to(w.to_global(w.rest[0].origin)), 0.0, 0.001)
	await wait_seconds(WindowBarricade.SLAM_TIME + 0.2)
	assert_almost_eq(p.position.distance_to(w.rest[0].origin), 0.0, 0.01, "nailed back in place")

func test_slam_plank_out_of_range_is_safe():
	var w := _window()
	assert_eq(w.slam_plank(99), w.center())
