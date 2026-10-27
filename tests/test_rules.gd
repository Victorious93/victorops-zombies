extends GutTest
## Rules ported from the libGDX LogicTest.kt, plus the new 3D rules (doors, power, perks, loadout).

func test_round1_baseline():
	assert_eq(Rounds.zombie_count(1), 6)
	assert_eq(Rounds.zombie_health(1), 150)

func test_count_monotonic_on_normal_rounds():
	var prev := 0
	for r in range(1, 61):
		if Rounds.is_special(r): continue
		assert_true(Rounds.zombie_count(r) >= prev, "round %d" % r)
		prev = Rounds.zombie_count(r)

func test_count_capped():
	assert_eq(Rounds.zombie_count(501), 120)

func test_health_curve():
	assert_eq(Rounds.zombie_health(9), 950)
	assert_eq(Rounds.zombie_health(10), 1045)
	assert_gt(Rounds.zombie_health(20), Rounds.zombie_health(19))

func test_speed_and_spawn_caps():
	assert_eq(Rounds.zombie_speed_units(100), 150.0)
	assert_almost_eq(Rounds.spawn_interval(100), 0.4, 0.0001)

func test_special_rounds():
	assert_false(Rounds.is_special(4))
	assert_true(Rounds.is_special(5))
	assert_true(Rounds.is_special(10))
	assert_eq(Rounds.zombie_count(5), int((6 + 12 + 4) * 0.75))
	assert_gt(Rounds.zombie_speed(5), Rounds.zombie_speed(6))

func test_economy():
	assert_eq(Economy.new().points, 500)
	var e := Economy.new(0)
	e.on_hit(); e.on_kill(); e.on_kill(true); e.on_repair()
	assert_eq(e.points, 10 + 60 + 100 + 10)

func test_cannot_overspend():
	var e := Economy.new(100)
	assert_false(e.spend(101)); assert_eq(e.points, 100)
	var f := Economy.new(1000)
	assert_true(f.spend(950)); assert_eq(f.points, 50)

func test_iron_hide_needs_power_and_buys_once():
	var e := Economy.new(6000); var owned := {}
	assert_eq(Perks.buy("ironhide", owned, e, false), "Power required")
	assert_eq(Perks.buy("ironhide", owned, e, true), "")
	assert_eq(Perks.buy("ironhide", owned, e, true), "Already owned")
	assert_eq(e.points, 3500)

func test_perk_unaffordable():
	var e := Economy.new(100); var owned := {}
	assert_eq(Perks.buy("quickhand", owned, e, true), "Not enough points")
	assert_false(owned.has("quickhand")); assert_eq(e.points, 100)

func test_three_original_perks():
	assert_eq(Perks.ALL.size(), 4)
	assert_eq(Perks.ALL.ironhide.name, "Iron Hide Tonic")

func test_crate_probabilities():
	var b := MysteryCrate.new(); var s := 0.0
	for e in b.table: s += b.probability_of(e[0])
	assert_almost_eq(s, 1.0, 1e-9)
	assert_almost_eq(b.probability_of("nova"), 0.05, 1e-9)

func test_crate_distribution():
	var b := MysteryCrate.new(); var rng := RandomNumberGenerator.new(); rng.seed = 42
	var counts := {}; var n := 20000
	for i in n:
		var id := b.roll(rng); counts[id] = counts.get(id, 0) + 1
	for e in b.table:
		assert_almost_eq(float(counts.get(e[0], 0)) / n, b.probability_of(e[0]), 0.015)

func test_crate_excludes_current():
	var b := MysteryCrate.new(); var rng := RandomNumberGenerator.new(); rng.seed = 1
	for i in 1000: assert_ne(b.roll(rng, "smg"), "smg")

func test_crate_cost():
	var b := MysteryCrate.new(); var rng := RandomNumberGenerator.new()
	assert_eq(b.buy(Economy.new(900), rng), "")
	var e := Economy.new(1000)
	assert_ne(b.buy(e, rng), ""); assert_eq(e.points, 50)

