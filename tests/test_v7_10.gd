extends GutTest
## v7.10: more ceiling lamps for the power wave, head-bone snap on headshots, round slam + sting, ground rise.

func test_extra_lamps_inside_building_and_many() -> void:
	assert_gte(FacilityMap.EXTRA_LAMPS.size(), 12)
	for q in FacilityMap.EXTRA_LAMPS:
		var inside_main: bool = q.x > -10 and q.x < 26 and q.y > -26 and q.y < 10
		var inside_pump: bool = q.x > 26 and q.x < 46 and q.y > 10 and q.y < 30
		assert_true(inside_main or inside_pump, "lamp %s inside a roofed room" % q)

func test_cascade_spreads_over_extra_lamps() -> void:
	var near := FacilityMap.cascade_delay(3.0)
	var far := FacilityMap.cascade_delay(25.0)
	assert_lt(near, far)

func test_head_snap_curve() -> void:
	assert_eq(HeadSnap.curve(-0.1), 0.0)
	assert_almost_eq(HeadSnap.curve(0.05), 1.0, 0.01)
	assert_lt(absf(HeadSnap.curve(HeadSnap.SNAP_TIME - 0.01)), 0.05)
	assert_eq(HeadSnap.curve(HeadSnap.SNAP_TIME + 0.1), 0.0)

func test_head_snap_trigger() -> void:
	var h := HeadSnap.new()
	h.snap(3.0)
	assert_eq(h.age, 0.0)
	assert_eq(h.side, 1.0)
	h.free()

func test_round_slam_curves() -> void:
	assert_gt(Hud.slam_scale(0.0), 2.5)
	assert_almost_eq(Hud.slam_scale(0.4), 1.0, 0.01)
	assert_eq(Hud.slam_alpha(Hud.SLAM_TIME), 0.0)
	assert_gt(Hud.slam_alpha(0.8), 0.9)
	assert_gt(Hud.slam_bar(0.5), 0.9)

func test_round_sting_exists() -> void:
	assert_true(ResourceLoader.exists("res://audio/round_sting_v10.wav"))

func test_ground_rise_offset() -> void:
	assert_almost_eq(Zombie.rise_offset(0.0), -1.8, 0.01)
	assert_almost_eq(Zombie.rise_offset(1.0), 0.0, 0.01)
	var prev := -2.0
	for i in 11:
		var y := Zombie.rise_offset(i / 10.0)
		assert_gte(y, prev - 0.001); prev = y
