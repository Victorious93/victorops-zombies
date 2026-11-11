extends GutTest
## v10 (VICTOR ZOMBIES by Victorious Framework): districts + power objective, purchase safety,
## the Brute elite, lifetime statistics, settings round-trip and the How-to-play card.

func test_three_districts_cover_every_room_once() -> void:
	assert_eq(Facility.DISTRICT_ORDER.size(), 3)
	var seen := {}
	for id in Facility.DISTRICT_ORDER:
		for a in Facility.DISTRICTS[id].areas:
			assert_false(seen.has(a), a); seen[a] = true
			assert_eq(Facility.district_of(a), id)
			assert_true(Facility.AREA_NAMES.has(a) and Facility.AREA_RECTS.has(a), a)
	for d in Facility.DOORS: assert_true(seen.has(Facility.DOORS[d].opens), d)
	for w in Facility.WINDOWS: assert_true(seen.has(Facility.WINDOWS[w]), w)

func test_area_lookup_matches_the_map() -> void:
	assert_eq(Facility.area_at(0, 3), "intake")
	assert_eq(Facility.area_at(3, -23), "generator")
	assert_eq(Facility.area_at(18, -24), "cold")
	assert_eq(Facility.area_at(16, 6), "lab")
	assert_eq(Facility.area_at(36, 2), "yard")
	assert_eq(Facility.area_at(40, 24), "pump")
	assert_eq(Facility.area_at(-50, 0), "")

func test_districts_unlock_with_doors() -> void:
	var f := Facility.new(); var e := Economy.new(); e.points = 10000
	assert_eq(f.districts_open(), 1)
	f.buy_door("east", e); assert_eq(f.districts_open(), 2)
	f.buy_door("yard", e); assert_eq(f.districts_open(), 3)

func test_power_objective_steps_and_text() -> void:
	var f := Facility.new(); var e := Economy.new(); e.points = 10000
	assert_string_contains(f.objective(), "open the Back Alley")
	f.buy_door("north", e)
	assert_string_contains(f.objective(), "crank the generator")
	for i in Facility.POWER_CRANKS - 1:
		assert_false(f.crank_power(), "crank %d" % i); assert_false(f.power_on)
	assert_true(f.crank_power(), "the last crank starts it"); assert_true(f.power_on)
	assert_false(f.crank_power(), "cranking a running generator does nothing")
	assert_eq(f.cranks, Facility.POWER_CRANKS)
	assert_string_contains(f.objective(), "Power on")
	f.buy_door("east", e); f.buy_door("yard", e)
	assert_eq(f.objective(), "")

func test_a_fresh_facility_has_no_power_or_progress() -> void:
	var f := Facility.new()
	assert_false(f.power_on); assert_eq(f.cranks, 0); assert_true(f.open_doors.is_empty())
	assert_eq(f.open_areas.keys(), ["intake"])

func test_crate_never_rolls_a_weapon_already_carried() -> void:
	var c := MysteryCrate.new(); var rng := RandomNumberGenerator.new(); rng.seed = 7
	for i in 2000:
		var id := c.roll(rng, ["rifle", "smg"])
		assert_true(id != "rifle" and id != "smg", id)
		assert_not_null(Weapons.make(id), "crate only rolls real weapons")
	for i in 200: assert_ne(c.roll(rng, "scatter"), "scatter")   # single id still accepted

func test_crate_charges_once_and_only_when_affordable() -> void:
	var c := MysteryCrate.new(); var rng := RandomNumberGenerator.new(); rng.seed = 3
	var e := Economy.new(); e.points = MysteryCrate.COST - 1
	assert_eq(c.buy(e, rng, ["sidearm"]), ""); assert_eq(e.points, MysteryCrate.COST - 1)
	e.points = MysteryCrate.COST
	assert_ne(c.buy(e, rng, ["sidearm"]), ""); assert_eq(e.points, 0)

func test_three_core_enhancements() -> void:
	assert_eq(Perks.CORE, ["ironhide", "quickhand", "fleetfoot"])
	for id in Perks.CORE:
		assert_true(Perks.ALL.has(id)); assert_gt(String(Perks.ALL[id].desc).length(), 8)
	assert_eq(Perks.HEALTH_MULT, 2.0); assert_eq(Perks.RELOAD_MULT, 0.5); assert_gt(Perks.STAMINA_MULT, 1.0)

