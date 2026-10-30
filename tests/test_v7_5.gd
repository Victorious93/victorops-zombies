extends GutTest

func _skel(v: String) -> Skeleton3D:
	var c := ModelLib.character(v, Zombie.HEIGHT); autofree(c[0])
	return c[0].find_children("*", "Skeleton3D", true, false)[0]

func test_zombie_b_has_fitted_outfits_on_real_bones():
	var sk := _skel("zombie_b")
	for o in ["worker", "labcoat", "guard"]:
		var parts := Zombie.outfit_parts(o, "zombie_b")
		assert_gt(parts.size(), 2, o)
		for pt in parts: assert_gt(sk.find_bone(pt[0]), -1, "%s on %s" % [o, pt[0]])
	assert_eq(Zombie.outfit_parts("rags", "zombie_b").size(), 0)

func test_outfits_are_rounded_not_boxes():
	for v in ["zombie_a", "zombie_b"]:
		for o in ["worker", "labcoat", "guard"]:
			for pt in Zombie.outfit_parts(o, v):
				if pt[1] != "patch": assert_false(Zombie.part_mesh(pt[1]) is BoxMesh, "%s %s %s" % [v, o, pt[1]])
	assert_true(Zombie.part_mesh("shell") is CylinderMesh); assert_true(Zombie.part_mesh("dome") is SphereMesh)

func test_hats_sit_on_the_skull_not_inside_it():
	# measured skull tops (height-normalised): zombie_a ~1.8, zombie_b box head ~1.58 (v7.6 refit)
	for v in ["zombie_a", "zombie_b"]:
		for o in ["worker", "guard"]:
			var dome: Array = Zombie.outfit_parts(o, v).filter(func(p): return p[1] == "dome")[0]
			var top: float = dome[3].y + dome[2].y * 0.5
			assert_gt(top, 1.74 if v == "zombie_a" else 1.62, "%s %s hat crown clears the skull" % [v, o])
			assert_lt(dome[3].y, 1.82, "%s %s hat not floating" % [v, o])

func test_zombie_b_keeps_its_outfit():
	var z := Zombie.new(); z.variant = "zombie_b"; autofree(z)
	z.set_outfit("guard"); assert_eq(z.outfit, "guard")
