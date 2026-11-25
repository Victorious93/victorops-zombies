extends GutTest
## v10.1 graphics pass (dusk pass): the tuning and curves in DuskLook. Purely cosmetic rules, but they
## carry readability and mobile-cost promises, so they are pinned here.

func _lum(c: Color) -> float: return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func test_sky_is_darker_overhead_than_at_the_horizon() -> void:
	assert_lt(_lum(DuskLook.SKY_TOP), _lum(DuskLook.SKY_HORIZON))
	assert_lt(_lum(DuskLook.GROUND_BOTTOM), _lum(DuskLook.GROUND_HORIZON))
	assert_gt(DuskLook.SKY_TOP.b, DuskLook.SKY_TOP.r, "overhead stays cool blue")

func test_horizon_band_is_dusky_not_orange() -> void:
	# warm but desaturated: red may lead, but green and blue stay close behind
	var h := DuskLook.SKY_HORIZON
	assert_lt(h.r - h.b, 0.2)
	assert_lt(h.r - h.g, 0.2)

func test_fog_stays_a_haze() -> void:
	assert_gt(DuskLook.FOG_DENSITY, 0.008, "thicker than v10")
	assert_lt(DuskLook.FOG_DENSITY_LATE, 0.03, "late rounds stay readable")
	assert_almost_eq(DuskLook.fog_density(0.0), DuskLook.FOG_DENSITY, 0.0001)
	assert_almost_eq(DuskLook.fog_density(1.0), DuskLook.FOG_DENSITY_LATE, 0.0001)
	assert_almost_eq(DuskLook.fog_density(5.0), DuskLook.FOG_DENSITY_LATE, 0.0001, "clamped")
	assert_gt(DuskLook.fog_density(0.5), DuskLook.FOG_DENSITY)

func test_ambient_keeps_readability_floor() -> void:
	assert_gte(DuskLook.AMBIENT_SCALE, 0.9)
	assert_gt(_lum(DuskLook.AMBIENT_COLOR), 0.3)

func test_puddles_are_deterministic_and_outdoors() -> void:
	var a := DuskLook.puddle_spots(1010, DuskLook.PUDDLE_COUNT, FacilityMap.ROOFED)
	var b := DuskLook.puddle_spots(1010, DuskLook.PUDDLE_COUNT, FacilityMap.ROOFED)
	assert_eq(a, b)
	assert_eq(a.size(), DuskLook.PUDDLE_COUNT)
	for sp in a:
		var p := Vector2(sp[0], sp[1])
		var inside := false
		for z in DuskLook.PUDDLE_ZONES: inside = inside or (z as Rect2).has_point(p)
		assert_true(inside, str(p))
		for r in FacilityMap.ROOFED: assert_false((r as Rect2).has_point(p), "no puddle under a roof %s" % p)
		assert_true(Facility.area_at(p.x, p.y) in ["generator", "yard", "pump"], "%s is %s" % [p, Facility.area_at(p.x, p.y)])

func test_puddles_do_not_overlap() -> void:
	var a := DuskLook.puddle_spots(7, DuskLook.PUDDLE_COUNT, FacilityMap.ROOFED)
	for i in a.size():
		for j in range(i + 1, a.size()):
			assert_gte(Vector2(a[i][0], a[i][1]).distance_to(Vector2(a[j][0], a[j][1])), 1.6)

func test_wet_surfaces_are_glossier_but_not_mirrors() -> void:
	assert_lt(DuskLook.WET_ROUGHNESS, 1.0)
	assert_gt(DuskLook.WET_ROUGHNESS, 0.5)
	assert_lt(DuskLook.PUDDLE_ROUGHNESS, 0.15)

func test_power_burst_spikes_then_dies() -> void:
	assert_almost_eq(DuskLook.power_burst(0.0), DuskLook.POWER_BURST_ENERGY, 0.001)
	assert_lt(DuskLook.power_burst(0.5), DuskLook.power_burst(0.1))
	assert_eq(DuskLook.power_burst(DuskLook.POWER_BURST_TIME), 0.0)
	assert_eq(DuskLook.power_burst(-0.1), 0.0)

func test_shockwave_rolls_past_the_danger_ring_and_fades() -> void:
	var r := ZombieTypes.SLAM_RADIUS
	assert_almost_eq(DuskLook.shock_radius(0.0, r), r * DuskLook.SHOCK_START, 0.001)
	assert_almost_eq(DuskLook.shock_radius(DuskLook.SHOCK_TIME, r), r * DuskLook.SHOCK_END, 0.001)
	assert_gt(DuskLook.SHOCK_END, 1.0, "the wave's edge passes the ring so the reach reads")
	var prev := -1.0
	for i in 11:
		var v := DuskLook.shock_radius(DuskLook.SHOCK_TIME * i / 10.0, r)
		assert_gte(v, prev); prev = v
	assert_gt(DuskLook.shock_alpha(0.0), 0.5)
	assert_eq(DuskLook.shock_alpha(DuskLook.SHOCK_TIME), 0.0)

func test_round_transition_curves() -> void:
	assert_eq(DuskLook.round_in_alpha(-0.1), 0.0)
	assert_almost_eq(DuskLook.round_in_alpha(0.08), 0.75, 0.001)
	assert_lt(DuskLook.round_in_alpha(1.0), DuskLook.round_in_alpha(0.2))
	assert_eq(DuskLook.round_in_alpha(DuskLook.ROUND_IN_TIME), 0.0)
	for i in 31:
		assert_lte(DuskLook.round_out_alpha(DuskLook.ROUND_OUT_TIME * i / 30.0), 0.45 + 0.0001, "the breather never blacks out the screen")
	assert_almost_eq(DuskLook.round_out_alpha(DuskLook.ROUND_OUT_TIME / 2.0), 0.45, 0.001)
	assert_eq(DuskLook.round_out_alpha(DuskLook.ROUND_OUT_TIME), 0.0)
	assert_lt(DuskLook.ROUND_OUT_TIME, Rounds.INTERMISSION, "fades out before the next round")