func test_enhancement_purchase_rules() -> void:
	var owned := {}; var e := Economy.new(); e.points = 100
	assert_eq(Perks.buy("ironhide", owned, e, false), "Power required"); assert_eq(e.points, 100)
	assert_eq(Perks.buy("ironhide", owned, e, true), "Not enough points"); assert_false(owned.has("ironhide"))
	e.points = 6000
	assert_eq(Perks.buy("ironhide", owned, e, true), ""); assert_eq(e.points, 6000 - Perks.ALL.ironhide.cost)
	assert_eq(Perks.buy("ironhide", owned, e, true), "Already owned"); assert_eq(e.points, 6000 - Perks.ALL.ironhide.cost)
	assert_eq(Perks.effect_lines(owned), ["Iron Hide Tonic — Doubles max health"])
	assert_eq(Perks.effect_lines({}), [])

func test_forge_upgrade_is_a_real_improvement() -> void:
	for id in Weapons.ALL_IDS:
		var w := Weapons.make(id); var up := w.upgraded_version()
		assert_gt(up.damage, w.damage, id); assert_gt(up.mag_size, w.mag_size, id)
		assert_lt(up.fire_interval, w.fire_interval, id); assert_lt(up.reload_time, w.reload_time, id)
		assert_ne(up.color, w.color, id + " looks different"); assert_ne(up.display_name(), w.display_name(), id)

func test_brute_schedule_and_count() -> void:
	assert_eq(ZombieTypes.brute_count(3), 0); assert_eq(ZombieTypes.brute_count(4), 1); assert_eq(ZombieTypes.brute_count(8), 1)
	assert_eq(ZombieTypes.brute_count(12), 2); assert_eq(ZombieTypes.brute_count(13), 0)

func test_brute_weakness_and_reward() -> void:
	assert_eq(ZombieTypes.damage_taken("brute", 100, false, false), 50, "armour halves body shots")
	assert_eq(ZombieTypes.damage_taken("brute", 100, true, false), 100, "the head is not armoured")
	assert_eq(ZombieTypes.damage_taken("brute", 100, false, false, true), 100, "winded: armour is down")
	assert_eq(ZombieTypes.damage_taken("walker", 100, false, false, true), 100)
	assert_gte(int(ZombieTypes.ALL.brute.points), 500); assert_eq(ZombieTypes.guaranteed_drop("brute"), "restock")

func test_brute_attacks_are_survivable_and_telegraphed() -> void:
	assert_gte(ZombieTypes.SLAM_WINDUP, 1.0, "at least a second of warning")
	assert_gt(ZombieTypes.SLAM_TRIGGER, ZombieTypes.SLAM_RADIUS, "it starts the slam from outside its own ring")
	assert_lt(ZombieTypes.SLAM_DAMAGE, 100.0, "a full-health survivor lives through one slam")
	assert_lt(Zombie.SWIPE_DAMAGE * float(ZombieTypes.ALL.brute.dmg), 100.0, "and through one swing")
	assert_gt(ZombieTypes.HEAVY_SWING_WINDUP, Zombie.WINDUP)
	assert_gt(ZombieTypes.SLAM_COOLDOWN, ZombieTypes.SLAM_WINDUP + ZombieTypes.SLAM_WINDED)

func test_difficulty_is_not_only_health() -> void:
	# between round 3 and round 12: more zombies, faster gaits, quicker spawns and special types, not just HP
	assert_gt(Rounds.zombie_count(12), Rounds.zombie_count(3) * 2)
	assert_lt(Rounds.spawn_interval(12), Rounds.spawn_interval(3))
	assert_gt(Gait.mix(12)[2], Gait.mix(3)[2]); assert_gt(ZombieTypes.sprinter_chance(12), ZombieTypes.sprinter_chance(3))
	assert_gt(ZombieTypes.bloater_chance(12), 0.0)
	assert_lte(Rounds.zombie_health(12), Rounds.zombie_health(3) * 4, "health grows slower than the horde")
	assert_lte(Rounds.MAX_ALIVE, 24)

