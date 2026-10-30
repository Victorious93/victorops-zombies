extends GutTest
## v7.11: round mix, power-up call-outs + flash, gibbing rules, last-zombie cue.

func test_round_mix_sting_leads() -> void:
	var m: Dictionary = Game.ROUND_MIX
	assert_gt(m.round_sting_v10, m.round_start_v6 + 8.0)
	assert_gt(m.ann_round_delay, 1.5)

func test_every_drop_has_callout_audio() -> void:
	for id in PowerUps.ALL:
		assert_true(Game.PICKUP_CALLOUTS.has(id), id)
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % Game.PICKUP_CALLOUTS[id]), id)
	assert_true(ResourceLoader.exists("res://audio/pu_grab_v11.wav"))
	assert_true(ResourceLoader.exists("res://audio/last_zombie_v11.wav"))

func test_pickup_flash_curve() -> void:
	assert_almost_eq(Hud.pickup_alpha(1.0), 0.45, 0.001)
	assert_eq(Hud.pickup_alpha(0.0), 0.0)
	assert_lt(Hud.pickup_alpha(0.5), Hud.pickup_alpha(0.9))

func test_gib_explosive_always_takes_something() -> void:
	for i in 20:
		var r := i / 20.0
		assert_ne(Gib.decide("body", 0.05, true, r), "", "roll %f" % r)

func test_gib_light_hits_keep_limbs() -> void:
	assert_eq(Gib.decide("body", 0.1, false, 0.0), "")
	assert_eq(Gib.decide("legs", 0.2, false, 0.0), "")

func test_gib_heavy_hits() -> void:
	assert_eq(Gib.decide("legs", 0.5, false, 0.1), "legs")
	assert_eq(Gib.decide("body", 0.5, false, 0.1), "arm")
	assert_eq(Gib.decide("body", 0.5, false, 0.1, true), "")
	assert_eq(Gib.decide("legs", 0.5, false, 0.1, false, true), "")

func test_last_cue_once_per_round() -> void:
	assert_true(Game.wants_last_cue(0, 1, 3, 4))
	assert_false(Game.wants_last_cue(0, 1, 4, 4))
	assert_false(Game.wants_last_cue(2, 1, 3, 4))
	assert_false(Game.wants_last_cue(0, 2, 3, 4))
