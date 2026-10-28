extends GutTest

func test_cannon_hip_sits_out_of_the_way():
	var h := Viewmodel.hip_pos("launcher")
	assert_gt(h.x, Viewmodel.HIP_POS.x); assert_lt(h.y, Viewmodel.HIP_POS.y); assert_lt(h.z, Viewmodel.HIP_POS.z)
	assert_eq(Viewmodel.hip_pos("rifle"), Viewmodel.HIP_POS)

func test_dead_helpers_removed():
	var src := FileAccess.get_file_as_string("res://scripts/game/viewmodel.gd")
	assert_false(src.contains("func underside_y")); assert_false(src.contains("func _rel("))

func test_light_zombies_get_every_outfit():
	var seen := {}
	for r in 8: seen[Zombie.pick_outfit("walker", r)] = true
	for o in Zombie.OUTFITS: assert_true(seen.has(o), o)
	assert_eq(Zombie.pick_outfit("brute", 1), "", "heavies keep armour plates")
	assert_eq(Zombie.pick_outfit("bloater", 1), "")

func test_outfit_parts_use_real_bones():
	var m = load("res://assets/models/zombie_a.glb").instantiate()
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	for o in ["worker", "labcoat", "guard"]:
		assert_gt(Zombie.outfit_parts(o).size(), 1, o)
		for pt in Zombie.outfit_parts(o): assert_gt(sk.find_bone(pt[0]), -1, "%s on %s" % [o, pt[0]])
	assert_eq(Zombie.outfit_parts("rags").size(), 0)
	m.free()

func test_leg_damage_always_makes_a_crawler():
	var src := FileAccess.get_file_as_string("res://scripts/game/zombie.gd")
	assert_false(src.contains('anims.has("Crawl") and hp > 0 and randf()'), "legs shot off => always crawls")
