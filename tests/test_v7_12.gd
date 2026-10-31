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

# ---- beats ----
func test_beat_rotation() -> void:
	assert_eq(Beats.for_round(1), "beat_grave_shift"); assert_eq(Beats.for_round(2), "beat_grave_shift")
	assert_eq(Beats.for_round(3), "beat_static_ward"); assert_eq(Beats.for_round(5), "beat_low_tide")
	assert_eq(Beats.for_round(7), "beat_grave_shift")
	for id in Beats.IDS:
		assert_between(int(Beats.BPM[id]), 85, 95)

func test_beats_loop_seamlessly() -> void:
	for id in Beats.IDS:
		var s = Beats.load_loop(id)
		assert_true(s is AudioStreamOggVorbis, id)
		assert_true(s.loop, id + " loops")
		var want := Beats.loop_seconds(id)
		assert_between(want, 30.0, 60.0)
		assert_almost_eq(s.get_length(), want, 0.06, id + " is whole bars")

func test_beats_setting_roundtrip() -> void:
	var st := GameSettings.new(); st.beats = false
	var st2 := GameSettings.new(); st2.from_dict(st.to_dict())
	assert_false(st2.beats)

# ---- hidden room ----
func test_room_reveal() -> void:
	var h := HiddenRoom.new()
	assert_false(h.hit(HiddenRoom.CRACK_HP - 1.0)); assert_false(h.revealed)
	assert_true(h.hit(5.0)); assert_true(h.revealed)
	assert_false(h.hit(999.0), "reveals only once")
	assert_true(HiddenRoom.inside(HiddenRoom.PEDESTAL_POS)); assert_true(HiddenRoom.inside(HiddenRoom.VAULT_POS + Vector3(0.3, 0, 0)))
	assert_false(HiddenRoom.inside(Vector3(0, 0, -20)))

# ---- armor ----
func test_armor_tiers_and_absorb() -> void:
	var a := ArmorState.new(); var e := Economy.new(); e.points = 20000
	assert_eq(a.absorb(30.0), 30.0, "no armor -> all to health")
	assert_true(a.buy_tier(e)); assert_eq(a.max_value, 250); assert_eq(a.value, 250.0)
	assert_almost_eq(a.absorb(100.0), 0.0, 0.001); assert_eq(a.value, 150.0)
	assert_true(a.buy_tier(e)); assert_true(a.buy_tier(e)); assert_eq(a.tier, 3); assert_eq(a.max_value, 400)
	assert_false(a.buy_tier(e), "3 tiers only")
	assert_eq(e.points, 20000 - 2000 - 3500 - 5500)
	a.value = 50.0
	assert_almost_eq(a.absorb(150.0), 100.0, 0.001, "plate breaks: rest goes through")
	assert_eq(a.value, 0.0)

func test_armor_tier_needs_points() -> void:
	var a := ArmorState.new(); var e := Economy.new(); e.points = 1000
	assert_false(a.buy_tier(e)); assert_eq(a.tier, 0); assert_eq(e.points, 1000)

# ---- alien LMG + Rift Bench ----
func test_alien_lmg_stats() -> void:
	var w := Weapons.make(Weapons.ALIEN)
	assert_eq(w.mag_size, 500); assert_true(w.automatic)
	var lmg := Weapons.make("lmg")
	assert_lt(w.fire_interval, lmg.fire_interval, "faster than the Grinder")
	assert_gt(w.reload_time, lmg.reload_time, "longer reload")
	assert_lt(w.move_mult(), lmg.move_mult(), "slower to move with")
	assert_gt(w.spin_mult(0.0), w.spin_mult(1.0)); assert_eq(w.spin_mult(1.0), 1.0)
	assert_false(Weapons.ALL_IDS.has(Weapons.ALIEN), "not in the crate")
	assert_eq(Weapons.at(Weapons.ALIEN, 1).spin_up, w.spin_up)
	for snd in ["shot_reaper_v12", "reload_reaper_v12", "armor_hit_v12", "armor_break_v12", "hidden_reveal_v12"]:
		assert_true(FileAccess.file_exists("res://audio/%s.wav" % snd), snd)

func test_alien_purchase_and_rift_bench() -> void:
	var e := Economy.new(); e.points = Weapons.ALIEN_PRICE - 1
	assert_false(e.spend(Weapons.ALIEN_PRICE))
	e.points = Weapons.ALIEN_PRICE + RiftBench.COST
	assert_true(e.spend(Weapons.ALIEN_PRICE))
	var lo := Loadout.new(Weapons.make("sidearm")); lo.give(Weapons.make(Weapons.ALIEN))
	assert_gte(lo.has(Weapons.ALIEN), 0)
	var up := RiftBench.upgrade(Weapons.make("smg"), e)
	assert_not_null(up); assert_eq(up.tier, 1); assert_eq(e.points, 0)
	assert_eq(RiftBench.cost_for(up), -1, "Mk.3 is Forge-only")
	assert_lt(RiftBench.COST, OverchargeForge.new().cost)

