extends GutTest
## v5: special zombie types, Marksman Mist, tutorial flow, settings.

func test_type_table_is_complete():
	for id in ["walker", "sprinter", "brute", "bloater"]:
		assert_true(ZombieTypes.ALL.has(id), id)
		for k in ["hp", "speed", "scale", "dmg", "armor", "tint", "points"]: assert_true(ZombieTypes.ALL[id].has(k), "%s.%s" % [id, k])

func test_distinct_silhouettes_and_roles():
	var t := ZombieTypes.ALL
	assert_lt(t.sprinter.scale, t.walker.scale); assert_gt(t.sprinter.speed, t.walker.speed); assert_lt(t.sprinter.hp, t.walker.hp)
	assert_gt(t.brute.scale, 1.3); assert_gt(t.brute.hp, 4.0); assert_gt(t.brute.armor, 0.0); assert_lt(t.brute.speed, 1.0)
	assert_gt(t.bloater.scale, t.walker.scale); assert_lt(t.bloater.speed, 1.0)

func test_brute_every_eight_rounds():
	for r in range(1, 40):
		assert_eq(ZombieTypes.is_brute_round(r), r % 8 == 0, "round %d" % r)

func test_brute_drops_guaranteed_restock():
	assert_eq(ZombieTypes.guaranteed_drop("brute"), "restock")
	assert_true(PowerUps.ALL.has("restock"))
	for id in ["walker", "sprinter", "bloater"]: assert_eq(ZombieTypes.guaranteed_drop(id), "")

func test_special_chances_ramp_and_cap():
	for r in range(1, ZombieTypes.SPRINTER_FROM): assert_eq(ZombieTypes.sprinter_chance(r), 0.0)
	for r in range(1, ZombieTypes.BLOATER_FROM): assert_eq(ZombieTypes.bloater_chance(r), 0.0)
	assert_gt(ZombieTypes.sprinter_chance(3), 0.0)
	assert_lte(ZombieTypes.sprinter_chance(50), 0.3); assert_lte(ZombieTypes.bloater_chance(50), 0.18)
	assert_gte(ZombieTypes.sprinter_chance(8), ZombieTypes.sprinter_chance(5))

func test_pick_distribution():
	assert_eq(ZombieTypes.pick(1, 0.0), "walker")
	assert_eq(ZombieTypes.pick(10, 0.0), "bloater")
	assert_eq(ZombieTypes.pick(10, ZombieTypes.bloater_chance(10) + 0.01), "sprinter")
	assert_eq(ZombieTypes.pick(10, 0.99), "walker")
	var n := {"walker": 0, "sprinter": 0, "bloater": 0}
	for i in 1000: n[ZombieTypes.pick(12, i / 1000.0)] += 1
	assert_gt(n.walker, 500); assert_gt(n.sprinter, 100); assert_gt(n.bloater, 50)

func test_health_scaling_per_type():
	assert_eq(ZombieTypes.health("walker", 150), 150)
	assert_eq(ZombieTypes.health("brute", 150), 1200)
	assert_eq(ZombieTypes.health("sprinter", 150), 90)
	assert_gte(ZombieTypes.health("sprinter", 1), 1)

func test_brute_armor_only_on_body_shots():
	assert_eq(ZombieTypes.damage_taken("brute", 100, false, false), 50)
	assert_eq(ZombieTypes.damage_taken("brute", 100, true, false), 100)
	assert_eq(ZombieTypes.damage_taken("brute", 100, false, true), 100)
	assert_eq(ZombieTypes.damage_taken("walker", 100, false, false), 100)
	assert_eq(ZombieTypes.damage_taken("brute", 1, false, false), 1)

func test_bloater_burst_falloff():
	assert_eq(ZombieTypes.burst_damage(0.0), ZombieTypes.BLOATER_BURST)
	assert_eq(ZombieTypes.burst_damage(ZombieTypes.BLOATER_RADIUS), 0)
	assert_eq(ZombieTypes.burst_damage(99.0), 0)
	assert_lt(ZombieTypes.burst_damage(2.0), ZombieTypes.burst_damage(1.0))
	assert_lt(ZombieTypes.BLOATER_TRIGGER, ZombieTypes.BLOATER_RADIUS)
	# a burst at point-blank must never one-shot a full-health player on its own
	assert_lt(ZombieTypes.BLOATER_BURST + ZombieTypes.GAS_DPS, 100)

func test_marksman_mist():
	assert_true(Perks.ALL.has("marksman")); assert_eq(Perks.ALL.marksman.name, "Marksman Mist")
	assert_eq(Perks.head_mult({}), 2.0)
	assert_eq(Perks.head_mult({"marksman": true}), 3.0)
	var e := Economy.new(); e.points = 3000
	assert_eq(Perks.buy("marksman", {}, e, true), "")
	assert_eq(Perks.ALL.ironhide.name, "Iron Hide Tonic")

func test_tutorial_flow():
	var t := Tutorial.new()
	assert_eq(t.current(), "move")
	t.event("shoot")                 # out of order: ignored
	assert_eq(t.current(), "move")
	t.event("move", 3.5); assert_eq(t.current(), "shoot")
	t.event("shoot"); assert_eq(t.current(), "rebuild")
	t.event("rebuild"); assert_eq(t.current(), "buy")
	assert_true(t.prompt().begins_with("4/4"))
	t.event("buy"); assert_true(t.done()); assert_eq(t.prompt(), "")

func test_tutorial_skip_and_timeouts():
	var t := Tutorial.new(); t.skip(); assert_true(t.done())
	var u := Tutorial.new()
	for i in 200: u.update(0.25)     # 50 s with no input
	assert_true(u.done())
	assert_lte(Tutorial.MAX_TIME, 40.0)

func test_settings_armory_and_tutorial_roundtrip():
	var s := GameSettings.new()
	assert_eq(s.starter_gun, "smg"); assert_false(s.tutorial_done)
	s.starter_gun = "rifle"; s.tutorial_done = true
	var s2 := GameSettings.new(); s2.from_dict(s.to_dict())
	assert_eq(s2.starter_gun, "rifle"); assert_true(s2.tutorial_done)
	s2.from_dict({"starter_gun": "bogus"}); assert_eq(s2.starter_gun, "smg")
	for p in GameSettings.ORDER: assert_true(GameSettings.PRESETS[p].has("ragdolls"))
	assert_lte(GameSettings.PRESETS.low.ragdolls, 4)

func test_painted_tally():
	for r in range(1, 11): assert_eq(Hud.painted_strokes(r), r)
	assert_eq(Hud.painted_strokes(11), 0)

func test_pump_station_door_opens_its_windows() -> void:
	var f := Facility.new(); var e := Economy.new(); e.points = 5000
	assert_false(f.active_windows().has("w_pump_s"))
	assert_eq(f.buy_door("pump", e), "")
	assert_true(f.active_windows().has("w_pump_s") and f.active_windows().has("w_pump_e"))
