extends GutTest
## Gameplay-feel pass: zombie scaling, economy, ammo reserve, power-ups, last stand.

func test_health_scaling_table():
	var want := [150, 250, 350, 450, 550, 650, 750, 850, 950]
	for i in want.size(): assert_eq(Rounds.zombie_health(i + 1), want[i], "round %d" % (i + 1))
	assert_eq(Rounds.zombie_health(10), 1045)   # x1.1 from here
	assert_eq(Rounds.zombie_health(11), 1149)
	for r in range(10, 40): assert_almost_eq(float(Rounds.zombie_health(r + 1)) / Rounds.zombie_health(r), 1.1, 0.01)

func test_round1_is_six_shamblers():
	assert_eq(Rounds.zombie_count(1), 6)
	for r in range(1, 5): assert_eq(Rounds.runner_chance(r), 0.0)
	assert_gt(Rounds.runner_chance(5), 0.0); assert_lt(Rounds.runner_chance(5), 1.0)
	assert_eq(Rounds.runner_chance(8), 1.0)
	assert_lt(Rounds.WALK_SPEED, 1.5); assert_gt(Rounds.RUN_SPEED, 3.0)
	assert_eq(Rounds.MAX_ALIVE, 24); assert_eq(Rounds.INTERMISSION, 10.0)

func test_two_pistol_body_shots_or_one_knife_kill_round1():
	var hp := Rounds.zombie_health(1)
	var pistol := Weapons.make("sidearm").damage
	assert_lt(pistol, hp); assert_gte(pistol * 2, hp)
	assert_gte(Equipment.KNIFE_DAMAGE, hp)

func test_zombie_downs_unperked_player_in_2_to_3_hits():
	var hits := ceili(100.0 / Zombie.SWIPE_DAMAGE)
	assert_between(hits, 2, 3)

func test_kill_payouts():
	var e := Economy.new(); e.points = 0
	e.on_hit(); assert_eq(e.points, 10)
	e.on_kill(); assert_eq(e.points, 70)
	e.on_kill(true); assert_eq(e.points, 170)
	e.on_kill(false, true); assert_eq(e.points, 300)

func test_double_pay_doubles_everything():
	var e := Economy.new(); e.points = 0; e.mult = 2
	e.on_hit(); e.on_kill(true); assert_eq(e.points, 220)

func test_repair_points_capped_per_round():
	var e := Economy.new(); e.points = 0
	var total := 0
	for i in 80: total += e.on_repair(1)
	assert_eq(e.points, Economy.REPAIR_CAP_PER_ROUND); assert_eq(total, Economy.REPAIR_CAP_PER_ROUND)
	assert_eq(e.on_repair(1), 0)
	e.on_round_start(); assert_eq(e.on_repair(1), 10)

func test_prices_in_band():
	for id in Facility.DOORS: assert_between(Facility.DOORS[id].cost, 750, 1250, id)
	for id in Weapons.WALL_PRICES:
		assert_between(Weapons.WALL_PRICES[id], 500, 1500, id)
		assert_eq(Weapons.ammo_price(id), Weapons.WALL_PRICES[id] / 2)
	assert_eq(MysteryCrate.COST, 950)
	for id in Perks.ALL: assert_between(Perks.ALL[id].cost, 2000, 3000, id)
	assert_eq(OverchargeForge.new().cost, 5000)

func test_ammo_reserve_runs_dry_and_refills():
	var a := Ammo.new(Weapons.make("sidearm"))
	assert_eq(a.reserve, a.max_reserve())
	var shots := 0
	while not a.is_empty() and shots < 1000:
		if a.can_fire(): a.fire(); shots += 1
		else: a.update(5.0)
	assert_eq(shots, a.weapon.mag_size * (1 + a.weapon.reserve_mags))
	assert_false(a.reload())
	a.refill(); assert_true(a.is_full())

func test_upgrade_renames_and_boosts():
	var w := Weapons.make("rifle"); var u := w.upgraded_version()
	assert_eq(u.display_name(), "Storm Pulse")
	assert_eq(u.mag_size, w.mag_size * 2); assert_eq(u.damage, w.damage * 2)
	for id in Weapons.ALL_IDS:
		var d := Weapons.make(id)
		assert_ne(d.upgrade_name, "", id); assert_gt(d.recoil_pattern.size(), 0, id); assert_gt(d.ads_time, 0.0, id)

func test_power_up_drops_bounded_and_cover_all():
	var p := PowerUps.new(); var rng := RandomNumberGenerator.new(); rng.seed = 7
	var seen := {}
	for round in 20:
		p.on_round_start()
		var n := 0
		for k in 200:
			var id := p.roll(rng)
			if id != "": n += 1; seen[id] = true
		assert_lte(n, PowerUps.MAX_PER_ROUND)
	assert_eq(seen.size(), PowerUps.ALL.size())

func test_power_up_timer():
	var p := PowerUps.new()
	p.activate("doublepay"); assert_true(p.active("doublepay"))
	assert_eq(p.update(29.0), []); assert_eq(p.update(1.5), ["doublepay"]); assert_false(p.active("doublepay"))
	p.activate("blackout"); assert_false(p.active("blackout"))  # instant ones have no timer

func test_last_stand_bleeds_out_without_lazarus():
	var ls := LastStand.new(); ls.start(false)
	assert_eq(ls.update(LastStand.BLEED_OUT - 0.1), "")
	assert_eq(ls.update(0.2), "dead")

func test_lazarus_revives_and_sells_out_after_three():
	var ls := LastStand.new(); ls.start(true)
	assert_eq(ls.update(LastStand.SELF_REVIVE + 0.1), "revive")
	var e := Economy.new(); e.points = 100000; var owned := {}
	for i in 3:
		assert_eq(Perks.buy("lazarus", owned, e, true), "")
		owned.erase("lazarus")   # used up on revive
	assert_eq(Perks.buy("lazarus", owned, e, true), "Sold out")
	assert_eq(Perks.held({"lazarus": true, "_lazarus_buys": 2}), ["lazarus"])