func test_reaper_heat_glow_is_capped() -> void:
	for h in [-1.0, 0.0, 0.5, 1.0, 5.0, 100.0]:
		var e := Viewmodel.heat_energy(h)
		assert_between(e, Viewmodel.HEAT_EMIT_MIN, Viewmodel.HEAT_EMIT_MAX)
		assert_between(Viewmodel.heat_core_alpha(h), Viewmodel.HEAT_CORE_ALPHA_MIN, Viewmodel.HEAT_CORE_ALPHA_MAX)
		assert_between(Viewmodel.heat_core_scale(h), 1.0, Viewmodel.HEAT_CORE_SCALE_MAX)
	assert_true(Viewmodel.HEAT_EMIT_MAX <= 1.0, "emission cap stays readable")
	var hot := Viewmodel.heat_color(1.0)
	assert_true(hot.r > hot.g and hot.g > hot.b, "full heat is orange, not white")
	assert_true(maxf(hot.r, maxf(hot.g, hot.b)) * Viewmodel.HEAT_EMIT_MAX < 1.0, "never blows out to white")
	var m := Viewmodel.alien_material()
	assert_true(m.emission_energy_multiplier <= Viewmodel.HEAT_EMIT_MAX)

func test_reaper_flash_light_capped() -> void:
	assert_true(Viewmodel.ALIEN_FLASH_MAX <= 1.5, "muzzle light capped for the 500-round LMG")
	assert_false(Viewmodel.alien_material().rim_enabled, "no rim wash-out")

func test_reaper_body_material_survives_rebake() -> void:
	var vm := Viewmodel.new(); add_child_autofree(vm); vm.setup(Color(0.2, 0.25, 0.2))
	await wait_frames(2)
	vm.set_weapon(Weapons.make("rifle"))
	vm.set_weapon(Weapons.make(Weapons.ALIEN))
	await wait_frames(5)
	var m := vm.gun_body_material() as StandardMaterial3D
	assert_not_null(m, "gun body has a material")
	assert_eq(m, vm.alien_mat, "body draws with the alien material")
	assert_almost_eq(m.albedo_color.r, 0.04, 0.01); assert_almost_eq(m.albedo_color.g, 0.07, 0.01)
	assert_almost_eq(m.albedo_color.b, 0.05, 0.01)
	if vm.flash: assert_ne(vm.flash.material_override, vm.alien_mat, "muzzle flash never shares the gun material")
	assert_true(vm.gun.scale.x <= Viewmodel.ALIEN_SCALE + 0.001, "reaper is shrunk")
	# switching away and back (a rebake of the viewmodel) still ends on the alien material
	vm.set_weapon(Weapons.make("rifle")); vm.set_weapon(Weapons.make(Weapons.ALIEN))
	await wait_frames(3)
	assert_eq(vm.gun_body_material(), vm.alien_mat)
	assert_almost_eq((vm.gun_body_material() as StandardMaterial3D).albedo_color.r, 0.04, 0.01)

func test_fx_splats_and_sparks_are_pooled() -> void:
	var fx := Fx.new(); add_child_autofree(fx)
	for i in 200: fx.sparks(Vector3.ZERO, Vector3.UP, Color(0.5, 0, 0), 4)
	assert_true(fx.sparks_alive.size() <= Fx.MAX_SPARK_EMITTERS)
	assert_true(Fx.MAX_SPLATS <= 64)

func test_dark_puffs_skip_near_camera() -> void:
	var fx := Fx.new(); add_child_autofree(fx)
	var cam := Camera3D.new(); add_child_autofree(cam); cam.current = true
	await wait_frames(1)
	assert_true(fx.near_camera(cam.global_position + Vector3(0, 0, -1)))
	fx.sparks(cam.global_position + Vector3(0, 0, -1), Vector3.UP, Color(0.42, 0.4, 0.37), 6)
	assert_eq(fx.sparks_alive.size(), 0, "no dark puff in the player's face")
	fx.sparks(cam.global_position + Vector3(0, 0, -6), Vector3.UP, Color(0.42, 0.4, 0.37), 6)
	assert_eq(fx.sparks_alive.size(), 1)