func test_barricade():
	var b := Barricade.new()
	assert_eq(b.hp, 300); assert_eq(b.planks(), 6); assert_false(b.is_broken())
	b.damage(60); assert_eq(b.planks(), 5); assert_eq(b.hp, 240)
	b.damage(1000); assert_eq(b.hp, 0); assert_true(b.is_broken())
	assert_true(b.repair_plank()); assert_eq(b.hp, 50)
	b.damage(10); assert_true(b.repair_plank()); assert_eq(b.hp, 50)
	assert_false(Barricade.new().repair_plank())

func test_barricade_multi_repair():
	var b := Barricade.new(); b.damage(120)
	assert_eq(b.planks(), 4)
	assert_eq(b.repair_planks(5), 3); assert_eq(b.planks(), 6); assert_eq(b.repair_all(), 0)

func test_weapon_tiers():
	var w := Weapons.make("sidearm")
	assert_eq(w.display_name(), "Volt Sidearm")
	w = w.upgraded_version(); assert_eq(w.display_name(), "Volt Tempest"); assert_eq(w.damage, 160); assert_false(w.is_maxed())
	w = w.upgraded_version(); assert_eq(w.display_name(), "Volt Tempest Mk.III"); assert_eq(w.damage, 240); assert_true(w.is_maxed())
	assert_same(w.upgraded_version(), w)

func test_upgrade_details():
	var a := Weapons.at("smg", 0); var b := Weapons.at("smg", 1); var c := Weapons.at("smg", 2)
	assert_true(a.fire_interval > b.fire_interval and b.fire_interval > c.fire_interval)
	assert_eq(Weapons.at("scatter", 2).pellets, 10)
	assert_eq(Weapons.at("cannon", 2).pierce, 3)
	assert_eq(Weapons.at("rifle", 1).pierce, 0); assert_eq(Weapons.at("rifle", 2).pierce, 1)
	assert_gt(Weapons.at("nova", 1).splash, Weapons.make("nova").splash)
	var r := Weapons.make("rifle"); var u := r.upgraded_version()
	assert_true(u.mag_size > r.mag_size and u.reload_time < r.reload_time)

func test_forge():
	var f := OverchargeForge.new(); var e := Economy.new(100000)
	assert_eq(f.cost_for(Weapons.make("smg")), 5000)
	var t1 := f.upgrade(Weapons.make("smg"), e); assert_eq(e.points, 95000); assert_eq(f.cost_for(t1), 10000)
	var t2 := f.upgrade(t1, e); assert_eq(e.points, 85000)
	assert_eq(f.cost_for(t2), -1); assert_null(f.upgrade(t2, e)); assert_eq(e.points, 85000)

func test_forge_unaffordable():
	var f := OverchargeForge.new(); var e := Economy.new(4999)
	assert_null(f.upgrade(Weapons.make("sidearm"), e)); assert_eq(e.points, 4999)

func test_armor_absorb_and_cap():
	var a := ArmorState.new(); a.add(50)
	assert_eq(a.absorb(30.0), 0.0); assert_eq(a.value, 20.0)
	assert_eq(a.absorb(30.0), 10.0); assert_eq(a.value, 0.0)
	var b := ArmorState.new(); b.add(150); b.add(150)
	assert_eq(b.value, 200.0); assert_true(b.is_full())

func test_armor_buy():
	var a := ArmorState.new(); var e := Economy.new(10000)
	assert_true(a.buy("heavy", e)); assert_eq(e.points, 8200); assert_eq(a.value, 150.0)
	assert_true(a.buy("medium", e)); assert_eq(a.value, 200.0)
	var before := e.points
	assert_false(a.buy("light", e)); assert_eq(e.points, before)
	var c := ArmorState.new(); var p := Economy.new(499)
	assert_false(c.buy("light", p)); assert_eq(c.value, 0.0); assert_eq(p.points, 499)

func test_armor_tiers_ordered():
	var ids := ["light", "medium", "heavy"]
	for i in 2:
		assert_lt(ArmorState.PACKS[ids[i]].cost, ArmorState.PACKS[ids[i + 1]].cost)
		assert_lt(ArmorState.PACKS[ids[i]].armor, ArmorState.PACKS[ids[i + 1]].armor)

