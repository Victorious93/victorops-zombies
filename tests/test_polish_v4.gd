extends GutTest
## Single-player polish v4: stuck watchdog, weapon weight, aim assist / look curve, mobile settings.

func test_progress_watch_sidesteps_then_respawns():
	var w := ProgressWatch.new()
	assert_eq(w.update(10.0, 0.1), "")
	var got := []
	for i in 70:
		var r := w.update(10.0, 0.1)
		if r != "": got.append([r, i])
	assert_eq(got.size(), 2)
	assert_eq(got[0][0], "sidestep"); assert_eq(got[1][0], "respawn")

func test_progress_watch_progress_resets_timer():
	var w := ProgressWatch.new()
	var d := 20.0
	for i in 200:
		d -= 0.1  # steady progress
		assert_eq(w.update(d, 0.1), "")

func test_heavy_guns_kick_harder_and_move_slower():
	var light := Weapons.make("smg"); var mid := Weapons.make("rifle"); var heavy := Weapons.make("lmg")
	assert_lt(light.weight, mid.weight); assert_lt(mid.weight, heavy.weight)
	assert_lt(light.kick_mult(), heavy.kick_mult())
	assert_gt(light.move_mult(), heavy.move_mult())
	assert_gt(heavy.move_mult(), 0.84)
	assert_almost_eq(heavy.upgraded_version().weight, heavy.weight, 0.001)

func test_first_shot_punch():
	var w := Weapons.make("rifle")
	assert_almost_eq(w.first_shot_mult(w.fire_interval), 1.0, 0.001)  # sustained fire: no bonus
	assert_almost_eq(w.first_shot_mult(2.0), 1.8, 0.001)               # after a pause: full punch

func test_aim_slowdown_near_target_only():
	var o := Vector3.ZERO; var f := Vector3.FORWARD
	assert_almost_eq(AimAssist.slowdown(o, f, [Vector3(0, 0, -10)]), AimAssist.SLOW_MIN, 0.01)
	assert_eq(AimAssist.slowdown(o, f, [Vector3(10, 0, -1)]), 1.0)
	assert_eq(AimAssist.slowdown(o, f, []), 1.0)

func test_auto_fire_on_target():
	var o := Vector3.ZERO; var f := Vector3.FORWARD
	assert_true(AimAssist.on_target(o, f, [Vector3(0.3, 0, -12)]))
	assert_false(AimAssist.on_target(o, f, [Vector3(1.0, 0, -12)]))
	assert_false(AimAssist.on_target(o, f, [Vector3(0, 0, 5)]))   # behind
	assert_false(AimAssist.on_target(o, f, [Vector3(0, 0, -60)]))  # out of range

func test_look_curve_precise_small_fast_large():
	var small := AimAssist.look_curve(Vector2(3, 0), 1.5)
	var big := AimAssist.look_curve(Vector2(40, 0), 1.5)
	assert_lt(small.x, 3.0); assert_gt(big.x, 40.0)
	assert_eq(AimAssist.look_curve(Vector2(7, 2), 1.0), Vector2(7, 2))

func test_stick_deadzone_and_curve():
	assert_eq(AimAssist.stick(Vector2(0.05, 0.05)), Vector2.ZERO)
	assert_almost_eq(AimAssist.stick(Vector2(0, -1)).length(), 1.0, 0.001)
	assert_lt(AimAssist.stick(Vector2(0.5, 0)).length(), 0.5)

func test_mobile_settings_round_trip_and_clamp():
	var s := GameSettings.new()
	s.auto_fire = true; s.gyro = "ads"; s.look_curve = 1.6; s.joystick = "fixed"; s.fire_size = 1.7
	var t := GameSettings.new(); t.from_dict(s.to_dict())
	assert_true(t.auto_fire); assert_eq(t.gyro, "ads"); assert_almost_eq(t.look_curve, 1.6, 0.001)
	assert_eq(t.joystick, "fixed"); assert_almost_eq(t.fire_size, 1.7, 0.001)
	t.from_dict({gyro = "bogus", look_curve = 9.0, joystick = "x", fire_size = 0.1})
	assert_eq(t.gyro, "off"); assert_eq(t.look_curve, 1.8); assert_eq(t.joystick, "floating"); assert_eq(t.fire_size, 1.0)
