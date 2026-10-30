extends GutTest
## v7.12: last-zombie rim, cue priority queue, crosshair points pop-ups, sprint ramp.

func test_last_rim_shader_and_pulse() -> void:
	assert_true(ResourceLoader.exists("res://shaders/last_rim.gdshader"))
	for i in 20:
		var p := Zombie.last_pulse(i * 0.07)
		assert_gte(p, 0.55 - 0.001); assert_lte(p, 1.0 + 0.001)

func test_voice_waits_for_round_sting() -> void:
	var q := CueQueue.new()
	var r1 := q.request(CueQueue.Prio.ROUND, 10.0, 3.8)
	assert_eq(r1.delay, 0.0)
	var r2 := q.request(CueQueue.Prio.VOICE, 10.5, 1.0, true)
	assert_almost_eq(r2.delay, 3.3 + CueQueue.GAP, 0.001)

func test_stinger_ducks_under_voice() -> void:
	var q := CueQueue.new()
	q.request(CueQueue.Prio.VOICE, 0.0, 1.5, true)
	var r := q.request(CueQueue.Prio.STINGER, 0.2, 0.9)
	assert_eq(r.delay, 0.0)
	assert_eq(r.db_offset, CueQueue.DUCK_DB)

func test_two_voices_queue_back_to_back() -> void:
	var q := CueQueue.new()
	q.request(CueQueue.Prio.VOICE, 0.0, 1.0, true)
	var r := q.request(CueQueue.Prio.VOICE, 0.1, 1.0, true)
	assert_almost_eq(r.delay, 0.9 + CueQueue.GAP, 0.001)

func test_free_slot_plays_now() -> void:
	var q := CueQueue.new()
	q.request(CueQueue.Prio.ROUND, 0.0, 1.0)
	var r := q.request(CueQueue.Prio.VOICE, 5.0, 1.0, true)
	assert_eq(r.delay, 0.0); assert_eq(r.db_offset, 0.0)

func test_points_pop_style() -> void:
	assert_gt(Hud.pop_size(100), Hud.pop_size(50)); assert_gt(Hud.pop_size(50), Hud.pop_size(10))
	assert_eq(Hud.pop_alpha(Hud.POP_LIFE), 0.0)
	assert_lt(Hud.pop_rise(0.8), Hud.pop_rise(0.1))

func test_sprint_ramp() -> void:
	assert_eq(Gait.ramp(Gait.Tier.WALK, 3, 999.0), Gait.Tier.WALK)
	assert_eq(Gait.ramp(Gait.Tier.WALK, 8, Gait.jog_after(8) + 0.1), Gait.Tier.JOG)
	assert_eq(Gait.ramp(Gait.Tier.JOG, 5, 999.0), Gait.Tier.JOG)
	assert_eq(Gait.ramp(Gait.Tier.JOG, 9, Gait.jog_after(9) + Gait.sprint_after(9)), Gait.Tier.SPRINT)
	assert_gt(Gait.lean(Gait.Tier.SPRINT), Gait.lean(Gait.Tier.JOG))
