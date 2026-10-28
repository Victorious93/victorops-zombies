extends GutTest
## v6: gunfeel, zombie gaits, hit reactions, touch layout, ADS snap, new audio.

func test_ads_zoom_varies_by_weapon():
	assert_lt(GunFeel.ads_fov("cannon"), GunFeel.ads_fov("rifle"))
	assert_lt(GunFeel.ads_fov("rifle"), GunFeel.ads_fov("scatter"))
	for id in Weapons.ALL_IDS:
		var f := GunFeel.ads_fov(id)
		assert_between(f, 30.0, 70.0, id)
		assert_lt(GunFeel.ads_fov(id, true), f + 0.001)

func test_ads_sens_matches_zoom():
	assert_lt(GunFeel.ads_sens("cannon"), GunFeel.ads_sens("smg"))
	assert_between(GunFeel.ads_sens("rifle"), 0.2, 1.0)

func test_camera_kick_heavier_and_ads_softer():
	assert_gt(GunFeel.camera_kick(2.0, 1.6, false), GunFeel.camera_kick(2.0, 0.6, false))
	assert_lt(GunFeel.camera_kick(2.0, 1.0, true), GunFeel.camera_kick(2.0, 1.0, false))
	assert_lt(GunFeel.camera_kick(2.0, 1.0, false, true), GunFeel.camera_kick(2.0, 1.0, false))
	assert_gt(GunFeel.recovery_rate(0.6), GunFeel.recovery_rate(1.6))

func test_hitmarker_kinds_and_colors():
	assert_eq(GunFeel.hitmarker(true, true), GunFeel.Mark.HEAD_KILL)
	assert_eq(GunFeel.hitmarker(true, false), GunFeel.Mark.KILL)
	assert_eq(GunFeel.hitmarker(false, false, true), GunFeel.Mark.ARMOR)
	assert_eq(GunFeel.hitmarker(false, true), GunFeel.Mark.HEAD)
	assert_ne(GunFeel.hitmarker_color(GunFeel.Mark.HEAD), GunFeel.hitmarker_color(GunFeel.Mark.BODY))

func test_impact_sounds():
	assert_eq(GunFeel.impact_sound(true, false, false), "impact_flesh")
	assert_eq(GunFeel.impact_sound(true, true, false), "impact_metal")
	assert_eq(GunFeel.impact_sound(false, false, false), "impact_wall")

func test_gait_mix_sums_and_ramps():
	for r in range(1, 40):
		var m := Gait.mix(r)
		assert_almost_eq(m[0] + m[1] + m[2], 1.0, 0.001, "round %d" % r)
	assert_eq(Gait.mix(1), [1.0, 0.0, 0.0])
	assert_eq(Gait.mix(4)[2], 0.0, "no sprinters before round 6")
	assert_gt(Gait.mix(4)[1], 0.0, "joggers by round 4")
	assert_gt(Gait.mix(12)[2], 0.5, "mostly sprinters late")

func test_gait_pick_and_speed():
	assert_eq(Gait.pick(1, 0.99), Gait.Tier.WALK)
	assert_eq(Gait.pick(20, 0.99), Gait.Tier.SPRINT)
	assert_lt(Gait.speed(Gait.Tier.WALK, 5), Gait.speed(Gait.Tier.JOG, 5))
	assert_lt(Gait.speed(Gait.Tier.JOG, 5), Gait.speed(Gait.Tier.SPRINT, 5))
	assert_gt(Gait.speed(Gait.Tier.SPRINT, 25), Gait.speed(Gait.Tier.SPRINT, 5))
	assert_lt(Gait.speed(Gait.Tier.SPRINT, 99), 3.6 * 1.16)

func test_hit_reactions():
	assert_eq(HitReact.classify("head", 0.3, 0), HitReact.Kind.HEAD_SNAP)
	assert_eq(HitReact.classify("leg", 0.3, 0), HitReact.Kind.STUMBLE)
	assert_eq(HitReact.classify("torso", 0.1, 0.8), HitReact.Kind.TWIST_RIGHT)
	assert_eq(HitReact.classify("torso", 0.1, -0.8), HitReact.Kind.TWIST_LEFT)
	assert_eq(HitReact.classify("torso", 0.8, 0), HitReact.Kind.KNOCKBACK)
	assert_eq(HitReact.classify("torso", 0.01, 0), HitReact.Kind.NONE)
	assert_gt(HitReact.stagger_time(HitReact.Kind.STUMBLE), HitReact.stagger_time(HitReact.Kind.FLINCH))
	assert_ne(HitReact.pose(HitReact.Kind.TWIST_LEFT).y, HitReact.pose(HitReact.Kind.TWIST_RIGHT).y)

func test_touch_layout_no_overlaps_on_common_screens():
	for s in [Vector2(1280, 720), Vector2(2400, 1080), Vector2(1024, 768), Vector2(2960, 1440)]:
		for fs in [1.0, 1.3, 1.5]:
			var b := TouchLayout.buttons(s, fs)
			assert_eq(TouchLayout.overlaps(b), [], "%s fs=%s" % [s, fs])
			for n in b:
				var c: Vector2 = b[n][0]; var r: float = b[n][1]
				assert_true(c.x - r >= 0 and c.x + r <= s.x and c.y - r >= 0 and c.y + r <= s.y, "%s on screen %s" % [n, s])

func test_touch_buttons_within_thumb_reach_of_fire():
	var b := TouchLayout.buttons(Vector2(1280, 720))
	for n in ["ads", "reload", "use", "swap"]:
		assert_lt(b[n][0].distance_to(b["fire"][0]), 200.0, n)

func test_ads_snap():
	var o := Vector3.ZERO; var f := Vector3(0, 0, -1)
	var s := AimAssist.ads_snap(o, f, [Vector3(1.5, 0, -10)])
	assert_lt(s.x, 0.0, "target on the right means turn right (negative yaw)")
	assert_eq(AimAssist.ads_snap(o, f, [Vector3(10, 0, -1)]), Vector2.ZERO, "outside cone")
	assert_eq(AimAssist.ads_snap(o, f, [Vector3(0, 0, -40)]), Vector2.ZERO, "out of range")

func test_v6_audio_present():
	for n in ["impact_flesh", "impact_metal", "impact_wall", "ricochet", "mag_out_v6", "mag_in_v6", "bolt_v6",
			"round_start_v6", "round_end_v6", "door_open_v6", "plank_pull_v6", "climb_v6", "hit_tick_v6"]:
		assert_true(FileAccess.file_exists("res://audio/%s.wav" % n), n)
