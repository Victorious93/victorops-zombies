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

# ---- v7 touch HUD: no overlaps, inside the safe area, at 16:9 / 19.5:9 / 20:9 ----
const HUD_SCREENS := [
	[Vector2(1920, 1080), 0.0, 0.0],      # 16:9, no cutout
	[Vector2(2532, 1170), 132.0, 63.0],   # 19.5:9, notch + home indicator
	[Vector2(2400, 1080), 110.0, 48.0],   # 20:9, punch-hole + gesture bar
	[Vector2(1280, 720), 0.0, 0.0],
]

func test_hud_no_overlap_and_inside_safe_area():
	for sc in HUD_SCREENS:
		var safe := TouchLayout.phone_safe(sc[0], sc[1], sc[2])
		for scale in [0.7, 1.0, 1.2, 1.4]:
			for fs in [1.0, 1.3, 1.8]:
				for lf in [false, true]:
					var b := TouchLayout.buttons(sc[0], safe, scale, fs, lf)
					var tag := "%s scale=%s fire=%s left=%s" % [sc[0], scale, fs, lf]
					assert_eq(TouchLayout.overlaps(b), [], "overlap " + tag)
					assert_eq(TouchLayout.outside_safe(b, safe), [], "outside safe " + tag)

func test_hud_has_all_actions():
	var b := TouchLayout.buttons(Vector2(2400, 1080), Rect2(), 1.0, 1.3, true)
	for n in ["fire", "fire_l", "ads", "reload", "jump", "crouch", "grenade", "swap", "use", "pause"]:
		assert_true(b.has(n), n)
	assert_false(TouchLayout.buttons(Vector2(2400, 1080)).has("fire_l"), "left fire is optional")

func test_hud_arc_is_thumb_reachable():
	var s := Vector2(2400, 1080)
	var b := TouchLayout.buttons(s, TouchLayout.phone_safe(s, 110, 48))
	var u := s.y / 720.0
	for n in ["ads", "reload", "jump", "crouch"]:
		assert_lt(b[n][0].distance_to(b["fire"][0]), 200.0 * u, n)
	for n in ["grenade", "swap", "knife", "skill"]:
		assert_lt(b[n][0].distance_to(b["fire"][0]), 330.0 * u, n)
	assert_gt(b["fire"][0].x, s.x * 0.75, "fire on the right")

func test_hud_custom_positions_clamped_into_safe_area():
	var s := Vector2(2532, 1170); var safe := TouchLayout.phone_safe(s, 132, 63)
	var b := TouchLayout.buttons(s, safe, 1.0, 1.3, false, {"jump": Vector2(1.5, -0.2), "ads": Vector2(0.5, 0.5)})
	assert_eq(TouchLayout.outside_safe(b, safe), [])
	assert_almost_eq(b["ads"][0].x, safe.get_center().x, 0.5)

func test_hud_editor_rejects_overlapping_drop():
	var b := TouchLayout.buttons(Vector2(1920, 1080))
	assert_false(TouchLayout.can_place(b, "jump", b["fire"][0]), "on top of fire")
	assert_true(TouchLayout.can_place(b, "jump", Vector2(960, 540)), "empty middle")

func test_controls_settings_round_trip():
	var st := GameSettings.new()
	st.button_scale = 1.25; st.button_opacity = 0.4; st.left_fire = true; st.layout = {"jump": Vector2(0.6, 0.7)}
	var st2 := GameSettings.new(); st2.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_almost_eq(st2.button_scale, 1.25, 0.001); assert_almost_eq(st2.button_opacity, 0.4, 0.001)
	assert_true(st2.left_fire)
	assert_almost_eq((st2.layout["jump"] as Vector2).x, 0.6, 0.001)
	st2.from_dict({"button_scale": 9, "button_opacity": -1})
	assert_almost_eq(st2.button_scale, 1.4, 0.001); assert_almost_eq(st2.button_opacity, 0.15, 0.001)
