extends GutTest
## v7.6: procedural crawl for rigs without a Crawl clip, hats fitted to the skull, fake-baked light pools.

func _ellipsoid_y(dome: Array, x: float, z: float) -> float:
	# top surface height of the dome ellipsoid at (x, z); -INF outside its footprint
	var c: Vector3 = dome[3]; var r: Vector3 = dome[2] * 0.5
	var q := 1.0 - pow((x - c.x) / r.x, 2) - pow((z - c.z) / r.z, 2)
	return c.y + r.y * sqrt(q) if q > 0.0 else -INF

func test_zombie_a_hats_hug_the_measured_skull():
	# measured zombie_a skull top (normalised space): (x, z) -> y
	var skull := {Vector2(0, 0.0): 1.78, Vector2(0, 0.15): 1.80, Vector2(0, 0.3): 1.77, Vector2(0.15, 0.12): 1.78, Vector2(-0.15, 0.12): 1.78, Vector2(0.25, 0.12): 1.74}
	for o in ["worker", "guard"]:
		var dome: Array = Zombie.outfit_parts(o, "zombie_a").filter(func(p): return p[1] == "dome")[0]
		for xz in skull:
			var y := _ellipsoid_y(dome, xz.x, xz.y)
			assert_gt(y, skull[xz] + 0.0, "%s dome covers skull at %s" % [o, xz])
			assert_lt(y, skull[xz] + 0.12, "%s dome not floating at %s" % [o, xz])

func test_brim_sits_on_the_dome_not_below_it():
	for v in ["zombie_a", "zombie_b"]:
		for o in ["worker", "guard"]:
			var parts := Zombie.outfit_parts(o, v)
			var dome: Array = parts.filter(func(p): return p[1] == "dome")[0]
			var brim: Array = parts.filter(func(p): return p[1] == "brim")[0]
			assert_gt(brim[3].y, dome[3].y - 0.01, "%s %s brim at the dome's rim" % [v, o])

func test_hatted_zombies_twitch_less():
	var z := Zombie.new(); z.variant = "zombie_a"; autofree(z)
	z.outfit = "guard"; assert_true(z.has_hat())
	z.outfit = "labcoat"; assert_false(z.has_hat())
	var zp := ZombiePose.new(); autofree(zp)
	assert_eq(zp.head_twitch, 1.0); assert_false(zp.crawl)

func test_crawl_constants_lay_body_prone():
	assert_gt(Zombie.CRAWL_PITCH, 1.2); assert_lt(Zombie.CRAWL_PITCH, PI / 2)
	assert_lt(Zombie.CRAWL_LIFT, 0.3)

func test_light_pool_texture_is_radial_and_fades_out():
	var t := FacilityMap.pool_texture()
	assert_eq(t.fill, GradientTexture2D.FILL_RADIAL)
	assert_eq(t.gradient.colors[t.gradient.colors.size() - 1], Color(0, 0, 0, 1), "edge is black (additive = no light)")
	var m := FacilityMap.pool_material(Color(1, 0.9, 0.75))
	assert_eq(m.blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
	assert_eq(m.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)

func test_light_pool_follows_its_lamp():
	var fm := FacilityMap.new(); autofree(fm)
	var l := fm.light(Vector3(3, 3.7, 2), Color(1, 0.9, 0.75), 2.2, 12.0, false)
	assert_eq(fm.light_pools.size(), 1)
	var pool: MeshInstance3D = fm.light_pools[0]
	assert_eq(pool.get_parent(), l, "child of the lamp so it toggles with power")
	assert_almost_eq(l.position.y + pool.position.y, 0.01, 0.001, "on the floor")
	fm.light(Vector3(0, 1.2, 0), Color.WHITE, 2.0, 10.0, false)
	assert_eq(fm.light_pools.size(), 1, "low fill lights get no pool")

func test_zombie_b_has_no_crawl_clip_but_can_crawl():
	var c = ModelLib.character("zombie_b", 1.8)
	autofree(c[0])
	assert_false(c[1].has_animation("Crawl"), "zombie_b needs the procedural crawl")
	var sk: Skeleton3D = c[0].find_children("*", "Skeleton3D", true, false)[0]
	for b in ["Body", "Leg.L", "Leg.R", "Arm.L", "Arm.R", "Head"]: assert_gt(sk.find_bone(b), -1, b)