func test_elite_bar_text() -> void:
	assert_string_contains(Hud.elite_bar_text("brute", false, false), "head")
	assert_string_contains(Hud.elite_bar_text("brute", false, true), "SLAM")
	assert_string_contains(Hud.elite_bar_text("brute", true, false), "WINDED")
	assert_string_contains(Hud.elite_bar_text("warden", false, false), "WARDEN")

func test_lifetime_totals_accumulate_and_records_survive() -> void:
	var path := "user://test_v10_hs.cfg"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var h := HighScore.new(path)
	assert_true(h.submit({"round": 5, "kills": 40, "points": 6000, "headshots": 10, "elites": 1}))
	assert_false(HighScore.new(path).submit({"round": 2, "kills": 9, "points": 900, "headshots": 3, "elites": 0}), "a worse run is not a best")
	var h3 := HighScore.new(path)
	var t := h3.load_totals(); var r := h3.load_records(); var b := h3.load_best()
	assert_eq(int(t.matches), 2); assert_eq(int(t.kills), 49); assert_eq(int(t.headshots), 13); assert_eq(int(t.elites), 1); assert_eq(int(t.rounds), 7)
	assert_eq(int(r.round), 5); assert_eq(int(r.score), 6000); assert_eq(int(b.headshots), 10)
	assert_string_contains(HighScore.totals_text(t), "49 kills"); assert_string_contains(HighScore.totals_text(t), "13 headshots (27%)")
	assert_string_contains(HighScore.totals_text({}), "0 kills")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_old_save_without_totals_still_loads() -> void:
	var path := "user://test_v10_old.cfg"
	var cf := ConfigFile.new(); cf.set_value("best", "round", 6); cf.set_value("best", "points", 4000); cf.save(path)
	var h := HighScore.new(path)
	assert_eq(int(h.load_totals().matches), 0); assert_eq(int(h.load_records().round), 6)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_settings_round_trip_including_invert_look() -> void:
	var a := GameSettings.new()
	a.invert_y = true; a.set_sensitivity(1.7); a.set_preset("low"); a.music = 0.2; a.sfx = 0.4; a.shake = 0.5; a.joystick = "fixed"
	var b := GameSettings.new(); b.from_dict(a.to_dict())
	assert_true(b.invert_y); assert_almost_eq(b.sensitivity, 1.7, 0.001); assert_eq(b.preset, "low")
	assert_almost_eq(b.music, 0.2, 0.001); assert_almost_eq(b.sfx, 0.4, 0.001); assert_almost_eq(b.shake, 0.5, 0.001); assert_eq(b.joystick, "fixed")
	var c := GameSettings.new(); c.from_dict({})
	assert_false(c.invert_y, "old settings files default to normal look")

func test_run_stats_lines_report_progress() -> void:
	var st := RunStats.new(); st.districts = 3; st.power = true; st.elites = 2
	var joined := "\n".join(st.lines(9))
	assert_string_contains(joined, "Districts  3/3"); assert_string_contains(joined, "Power  restored"); assert_string_contains(joined, "Brutes slain  2")

func test_help_card_text_comes_from_the_rules() -> void:
	var loop := "\n".join(HelpPanel.loop_lines()); var shop := "\n".join(HelpPanel.shop_lines())
	assert_string_contains(loop, str(Facility.DOORS.north.cost)); assert_string_contains(loop, "BRUTE")
	for id in Perks.CORE:
		assert_string_contains(shop, Perks.ALL[id].name); assert_string_contains(shop, str(Perks.ALL[id].cost))
	assert_string_contains(shop, str(MysteryCrate.COST))
	for id in PowerUps.ALL: assert_string_contains(shop, PowerUps.ALL[id].name)
	assert_gt(HelpPanel.controls(true).size(), 3); assert_gt(HelpPanel.controls(false).size(), 3)
	var p := HelpPanel.make(true); assert_not_null(p); p.free()

func test_atmosphere_escalates_and_is_capped() -> void:
	assert_eq(Game.atmosphere01(1), 0.0); assert_gt(Game.atmosphere01(8), Game.atmosphere01(3)); assert_eq(Game.atmosphere01(40), 1.0)

func test_version_is_ten() -> void:
	assert_true(String(ProjectSettings.get_setting("application/config/version")).begins_with("10."))
