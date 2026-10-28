extends GutTest
## v7: wonder-weapon quest, Forge alt ammo + camo, Pact Stone chain, boss rounds, high score, stats, audio.

func _econ(pts: int) -> Economy:
	var e := Economy.new(); e.points = pts; return e

func test_quest_needs_all_three_parts():
	var q := WonderQuest.new(); var rng := RandomNumberGenerator.new(); rng.seed = 3
	q.pick_spots(rng)
	for p in WonderQuest.PARTS: assert_true(q.chosen[p] < WonderQuest.SPOTS[p].size())
	assert_false(q.build())
	assert_true(q.collect("frame")); assert_false(q.collect("frame"), "no double pickup")
	assert_false(q.collect("bogus"))
	q.collect("core"); assert_false(q.can_build())
	q.collect("coil"); assert_true(q.can_build())
	assert_false(q.take(), "nothing to take before it is built")
	assert_true(q.build()); assert_false(q.build())
	assert_true(q.take()); assert_false(q.take(), "one Harp per game")
	assert_eq(q.prompt(), "")

func test_quest_spots_spread_across_areas():
	var seen := {}
	for p in WonderQuest.PARTS:
		for v in WonderQuest.SPOTS[p]: seen[v] = true
	assert_eq(seen.size(), 9, "all hiding spots distinct")

func test_gloam_harp_is_quest_only():
	var w := Weapons.make(Weapons.QUEST_WONDER)
	assert_not_null(w); assert_eq(w.name, "Gloam Harp")
	assert_false(Weapons.ALL_IDS.has(Weapons.QUEST_WONDER), "never in the Mystery Crate")
	assert_gt(w.pierce, 3)

func test_alt_ammo_assignment():
	for id in Weapons.ALL_IDS:
		assert_eq(AltAmmo.for_weapon(id, 0), "")
		var a := AltAmmo.for_weapon(id, 1); var b := AltAmmo.for_weapon(id, 2)
		assert_true(AltAmmo.KINDS.has(a)); assert_true(AltAmmo.KINDS.has(b)); assert_ne(a, b, "Mk.III rotates ammo")
	var kinds := {}
	for id in Weapons.ALL_IDS: kinds[AltAmmo.for_weapon(id, 1)] = true
	assert_eq(kinds.size(), 3, "all three ammo types appear across the roster")

func test_forge_bakes_alt_ammo_and_camo():
	var w := Weapons.make("rifle")
	assert_eq(w.alt_ammo, "")
	var up := w.upgraded_version()
	assert_eq(up.alt_ammo, AltAmmo.for_weapon("rifle", 1))
	assert_eq(up.duplicate_def().alt_ammo, up.alt_ammo)
	assert_eq(AltAmmo.camo(0).size(), 0); assert_eq(AltAmmo.camo(1).size(), 3); assert_ne(AltAmmo.camo(1)[0], AltAmmo.camo(2)[0])

func test_alt_ammo_proc_and_numbers():
	assert_false(AltAmmo.procs("", 0.0, 99.0))
	assert_true(AltAmmo.procs("fire", 0.0, AltAmmo.COOLDOWN))
	assert_false(AltAmmo.procs("fire", 0.0, AltAmmo.COOLDOWN - 0.1), "cooldown")
	assert_false(AltAmmo.procs("fire", AltAmmo.PROC_CHANCE + 0.01, 99.0))
	assert_almost_eq(AltAmmo.burn_dps(100), 35.0, 0.01)
	assert_eq(AltAmmo.chain_damage(100), 50); assert_eq(AltAmmo.chain_damage(1), 1)
	assert_lt(AltAmmo.SLOW_MULT, 1.0)

func test_pact_stone_chain():
	var ps := PactStone.new(); var e := _econ(5000)
	assert_eq(ps.current(), "awaken"); assert_eq(ps.cost(), PactStone.AWAKEN_COST)
	assert_false(ps.on_kill(1.0), "kills do nothing before awakening")
	assert_true(ps.pay(e)); assert_eq(e.points, 5000 - PactStone.AWAKEN_COST)
	assert_eq(ps.current(), "feed"); assert_false(ps.pay(e), "can't pay through the feed step")
	assert_false(ps.on_kill(PactStone.FEED_RADIUS + 1.0)); assert_eq(ps.souls, 0)
	for i in PactStone.SOULS - 1: assert_false(ps.on_kill(2.0))
	assert_true(ps.on_kill(2.0)); assert_eq(ps.current(), "tithe")
	assert_false(ps.pay(_econ(10)))
	assert_true(ps.pay(e)); assert_eq(ps.current(), "endure")
	ps.on_round_start(7); ps.on_down()
	assert_false(ps.on_round_end(7), "going down breaks the endure step")
	ps.on_round_start(8); assert_true(ps.on_round_end(8)); assert_true(ps.done); assert_eq(ps.prompt(), "")

func test_boss_round_every_15():
	assert_false(Rounds.is_boss(14)); assert_true(Rounds.is_boss(15)); assert_true(Rounds.is_boss(30)); assert_false(Rounds.is_boss(0))
	assert_false(Rounds.is_special(15), "boss rounds replace Frenzy")
	assert_true(Rounds.is_special(10))
	assert_lt(Rounds.boss_escort(15), Rounds.zombie_count(15))
	assert_true(ZombieTypes.is_heavy("warden")); assert_eq(ZombieTypes.guaranteed_drop("warden"), "restock")
	assert_gt(ZombieTypes.health("warden", 1000), ZombieTypes.health("brute", 1000))
	assert_lt(ZombieTypes.damage_taken("warden", 100, false, false), 100)

func test_high_score_saves_and_ranks():
	var path := "user://test_highscore_%d.cfg" % Time.get_ticks_usec()
	var h := HighScore.new(path)
	assert_true(h.submit({"round": 5, "kills": 40, "points": 9000}))
	assert_false(h.submit({"round": 4, "kills": 99, "points": 99999}), "round ranks first")
	assert_true(h.submit({"round": 5, "kills": 41, "points": 10}))
	var h2 := HighScore.new(path)
	assert_eq(h2.load_best().round, 5); assert_eq(h2.best.kills, 41)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_last_stand_and_stats_lines():
	var ls := LastStand.new(); ls.start(false)
	assert_eq(ls.update(LastStand.BLEED_OUT + 0.1), "dead")
	var st := RunStats.new(); st.kills = 12; st.headshots = 4; st.time = 125.0
	var lines := st.lines(6)
	assert_eq(lines.size(), 5)
	assert_string_contains(lines[0], "6"); assert_string_contains(lines[3], "2:05")

func test_v7_audio_present():
	for n in ["ann_round_v7", "ann_boss_v7", "ann_part_v7", "ann_built_v7", "ann_pact_v7", "ann_sealed_v7", "ann_gameover_v7", "ann_highscore_v7",
			"ann_laststand_v7", "ann_forge_v7", "alt_fire_v7", "alt_shock_v7", "alt_freeze_v7", "shatter_v7", "part_pickup_v7", "wonder_build_v7",
			"gloam_fire_v7", "pact_step_v7", "boss_roar_v7"]:
		assert_true(FileAccess.file_exists("res://audio/%s.wav" % n), n)
