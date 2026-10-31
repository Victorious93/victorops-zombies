extends GutTest
## v7.14: natural-tone rim/wound overlay, blood trails, bigger Sentry Pod, zombie_b ZRun, bot gear use, atmosphere.

# ---------------------------------------------------------------- rim / wound
func test_rim_overlay_not_orange():
	var c := Zombie.RIM_COLOR
	assert_gt(c.b, c.r, "cool rim: blue over red")
	assert_gt(c.g, c.r, "cool rim: green over red")
	assert_lt(c.s, 0.45, "desaturated, never a warm glow")

func test_skin_material_has_no_light_dependent_rim_and_unscaled_uv():
	var src := StandardMaterial3D.new()
	for ty in ZombieTypes.ALL:
		var m := Zombie._skin_mat(src, ty, 0)
		assert_false(m.rim_enabled, "%s: lamp-coloured rim off (was the orange cast)" % ty)
		assert_eq(m.uv1_scale, Vector3.ONE, "%s: UV1 unscaled so the atlas samples the real skin cell" % ty)

func test_grime_texture_is_neutral():
	var img := Zombie.grime_tex().get_image()
	var red_cast := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p := img.get_pixel(x, y)
			if p.r - p.g > 0.08: red_cast += 1
	assert_eq(red_cast, 0, "no red/orange blotches multiplied into the skin")

func test_skins_stay_grey_green():
	var src := StandardMaterial3D.new()
	for i in Zombie.SKINS.size():
		var c := Zombie._skin_mat(src, "walker", i).albedo_color
		assert_true(c.g >= c.r - 0.03, "skin %d is not orange (g %.2f r %.2f)" % [i, c.g, c.r])

func test_wound_levels():
	assert_eq(Zombie.wound_level(1.0), 0)
	assert_eq(Zombie.wound_level(0.6), 1)
	assert_eq(Zombie.wound_level(0.3), 2)
	assert_eq(Zombie.wound_level(0.05), 3)
	assert_eq(Zombie.wound_level(0.0), 3)

func test_rim_materials_shared_and_graded():
	assert_true(ResourceLoader.exists("res://shaders/zombie_rim.gdshader"))
	var a := Zombie.rim_material(0); var b := Zombie.rim_material(0)
	assert_same(a, b, "shared per level (batches)")
	assert_eq(float(a.get_shader_parameter("wound")), 0.0)
	assert_eq(float(Zombie.rim_material(3).get_shader_parameter("wound")), 1.0)
	assert_lt(float(Zombie.rim_material(1).get_shader_parameter("wound")), float(Zombie.rim_material(2).get_shader_parameter("wound")))
	assert_same(Zombie.rim_material(99), Zombie.rim_material(3), "clamped")

func test_rim_shader_is_unshaded_and_lamp_independent():
	var code: String = (load("res://shaders/zombie_rim.gdshader") as Shader).code
	assert_string_contains(code, "unshaded")
	assert_false(code.contains("LIGHT"), "no light() pass: lamp colour can't tint it")

# ---------------------------------------------------------------- blood trails
func test_trail_spacing_rules():
	assert_eq(BloodTrail.spacing(1.0, false), INF, "healthy walkers don't bleed")
	assert_eq(BloodTrail.spacing(0.7, false), INF)
	assert_lt(BloodTrail.spacing(0.1, false), BloodTrail.spacing(0.5, false), "worse wounds drip more often")
	assert_eq(BloodTrail.spacing(1.0, true), BloodTrail.CRAWL_SPACING, "crawlers always smear")
	assert_lt(BloodTrail.CRAWL_SPACING, BloodTrail.SPACING)

func test_trail_should_drop():
	assert_false(BloodTrail.should_drop(100.0, 0.9, false))
	assert_true(BloodTrail.should_drop(BloodTrail.CRAWL_SPACING, 1.0, true))
	assert_false(BloodTrail.should_drop(0.1, 0.2, false))
	assert_true(BloodTrail.should_drop(3.0, 0.2, false))

func test_trail_mark_size():
	var crawl := BloodTrail.mark_size(0.5, true)
	assert_gt(crawl.y, crawl.x, "smear is elongated along travel")
	assert_gt(BloodTrail.mark_size(0.05, false).x, BloodTrail.mark_size(0.55, false).x, "heavier bleeding, bigger drips")

func test_trail_ring_caps_and_recycles():
	var r := BloodTrail.Ring.new(4)
	var got := []
	for i in 10: got.append(r.take())
	assert_eq(got, [0, 1, 2, 3, 0, 1, 2, 3, 0, 1])
	assert_eq(r.used, 4)
	assert_lte(BloodTrail.MAX_TRAIL, 48, "mobile budget")