func test_characters():
	assert_eq(Characters.ALL.size(), 2)
	assert_eq(Characters.by_id("hollis").name, "Hollis Marrow")
	assert_eq(Characters.by_id("rook").ability_name, "Bass Drop")
	assert_eq(Characters.by_id("hollis").ability_name, "Fortify")
	assert_eq(Characters.by_id("nope").name, Characters.by_id(Characters.DEFAULT).name)
	var m := Characters.by_id("hollis"); var s := Characters.by_id("rook")
	assert_gt(m.repair_planks_per_use, s.repair_planks_per_use)
	var e := Economy.new(0); e.on_repair(2, m.repair_points_mult); assert_eq(e.points, 40)
	assert_true(s.fire_interval_mult < 1.0 and s.speed_mult > 1.0)
	assert_gt(Characters.bass_damage(10), Characters.bass_damage(1))

func test_ammo_cycle():
	var a := Ammo.new(Weapons.make("scatter"))
	for i in a.weapon.mag_size - 1: assert_false(a.fire())
	assert_true(a.fire()); assert_true(a.reloading()); assert_false(a.can_fire())
	a.update(a.weapon.reload_time - 0.1); assert_true(a.reloading())
	a.update(0.2); assert_false(a.reloading()); assert_eq(a.rounds, a.weapon.mag_size)

func test_ammo_swap_and_manual_reload():
	var a := Ammo.new(Weapons.make("rifle")); a.fire()
	a.swap(Weapons.make("nova")); assert_eq(a.rounds, 6); assert_true(a.can_fire())
	assert_false(a.reload())
	a.fire(); assert_true(a.reload()); assert_false(a.can_fire())

func test_quickhand_halves_reload():
	var a := Ammo.new(Weapons.make("sidearm")); a.reload_mult = 0.5
	a.fire(); a.reload(); assert_almost_eq(a.reload_left, 0.65, 1e-5)

func test_low_health_trigger():
	var t := LowHealthTrigger.new()
	assert_false(t.check(100, 100)); assert_true(t.check(25, 100)); assert_false(t.check(10, 100))
	assert_false(t.check(40, 100)); assert_false(t.check(20, 100))
	assert_false(t.check(60, 100)); assert_true(t.check(20, 100))
	assert_false(LowHealthTrigger.new().check(0, 100))

func test_facility_doors_and_windows():
	var f := Facility.new(); var e := Economy.new(800)
	assert_eq(f.active_windows().size(), 2)
	assert_eq(f.buy_door("east", e), "Not enough points"); assert_eq(e.points, 800)
	assert_eq(f.buy_door("north", e), ""); assert_eq(e.points, 50)
	assert_eq(f.buy_door("north", e), "Already open")
	assert_true(f.open_areas.generator)
	assert_eq(f.active_windows().size(), 3)

func test_power_switch_once():
	var f := Facility.new()
	assert_false(f.power_on)
	assert_true(f.throw_power()); assert_false(f.throw_power()); assert_true(f.power_on)

func test_loadout_two_slots():
	var l := Loadout.new(Weapons.make("sidearm"))
	l.give(Weapons.make("smg")); assert_eq(l.slots.size(), 2); assert_eq(l.weapon().id, "smg")
	l.give(Weapons.make("rifle")); assert_eq(l.slots.size(), 2); assert_eq(l.weapon().id, "rifle")
	assert_eq(l.has("smg"), -1); assert_eq(l.has("sidearm"), 0)
	l.cycle(); assert_eq(l.weapon().id, "sidearm")
	l.give(Weapons.make("sidearm")); assert_eq(l.slots.size(), 2)

func test_characters_are_original():
	for id in Characters.ALL:
		var n: String = Characters.ALL[id].name
		for banned in ["Snoop", "Martha", "Stewart", "Dogg"]:
			assert_false(n.contains(banned), "%s should be an original name" % n)

func test_full_gun_roster():
	for id in ["sidearm", "smg", "scatter", "rifle", "lmg", "nova"]:
		assert_not_null(Weapons.make(id), id)
		assert_true(Weapons.MODELS.has(id), "model for " + id)
	assert_true(Weapons.make("lmg").mag_size > Weapons.make("rifle").mag_size)
	assert_eq(Weapons.WONDER, "nova")
	assert_false(Weapons.WALL_PRICES.has(Weapons.WONDER), "wonder weapon is crate-only")
	assert_gt(MysteryCrate.new().probability_of("lmg"), 0.0)

