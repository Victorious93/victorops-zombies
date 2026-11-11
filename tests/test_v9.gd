extends GutTest
## v9 (Victorious Framework): abandoned-town rebuild. Town kit batching, signage atlas, the Side Alley
## loop door, the camera-shake setting and the town art files.

func test_side_alley_door_closes_the_second_loop() -> void:
	var f := Facility.new(); var e := Economy.new(); e.points = 3000
	assert_true(Facility.DOORS.has("alley"))
	assert_false(f.active_windows().has("w_pump_s"))
	assert_eq(f.buy_door("alley", e), ""); assert_eq(e.points, 3000 - Facility.DOORS.alley.cost)
	assert_true(f.open_areas.get("pump", false) and f.open_areas.get("lab", false), "opens the rooms on both sides")
	assert_true(f.active_windows().has("w_pump_s") and f.active_windows().has("w_pump_e"))
	assert_eq(f.buy_door("alley", e), "Already open")

func test_every_door_has_a_town_label_and_every_window_an_area() -> void:
	for id in Facility.DOORS:
		assert_false(Facility.DOORS[id].label in ["Generator Wing", "Lab Corridor", "Cold Storage", "Loading Yard", "Pump Station"], id)
	var areas := {"intake": true}
	for id in Facility.DOORS:
		areas[Facility.DOORS[id].opens] = true
	for w in Facility.WINDOWS: assert_true(areas.has(Facility.WINDOWS[w]), w)

func test_town_kit_batches_boxes_by_material_and_cell() -> void:
	var root := Node3D.new(); add_child_autofree(root)
	var kit := TownKit.new(root)
	var a := StandardMaterial3D.new(); var b := StandardMaterial3D.new()
	for i in 20: kit.box(a, Vector3.ONE, Vector3(1 + i * 0.3, 0.5, 1))        # one 10 m cell, one material
	kit.box(b, Vector3.ONE, Vector3(2, 0.5, 2))
	kit.box(a, Vector3.ONE, Vector3(25, 0.5, 2))                              # another cell
	kit.outdoor = true; kit.box(a, Vector3.ONE, Vector3(3, 0.5, 3))           # skylit twin of the first batch
	kit.commit()
	assert_eq(root.get_child_count(), 4, "23 boxes -> 4 draw calls")
	var first := root.get_child(0) as MeshInstance3D
	assert_eq(first.mesh.surface_get_array_len(0), 20 * 36, "20 boxes merged into one surface")
	assert_eq(first.layers, TownKit.INDOOR_LAYER, "roofed geometry sits on the layer the dusk light skips")
	assert_eq((root.get_child(3) as MeshInstance3D).layers, 1)
	assert_eq(TownKit.INDOOR_LAYER & ViewmodelOverlay.LAYER, 0, "never the viewmodel layer")

func test_town_kit_box_faces_point_outwards() -> void:
	var root := Node3D.new(); add_child_autofree(root)
	var kit := TownKit.new(root)
	kit.box(StandardMaterial3D.new(), Vector3(2, 4, 6), Vector3(5, 2, 5), 0.7)
	kit.commit()
	var arr := (root.get_child(0) as MeshInstance3D).mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in range(0, v.size(), 3):
		var face_n := (v[i + 2] - v[i]).cross(v[i + 1] - v[i]).normalized()   # clockwise = front in Godot
		assert_gt(face_n.dot(n[i]), 0.99, "winding matches the normal")
		assert_gt(n[i].dot(v[i] - Vector3(5, 2, 5)), 0.0, "normal points away from the centre")

func test_sign_atlas_cells() -> void:
	assert_eq(TownKit.banner_uv("diner"), Rect2(0, 0, 0.5, 0.125))
	assert_eq(TownKit.banner_uv("curfew"), Rect2(0.5, 0.625, 0.5, 0.125))
	assert_eq(TownKit.poster_uv("special"), Rect2(0.75, 0.75, 0.25, 0.25))
	for id in TownKit.BANNERS: assert_true(TownKit.banner_uv(id).end.y <= 0.7501, id)

func test_town_art_is_shipped() -> void:
	for f in ["facade_brick", "facade_brick_emit", "facade_plaster", "facade_concrete", "skyline", "signs", "signs_emit", "glass_broken", "road_paint", "corrugated_albedo", "corrugated_normal", "vinyl_red"]:
		assert_true(ResourceLoader.exists("res://assets/town/%s.png" % f), f)

func test_lamps_know_if_they_are_under_a_roof() -> void:
	var fm := FacilityMap.new(); autofree(fm)
	assert_true(fm.in_roofed(0, 0), "diner"); assert_true(fm.in_roofed(18, -18), "garage"); assert_true(fm.in_roofed(18, 0), "store")
	assert_false(fm.in_roofed(0, -18), "back alley is open air"); assert_false(fm.in_roofed(36, 0), "main street"); assert_false(fm.in_roofed(36, 20), "courtyard")

func test_camera_shake_setting_round_trips_and_clamps() -> void:
	var s := GameSettings.new()
	assert_eq(s.shake, 1.0)
	s.shake = 0.0
	var t := GameSettings.new(); t.from_dict(s.to_dict())
	assert_eq(t.shake, 0.0, "shake can be switched off")
	t.from_dict({"shake": 9.0}); assert_eq(t.shake, 1.5)

func test_dusk_fog_is_a_thin_haze() -> void:
	assert_gt(Game.BASE_FOG.b, Game.BASE_FOG.r, "blue-gray, not black")
	assert_gt(Game.AMBIENT_OFF, 0.4, "silhouettes read before the power is on")
	assert_lt(Game.AMBIENT_OFF, Game.AMBIENT_ON)