func test_fx_trail_pool_never_exceeds_cap():
	var fx := Fx.new(); add_child_autofree(fx)
	for i in BloodTrail.MAX_TRAIL * 3:
		fx.trail_mark(Vector3(i * 0.3, 0, 0), Vector3.FORWARD, Vector2(0.4, 0.6))
	assert_eq(fx.trail_marks.size(), BloodTrail.MAX_TRAIL)
	var mats := {}
	for m in fx.trail_marks: mats[m.material_override] = true
	assert_eq(mats.size(), 1, "one shared material")
	assert_eq((fx.trail_marks[0] as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

# ---------------------------------------------------------------- sentry
func test_sentry_is_bigger_and_readable():
	assert_gt(SentryModel.SCALE, 1.3)
	assert_gt(SentryModel.HEAD_Y, 1.1, "head well above the old 0.85 m")
	var p := SentryModel.build(); var root: Node3D = p.root; add_child_autofree(root)
	for k in ["head", "bar", "bar_mat", "beacon", "ring", "light"]: assert_true(p.has(k), k)
	assert_false((p.light as OmniLight3D).shadow_enabled, "no shadowed light on phones")
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	assert_between(meshes.size(), 10, 30, "chunky but cheap")
	var aabb := AABB()
	for m in meshes:
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		aabb = b if aabb.size == Vector3.ZERO else aabb.merge(b)
	assert_gt(aabb.size.y, 1.2, "≈1.3 m tall")

func test_sentry_status_colours():
	assert_gt(SentryModel.status_color(1.0).g, SentryModel.status_color(1.0).r, "full = green")
	var mid := SentryModel.status_color(0.35); assert_gt(mid.r, 0.9); assert_gt(mid.g, 0.5)
	var low := SentryModel.status_color(0.1); assert_gt(low.r, low.g * 3.0, "nearly spent = red")

func test_sentry_bar_tracks_life_and_ammo():
	var p := SentryModel.build(); add_child_autofree(p.root)
	var st := Backpack.Sentry.new()
	SentryModel.update_visuals(p, st, 0.0)
	assert_almost_eq((p.bar as Node3D).scale.x, 1.0, 0.001)
	st.ammo = Backpack.SENTRY_AMMO / 4
	assert_almost_eq(SentryModel.remaining(st), 0.25, 0.01, "min of life and ammo")
	SentryModel.update_visuals(p, st, 0.0)
	assert_almost_eq((p.bar as Node3D).scale.x, 0.25, 0.01)
	st.life = 0.0
	assert_eq(SentryModel.remaining(st), 0.0)

# ---------------------------------------------------------------- zombie_b run
func _b_run() -> Array:
	var c = ModelLib.character("zombie_b", 1.8); var m: Node3D = c[0]; add_child_autofree(m)
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	return [ap, ModelLib.anim_name(ap, ["Run"])]

func test_zrun_installs_once():
	var r := _b_run(); var ap: AnimationPlayer = r[0]
	assert_ne(r[1], "", "zombie_b has a stock Run")
	assert_eq(ZombieRunClip.install(ap, r[1]), ZombieRunClip.NAME)
	assert_eq(ZombieRunClip.install(ap, r[1]), ZombieRunClip.NAME, "idempotent")
	assert_true(ap.has_animation(ZombieRunClip.NAME))
	assert_eq(ap.get_animation(ZombieRunClip.NAME).loop_mode, Animation.LOOP_LINEAR)
	assert_eq(ZombieRunClip.install(null, "x"), "")

func test_zrun_reshapes_arms_body_not_source():
	var r := _b_run(); var ap: AnimationPlayer = r[0]
	var src := ap.get_animation(r[1]); var a := ZombieRunClip.build(src)
	assert_almost_eq(a.length, src.length, 0.001, "same cycle so feet match ground speed")
	var changed := {}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D: continue
		var b := ZombieRunClip.bone_of(a.track_get_path(t))
		var q0: Quaternion = src.track_get_key_value(t, 0); var q1: Quaternion = a.track_get_key_value(t, 0)
		changed[b] = q0.angle_to(q1) > 0.05
	assert_true(changed.get("Body", false), "torso hunched")
	assert_true(changed.get("Arm.L", false) and changed.get("Arm.R", false), "arms reach forward")
	assert_false(changed.get("Leg.R", true), "one leg untouched (limp is asymmetric)")

func test_zrun_arm_swing_damped():
	var r := _b_run(); var src: Animation = (r[0] as AnimationPlayer).get_animation(r[1]); var a := ZombieRunClip.build(src)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D or ZombieRunClip.bone_of(a.track_get_path(t)) != "Arm.L": continue
		var n := a.track_get_key_count(t)
		var span_src := (src.track_get_key_value(t, 0) as Quaternion).angle_to(src.track_get_key_value(t, n / 2))
		var span_new := (a.track_get_key_value(t, 0) as Quaternion).angle_to(a.track_get_key_value(t, n / 2))
		assert_lt(span_new, span_src * 0.6, "flail, not a jogger's pump")

func test_zombie_b_uses_zrun():
	var z := Zombie.new(); z.variant = "zombie_b"; z.drop_in = true
	add_child_autofree(z)
	assert_eq(z.anims.get("Run", ""), ZombieRunClip.NAME)
	var za := Zombie.new(); za.variant = "zombie_a"; za.drop_in = true
	add_child_autofree(za)
	assert_ne(za.anims.get("Run", ""), ZombieRunClip.NAME, "zombie_a keeps its own keyframed run")

func test_zombie_gets_rim_overlay():
	var z := Zombie.new(); z.variant = "zombie_a"; z.drop_in = true
	add_child_autofree(z)
	var any := false
	for m in z.meshes:
		if (m as GeometryInstance3D).material_overlay == Zombie.rim_material(0): any = true
	assert_true(any, "healthy zombie wears the level-0 rim")

# ---------------------------------------------------------------- bot gear
func test_bot_picks_aegis_when_hurt_and_close():
	var bag := {"aegis": 1, "pulse": 1, "sentry": 1}
	assert_eq(BotDriver.pick_gadget(bag, 40.0, 1, 1, 1, false, 0), "aegis")
	assert_ne(BotDriver.pick_gadget(bag, 40.0, 1, 1, 1, true, 0), "aegis", "not while one is up")
	assert_eq(BotDriver.pick_gadget(bag, 90.0, 1, 1, 1, false, 0), "", "healthy, one close: save it")
	assert_eq(BotDriver.pick_gadget(bag, 90.0, 2, 2, 2, false, 0), "aegis", "two in arm's reach: shield up")

func test_bot_picks_pulse_for_crowd():
	assert_eq(BotDriver.pick_gadget({"pulse": 1}, 100.0, 0, 3, 3, false, 0), "pulse")
	assert_eq(BotDriver.PULSE_NEAR, Backpack.PULSE_RADIUS, "counts what the blast reaches")
	assert_eq(BotDriver.pick_gadget({"pulse": 1}, 100.0, 0, 1, 3, false, 0), "")

func test_bot_picks_sentry_for_horde_once():
	assert_eq(BotDriver.pick_gadget({"sentry": 1}, 100.0, 0, 0, 3, false, 0), "sentry")
	assert_eq(BotDriver.pick_gadget({"sentry": 1}, 100.0, 0, 0, 3, false, 1), "", "one pod at a time")
	assert_eq(BotDriver.pick_gadget({}, 10.0, 5, 5, 5, false, 0), "", "empty bag")

func test_bot_pickup_and_locker_rules():
	assert_true(BotDriver.want_pickup(5.0, 8.0))
	assert_false(BotDriver.want_pickup(5.0, 2.0), "not into a zombie's arms")
	assert_false(BotDriver.want_pickup(20.0, 99.0), "too far from the room")
	assert_true(BotDriver.want_locker(Backpack.LOCKER_PRICE + BotDriver.LOCKER_SPARE, 3, false))
	assert_false(BotDriver.want_locker(99999, 2, false), "early rounds: guns first")
	assert_false(BotDriver.want_locker(99999, 5, true), "bag full")
	assert_false(BotDriver.want_locker(Backpack.LOCKER_PRICE, 5, false), "keeps a reserve")

func test_backpack_slot_of():
	var b := Backpack.new()
	assert_eq(b.slot_of("aegis"), -1)
	b.add("sentry"); b.add("aegis")
	assert_eq(b.slot_of("aegis"), 1)
	b.use(1)
	assert_eq(b.slot_of("aegis"), -1)

# ---------------------------------------------------------------- atmosphere
func test_grade_and_cones_are_mobile_safe():
	assert_between(Game.SATURATION, 0.8, 0.98)
	assert_lt(FacilityMap.CONE_ALPHA, 0.12, "faint dust cones, not white pillars")
	var src := FileAccess.get_file_as_string("res://scripts/game/game.gd")
	assert_false(src.contains("volumetric_fog_enabled = true"), "no volumetric fog (not on mobile/compat)")
	assert_false(src.contains("ssr_enabled = true"))
