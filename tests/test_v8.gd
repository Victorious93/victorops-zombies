extends GutTest
## v8 "Victor Zombies" pass: pump-action shell reload, reload/switch rules, loop door, records, prompts, pad.

func test_shell_reload_one_at_a_time() -> void:
	var a := Ammo.new(Weapons.make("scatter"))
	assert_true(a.by_shell())
	a.rounds = 1
	assert_true(a.reload())
	a.update(a.reload_step() + 0.01)
	assert_eq(a.rounds, 2); assert_true(a.reloading())
	a.update(a.reload_step() * 2.0)
	assert_eq(a.rounds, 4)
	a.update(10.0)
	assert_eq(a.rounds, a.weapon.mag_size); assert_false(a.reloading())

func test_shell_reload_interrupt_rules() -> void:
	var a := Ammo.new(Weapons.make("scatter"))
	a.rounds = 0; a.reload()
	assert_false(a.can_interrupt(), "nothing in the tube yet")
	a.update(a.reload_step() + 0.01)
	assert_true(a.can_interrupt())
	a.cancel_reload()
	assert_true(a.can_fire()); assert_eq(a.rounds, 1)
	var m := Ammo.new(Weapons.make("rifle"))
	m.rounds = 5; m.reload()
	assert_false(m.can_interrupt(), "magazine reloads are all-or-nothing")

func test_shell_reload_stops_when_reserve_runs_out() -> void:
	var a := Ammo.new(Weapons.make("scatter"))
	a.rounds = 0; a.reserve = 2; a.reload()
	a.update(60.0)
	assert_eq(a.rounds, 2); assert_eq(a.reserve, 0); assert_false(a.reloading())

func test_ammo_never_negative() -> void:
	var a := Ammo.new(Weapons.make("sidearm"))
	for i in 2000:
		if a.can_fire(): a.fire()
		else: a.update(5.0)
		assert_true(a.rounds >= 0 and a.reserve >= 0)
	assert_true(a.is_empty())
	assert_false(a.can_fire()); assert_false(a.reload())

func test_switch_cancels_reload_and_only_held_gun_reloads() -> void:
	var l := Loadout.new(Weapons.make("sidearm"))
	l.give(Weapons.make("rifle")); l.current = 0
	l.ammo().rounds = 2; l.ammo().reload()
	l.cycle()
	assert_false(l.slots[0].reloading()); assert_eq(l.slots[0].rounds, 2)
	l.slots[0].reload()          # a reload left running on the holstered gun must not progress
	l.update(30.0)
	assert_eq(l.slots[0].rounds, 2)

func test_forge_lock_survives_switching() -> void:
	var l := Loadout.new(Weapons.make("sidearm"))
	l.give(Weapons.make("rifle"))
	var held: Ammo = l.ammo(); held.locked = true
	l.cycle(); l.cycle(); l.update(30.0)
	assert_true(held.reloading()); assert_false(held.can_fire())
	held.swap(held.weapon.upgraded_version())
	assert_false(held.locked); assert_true(held.can_fire())

func test_upgrade_keeps_pump_action() -> void:
	var w := Weapons.make("scatter").upgraded_version()
	assert_gt(w.shell_reload, 0.0); assert_lt(w.shell_reload, Weapons.make("scatter").shell_reload)

func test_three_core_weapons_are_distinct() -> void:
	var p := Weapons.make("sidearm"); var r := Weapons.make("rifle"); var s := Weapons.make("scatter")
	assert_false(p.automatic); assert_true(r.automatic); assert_gt(s.pellets, 1)
	assert_lt(r.fire_interval, p.fire_interval); assert_gt(s.fire_interval, p.fire_interval)
	assert_gt(s.spread_deg, r.spread_deg); assert_gt(s.recoil, r.recoil)
	assert_true(Weapons.WALL_PRICES.has("rifle") and Weapons.WALL_PRICES.has("scatter"))
	for w in [p, r, s]:
		assert_gt(w.mag_size, 0); assert_gt(w.reserve_mags, 0); assert_gt(w.reload_time, 0.0)

func test_service_door_opens_both_rooms_once() -> void:
	var f := Facility.new(); var e := Economy.new(2500)
	assert_eq(f.buy_door("service", e), ""); assert_eq(e.points, 1500)
	assert_true(f.open_areas.get("cold", false) and f.open_areas.get("lab", false))
	assert_eq(f.buy_door("service", e), "Already open"); assert_eq(e.points, 1500)
	assert_true(f.active_windows().has("w_cold") and f.active_windows().has("w_lab"))

func test_price_text() -> void:
	assert_eq(Game.price_text(750, "Open Generator Wing", 750), "Open Generator Wing — 750 points")
	assert_eq(Game.price_text(500, "Open Generator Wing", 750), "Open Generator Wing — 750 points (need 250 more)")

func test_countdown_text() -> void:
	assert_eq(Hud.countdown_text(1, 3.2), "Round 1 in 4")
	assert_eq(Hud.countdown_text(5, 0.0), "")

func test_records_tracked_independently() -> void:
	var path := "user://test_v8_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var h := HighScore.new(path)
	assert_true(h.submit({"round": 5, "kills": 60, "points": 4000}))
	assert_true(h.new_round and h.new_score)
	# a shorter run with a bigger score: not the best run, but a new best score
	var h2 := HighScore.new(path)
	assert_false(h2.submit({"round": 3, "kills": 80, "points": 9000}))
	assert_false(h2.new_round); assert_true(h2.new_score)
	var rec := HighScore.new(path).load_records()
	assert_eq(int(rec.round), 5); assert_eq(int(rec.score), 9000)
	assert_eq(int(HighScore.new(path).load_best().round), 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_pad_axis_deadzone() -> void:
	assert_eq(Player.pad_axis(0.1), 0.0); assert_eq(Player.pad_axis(-0.2), 0.0)
	assert_almost_eq(Player.pad_axis(1.0), 1.0, 0.001); assert_almost_eq(Player.pad_axis(-1.0), -1.0, 0.001)
	assert_gt(Player.pad_axis(0.6), 0.0); assert_lt(Player.pad_axis(0.6), 0.6)

func test_auto_pause_rule() -> void:
	assert_true(Game.wants_auto_pause(true, false, false, false))
	assert_false(Game.wants_auto_pause(false, false, false, false))
	assert_false(Game.wants_auto_pause(true, true, false, false))
	assert_false(Game.wants_auto_pause(true, false, true, false))
	assert_false(Game.wants_auto_pause(true, false, false, true))

func test_branding() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Victor Zombies")
	var m = load("res://scripts/main.gd")
	assert_eq(m.TITLE, "VICTOR ZOMBIES"); assert_eq(m.BYLINE, "By Victorious Framework")