func test_grenades():
	var e := Equipment.new()
	assert_eq(e.grenades, Equipment.GRENADE_START)
	assert_true(e.throw_one()); assert_true(e.throw_one()); assert_false(e.throw_one())
	e.on_round_start(); e.on_round_start(); e.on_round_start()
	assert_eq(e.grenades, Equipment.GRENADE_MAX)
	assert_eq(Equipment.grenade_falloff(0.0), 1.0)
	assert_almost_eq(Equipment.grenade_falloff(Equipment.GRENADE_RADIUS_M), 0.25, 1e-5)
	assert_eq(Equipment.grenade_falloff(Equipment.GRENADE_RADIUS_M + 0.1), 0.0)
	assert_gt(Equipment.grenade_damage(10), Equipment.grenade_damage(1))

func test_crate_moves_to_a_different_spot():
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var m := CrateMover.new(["lab", "yard", "gen", "intake"], rng)
	assert_between(m.uses_left, CrateMover.MIN_USES, CrateMover.MAX_USES)
	for trial in 200:
		var rolls := 0
		while not m.on_roll(rng): rolls += 1
		assert_between(rolls + 1, CrateMover.MIN_USES, CrateMover.MAX_USES)
		var before := m.current
		assert_ne(m.relocate(rng), before)
	var single := CrateMover.new(["lab"], rng)
	for i in 20: assert_false(single.on_roll(rng))

func test_resonance_easter_egg():
	var r := Resonance.new()
	assert_eq(r.shoot("yard", false), "", "needs power")
	assert_eq(r.shoot("yard", true), "progress")
	assert_eq(r.shoot("yard", true), "", "no double count")
	assert_eq(r.shoot("bogus", true), "")
	assert_eq(r.shoot("cold", true), "progress")
	assert_eq(r.shoot("catwalk", true), "complete")
	assert_true(r.done); assert_eq(r.shoot("cold", true), "")

func test_settings_and_presets():
	var s := GameSettings.new()
	s.set_sensitivity(10.0); assert_eq(s.sensitivity, 3.0)
	s.set_preset("ultra"); assert_eq(s.preset, "medium")
	assert_eq(GameSettings.default_preset(true), "low")
	assert_lt(GameSettings.PRESETS.low.scale, GameSettings.PRESETS.high.scale)
	assert_false(GameSettings.PRESETS.low.shadows)
	var t := GameSettings.new(); s.set_preset("high"); s.aim_assist = false
	t.from_dict(s.to_dict())
	assert_eq(t.preset, "high"); assert_false(t.aim_assist); assert_eq(t.sensitivity, 3.0)

func test_aim_assist():
	var o := Vector3.ZERO; var f := Vector3(0, 0, -1)
	var targets := [Vector3(5, 0, -10), Vector3(0.3, 0, -10), Vector3(0, 0, 10)]
	assert_eq(AimAssist.pick(o, f, targets), 1)
	assert_eq(AimAssist.pick(o, f, [Vector3(5, 0, -10)]), -1, "outside cone")
	assert_eq(AimAssist.pick(o, f, [Vector3(0, 0, -50)], 30.0), -1, "out of range")
	var n := AimAssist.nudge(o, f, Vector3(0.3, 0, -10), 0.016)
	assert_lt(n.x, 0.0, "turns right (negative yaw) toward a target on +x")

func test_yard_area():
	var f := Facility.new(); var e := Economy.new(5000)
	assert_eq(f.buy_door("yard", e), ""); assert_true(f.open_areas.yard)
	assert_true(f.active_windows().has("w_yard_n"))

func test_original_characters_keep_abilities():
	assert_eq(Characters.DEFAULT, "rook")
	assert_eq(Characters.ALL.rook.ability, "bass_drop")
	assert_eq(Characters.ALL.hollis.ability, "fortify")
	for id in Characters.ALL:
		var n: String = Characters.ALL[id].name.to_lower()
		assert_false(n.contains("snoop") or n.contains("martha"), "no celebrity names")
