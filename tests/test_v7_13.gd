extends GutTest
## v7.13: Upgrade Paks, Backpack gadgets, runner gait clips, Reaper tune, bot line-of-sight.

func test_pak_starts_at_base_10s() -> void:
	var p := UpgradePaks.new(); p.activate("overdrive")
	assert_true(p.active()); assert_almost_eq(p.time_left, 10.0, 0.001)
	assert_almost_eq(p.damage_mult(), 1.6, 0.001)

func test_pak_kills_extend() -> void:
	var p := UpgradePaks.new(); p.activate("hyperloop")
	assert_almost_eq(p.on_kill(false), 1.5, 0.001)
	assert_almost_eq(p.on_kill(true), 2.5, 0.001)
	assert_almost_eq(p.time_left, 14.0, 0.001)

func test_pak_hard_cap_45s() -> void:
	var p := UpgradePaks.new(); p.activate("quickstep")
	for i in 100: p.on_kill(true)
	assert_almost_eq(p.time_left, 45.0, 0.001)
	assert_eq(p.on_kill(false), 0.0, "no time past the cap")
	p.update(5.0); p.on_kill(true)
	assert_almost_eq(p.time_left, 40.0, 0.001, "cap is total lifetime, not a refillable bar")

func test_pak_expiry_removes_effect() -> void:
	var p := UpgradePaks.new(); p.activate("bottomless")
	assert_true(p.infinite_ammo())
	p.update(7.5); assert_true(p.warning())
	assert_eq(p.update(3.0), "bottomless")
	assert_false(p.active()); assert_false(p.infinite_ammo())
	assert_eq(p.damage_mult(), 1.0); assert_eq(p.fire_mult(), 1.0); assert_eq(p.speed_mult(), 1.0)
	assert_eq(p.on_kill(true), 0.0)

func test_pak_one_at_a_time() -> void:
	var p := UpgradePaks.new(); p.activate("overdrive"); p.activate("quickstep")
	assert_eq(p.id, "quickstep"); assert_eq(p.damage_mult(), 1.0)
	assert_true(UpgradePaks.FIRE_MULT < 1.0, "hyperloop shortens the fire interval")

func test_pak_drop_pity() -> void:
	var p := UpgradePaks.new(); var rng := RandomNumberGenerator.new(); rng.seed = 3
	var got := false
	for i in UpgradePaks.PITY_KILLS: if p.roll(rng) != "": got = true
	assert_true(got)

func test_backpack_slots_stack_and_full() -> void:
	var b := Backpack.new()
	assert_eq(b.add("sentry"), 0); assert_eq(b.add("sentry"), 0)
	assert_eq(b.add("sentry"), 1, "stack of 2 spills into the next slot")
	assert_eq(b.add("aegis"), 2)
	assert_eq(b.add("pulse"), -1, "bag full")
	assert_eq(b.add("aegis"), 2); assert_eq(b.add("aegis"), -1)
	assert_true(b.is_full_for("pulse"))

func test_backpack_use_consumes() -> void:
	var b := Backpack.new(); b.add("pulse"); b.add("pulse")
	assert_eq(b.use(0), "pulse"); assert_eq(b.count("pulse"), 1)
	assert_eq(b.use(0), "pulse"); assert_eq(b.use(0), ""); assert_eq(b.first_filled(), -1)

func test_sentry_expires() -> void:
	var s := Backpack.Sentry.new(); var shots := 0
	for i in 60 * 25:
		if s.update(1.0 / 60.0): s.fire(); shots += 1
	assert_false(s.alive())
	assert_true(shots <= Backpack.SENTRY_AMMO)
	var s2 := Backpack.Sentry.new(); s2.update(Backpack.SENTRY_LIFE + 0.1)
	assert_false(s2.alive(), "times out at ~20 s even with ammo left")

func test_aegis_blocks_damage() -> void:
	var a := Backpack.Aegis.new()
	assert_eq(a.absorb(40.0), 40.0, "down: everything gets through")
	a.start()
	for i in Backpack.AEGIS_HITS: assert_eq(a.absorb(40.0), 0.0)
	assert_false(a.up()); assert_eq(a.absorb(40.0), 40.0)
	var b := Backpack.Aegis.new(); b.start(); assert_true(b.update(Backpack.AEGIS_TIME + 0.1))

func test_emp_stuns_in_range_only() -> void:
	var c := Vector3.ZERO
	assert_true(Backpack.in_pulse(c, Vector3(4, 1, 4)))
	assert_false(Backpack.in_pulse(c, Vector3(7, 0, 0)))
	var z := Zombie.new(); z.variant = "zombie_a"; autofree(z)
	z.emp_stun(Backpack.PULSE_STUN, Backpack.PULSE_SLOW)
	assert_true(z.stagger_t >= Backpack.PULSE_STUN - 0.01, "stunned (no swings)")
	assert_true(z.slow_t >= Backpack.PULSE_SLOW - 0.01, "then slowed")

func test_gadget_sounds_and_names_exist() -> void:
	for n in ["pak_on", "pak_extend", "pak_warn", "pak_off", "gadget_pickup", "bag_full", "turret_deploy", "turret_shot", "turret_off", "shield_up", "shield_hit", "shield_down", "emp_burst"]:
		assert_true(ResourceLoader.exists("res://audio/%s_v13.wav" % n), n)
	assert_eq(Backpack.GADGETS.size(), 3); assert_eq(UpgradePaks.ALL.size(), 4)
	assert_true(TouchLayout.ORDER.has("gadget"))

func test_runner_clip_fallbacks() -> void:
	assert_eq(Gait.clip_for(Gait.Tier.SPRINT, {"Run_Arms": true, "Run": true}), "Run_Arms")
	assert_eq(Gait.clip_for(Gait.Tier.SPRINT, {"Run": true}), "Run")
	assert_eq(Gait.clip_for(Gait.Tier.JOG, {"Run": true}), "Run")
	assert_eq(Gait.clip_for(Gait.Tier.SPRINT, {}), "Walk")

func test_reaper_tuned_below_wonder_tier_spike() -> void:
	var r := Weapons.make("reaper")
	var dps := r.damage / r.fire_interval
	assert_eq(r.damage, 105)
	assert_true(dps < 2000.0, "Hive Reaper body DPS ~1909 (was ~2364)")
