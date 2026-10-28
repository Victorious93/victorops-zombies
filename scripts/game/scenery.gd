class_name Scenery
extends RefCounted
## v7 scenery dressing for the Blackwater Research Annex: CC0 Quaternius props (poly.pizza), broken
## parapets for varied wall heights, fire barrels, procedural (original) blood/crack/grime decals,
## ground mist cards, MultiMesh grass and dead trees. Mobile-safe: no volumetrics, MultiMesh clutter,
## visibility-range culling on every prop. Deterministic (seeded) so screenshots are comparable.

var map: FacilityMap
var rng := RandomNumberGenerator.new()
static var _decal_tex := {}

func _init(m: FacilityMap) -> void:
	map = m; rng.seed = 7707

func build() -> void:
	_parapets()
	_clutter()
	_fire_barrels()
	_decals()
	_mist()
	_grass()
	_height_fog()

# ---------------------------------------------------------------- geometry
## Broken brick parapets + pilasters on the perimeter so the skyline is not one flat 4 m line.
func _parapets() -> void:
	var runs := [[Vector2(-10, 10), Vector2(-10, -26)], [Vector2(-10, 10), Vector2(26, 10)],
		[Vector2(-10, -26), Vector2(26, -26)], [Vector2(46, 10), Vector2(46, -16)],
		[Vector2(26, 30), Vector2(46, 30)], [Vector2(46, 30), Vector2(46, 10)]]
	for r in runs:
		var a: Vector2 = r[0]; var b: Vector2 = r[1]
		var along_x := absf(a.y - b.y) < 0.01
		var len := a.distance_to(b); var dir := (b - a).normalized()
		var s := 0.0
		while s < len - 0.5:
			var w := rng.randf_range(1.5, 4.5); w = minf(w, len - s)
			var h := rng.randf_range(0.0, 2.2) if rng.randf() < 0.75 else 0.0
			if h > 0.2:
				var mid := a + dir * (s + w / 2.0)
				var size := Vector3(w, h, 0.5) if along_x else Vector3(0.5, h, w)
				var n := map.box(size, Vector3(mid.x, FacilityMap.H + h / 2.0, mid.y), map.mats.wall_ext, false)
				n.rotation.z = rng.randf_range(-0.04, 0.04) if along_x else 0.0
			s += w
		# pilasters every ~6 m (layered depth on the facade)
		var k := 3.0
		while k < len:
			var p := a + dir * k
			var ps := Vector3(0.6, FacilityMap.H + 0.6, 0.7) if along_x else Vector3(0.7, FacilityMap.H + 0.6, 0.6)
			map.box(ps, Vector3(p.x, ps.y / 2.0, p.y), map.mats.wall_low, false)
			k += rng.randf_range(5.0, 7.5)

# ---------------------------------------------------------------- props
func _p(name: String, size: float, pos: Vector3, rot := 0.0, by_h := false, collide := false) -> Node3D:
	return map.prop(("props/" + name) if ResourceLoader.exists("res://assets/models/props/%s.glb" % name) else name, size, pos, rot if rot != 0.0 else rng.randf_range(-PI, PI), by_h, collide)

func _clutter() -> void:
	# Intake hall: overturned furniture, papers, trash
	_p("couch", 2.0, Vector3(-7.6, 0, 3.5), 1.2, false, true)
	_p("debris_papers", 1.2, Vector3(-2, 0, -3)); _p("debris_papers", 1.0, Vector3(3, 0, 4))
	_p("debris_papers", 1.0, Vector3(16, 0, 0)); _p("debris_papers", 1.0, Vector3(0, 0, -16))
	_p("trashcan", 0.9, Vector3(8.6, 0, 8.4), 0.0, true, true)
	_p("cardboard_boxes", 1.2, Vector3(-8.4, 0, -8.2), 0.0, false, true)
	_p("debris_pile", 1.6, Vector3(-8.3, 0, 8.0)); _p("debris_pile", 1.3, Vector3(8.3, 0, -8.4))
	# generator wing / cold storage
	_p("pallet_broken", 1.3, Vector3(-7.5, 0, -12.5)); _p("tires", 1.1, Vector3(7.6, 0, -24.2), 0.0, false, true)
	_p("cardboard_boxes", 1.1, Vector3(22.8, 0, -24.0), 0.0, false, true)
	_p("debris_pile", 1.4, Vector3(14, 0, -24.6)); _p("traffic_barrier", 1.8, Vector3(-4, 0, -12.0), 0.1, false, true)
	# lab
	_p("couch", 1.8, Vector3(24.5, 0, 7.5), PI, false, true); _p("trashcan", 0.9, Vector3(11.0, 0, 8.6), 0.0, true, true)
	# loading yard: wrecks, dumpsters, cones, lamp posts
	_p("sports_car", 4.2, Vector3(43.0, 0, -7.0), 1.9, false, true)
	_p("dumpster", 2.0, Vector3(27.6, 0, -14.6), PI / 2, false, true)
	_p("tires", 1.1, Vector3(34.0, 0, 4.0)); _p("traffic_cone", 0.6, Vector3(38.0, 0, 2.0), 0.0, true)
	_p("traffic_cone", 0.6, Vector3(33.0, 0, -5.0), 0.0, true); _p("traffic_cone", 0.6, Vector3(39.5, 0, -6.4), 0.0, true)
	_p("debris_pile", 1.8, Vector3(29.0, 0, -6.0)); _p("rocks", 1.4, Vector3(44.6, 0, 8.4))
	_p("pallet_broken", 1.3, Vector3(41.0, 1.42, -14.2))
	for sp in [Vector3(27.0, 0, -9.0), Vector3(45.2, 0, 0.5)]:
		_p("street_light", 5.0, sp, 0.0, true, false)
		map.light(sp + Vector3(0, 4.6, 0), Color(1.0, 0.7, 0.4), 1.6, 10.0)
	# pump station
	_p("dumpster", 2.0, Vector3(44.4, 0, 12.0), 0.0, false, true); _p("trashcan", 0.9, Vector3(28.0, 0, 28.4), 0.0, true, true)
	_p("debris_pile", 1.5, Vector3(40, 0, 28.0)); _p("rocks", 1.2, Vector3(33, 0, 27.6))
	# outside the walls (zombie approach lanes): dead trees, wrecks, fences
	for t in [Vector3(-16, 0, 4), Vector3(-15, 0, -20), Vector3(-2, 0, 16), Vector3(16, 0, 15.5), Vector3(4, 0, -31),
			Vector3(20, 0, -31), Vector3(52, 0, -4), Vector3(52, 0, 22), Vector3(30, 0, 36), Vector3(42, 0, 37)]:
		_p("dead_tree" if rng.randf() < 0.5 else "dead_trees", rng.randf_range(5.0, 7.5), t, 0.0, true, false)
	_p("sports_car", 4.2, Vector3(-16, 0, -8), 0.3, false, true)
	_p("dumpster", 2.0, Vector3(8, 0, 14.5), 0.2, false, true)
	for f in [Vector3(-14, 0, 12), Vector3(-17, 0, 12), Vector3(26, 0, 34), Vector3(50, 0, 14)]:
		_p("fence", 3.0, f, rng.randf_range(-0.3, 0.3))

# ---------------------------------------------------------------- fire barrels
func _fire_barrels() -> void:
	for p in [Vector3(-7.8, 0, 7.5), Vector3(33.0, 0, -9.0), Vector3(42.5, 0, 3.0), Vector3(29.0, 0, 26.0), Vector3(-15, 0, -2), Vector3(52, 0, 8)]:
		fire_barrel(p)

func fire_barrel(p: Vector3) -> Node3D:
	var root := Node3D.new(); root.position = p; map.add_child(root)
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.3; cm.bottom_radius = 0.3; cm.height = 0.9
	cm.cap_top = false; mi.mesh = cm; mi.material_override = map.mats.rust; mi.position.y = 0.45; root.add_child(mi)
	var f := CPUParticles3D.new(); f.amount = 24; f.lifetime = 0.7; f.position.y = 0.9
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; f.emission_sphere_radius = 0.18
	f.direction = Vector3.UP; f.spread = 12; f.gravity = Vector3(0, 2.2, 0); f.initial_velocity_min = 0.3; f.initial_velocity_max = 0.8
	f.scale_amount_min = 0.6; f.scale_amount_max = 1.2
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.6)); cv.add_point(Vector2(0.3, 1.0)); cv.add_point(Vector2(1, 0)); f.scale_amount_curve = cv
	var g := Gradient.new(); g.set_color(0, Color(1.0, 0.85, 0.35)); g.set_color(1, Color(0.6, 0.1, 0.02, 0.0)); f.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(0.35, 0.35); f.mesh = q
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true; m.albedo_texture = _radial(); m.disable_fog = true; q.material = m
	root.add_child(f); map.dust.append(f)
	var l := map.light(p + Vector3(0, 1.4, 0), Color(1.0, 0.5, 0.18), 2.2, 8.0)
	l.set("rate", 0.6)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 0.3; cy.height = 0.9
	cs.shape = cy; cs.position.y = 0.45; sb.add_child(cs); root.add_child(sb)
	return root

static func _radial() -> Texture2D:
	if _decal_tex.has("radial"): return _decal_tex.radial
	var g := Gradient.new(); g.set_color(0, Color.WHITE); g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(0.5, 0.0); t.width = 32; t.height = 32
	_decal_tex.radial = t; return t

# ---------------------------------------------------------------- decals (original, generated)
static func decal_tex(kind: String) -> Texture2D:
	if _decal_tex.has(kind): return _decal_tex[kind]
	var n := FastNoiseLite.new(); n.seed = kind.hash() & 0xffff; n.frequency = 0.035 if kind != "crack" else 0.02
	n.fractal_octaves = 4
	var sz := 128; var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz / 2.0, y - sz / 2.0).length() / (sz / 2.0)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0, 0, 0, 0)
			match kind:
				"blood":
					var a := clampf((v * 1.4 - d) * 3.0, 0, 1)
					c = Color(0.28 + v * 0.1, 0.01, 0.01, a * 0.95)
				"grime":
					var a := clampf((v - d * 0.6) * 1.6, 0, 1)
					c = Color(0.05, 0.045, 0.035, a * 0.75)
				"crack":
					var r := absf(n.get_noise_2d(x * 1.0, y * 1.0))
					var a := clampf(1.0 - r * 18.0, 0, 1) * clampf(1.2 - d, 0, 1)
					c = Color(0.02, 0.02, 0.02, a)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img); _decal_tex[kind] = t
	return t

func decal(kind: String, pos: Vector3, size: float, normal := Vector3.UP) -> Decal:
	var d := Decal.new(); d.texture_albedo = decal_tex(kind)
	d.size = Vector3(size, 0.6, size)
	var y := normal.normalized()   # decals project along local -Y, so local +Y = surface normal
	var x := (Vector3.UP.cross(y) if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	d.transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	if absf(y.y) > 0.9: d.rotate_object_local(Vector3.UP, rng.randf_range(-PI, PI))
	d.cull_mask = 1; d.upper_fade = 0.3; d.lower_fade = 0.3
	d.distance_fade_enabled = true; d.distance_fade_begin = 22.0; d.distance_fade_length = 6.0
	map.add_child(d)
	return d

func _decals() -> void:
	var kinds := ["blood", "grime", "grime", "crack"]
	var zones := [Rect2(-9, -9, 18, 18), Rect2(-9, -25, 18, 14), Rect2(11, -9, 14, 18), Rect2(11, -25, 14, 14), Rect2(27, -15, 18, 24), Rect2(27, 11, 18, 18)]
	for z in zones:
		for i in 7:
			var k: String = kinds[rng.randi() % kinds.size()]
			decal(k, Vector3(rng.randf_range(z.position.x, z.end.x), 0.05, rng.randf_range(z.position.y, z.end.y)), rng.randf_range(1.2, 3.2))
	# wall smears near the windows (where the horde breaks in) + cracks high on walls
	for w in [[Vector3(-9.75, 1.2, 2.0), Vector3.RIGHT], [Vector3(-3.0, 1.0, 9.75), Vector3.BACK * -1], [Vector3(9.75, 1.6, 6.0), Vector3.LEFT],
			[Vector3(-9.75, 2.6, -14.0), Vector3.RIGHT], [Vector3(18.0, 2.4, 9.75), Vector3.FORWARD], [Vector3(25.75, 1.4, -2.0), Vector3.LEFT]]:
		decal("blood" if rng.randf() < 0.5 else "crack", w[0], rng.randf_range(1.0, 1.8), w[1])

# ---------------------------------------------------------------- mist
func _mist() -> void:
	var n := FastNoiseLite.new(); n.frequency = 0.05; n.seed = 3
	var nt := NoiseTexture2D.new(); nt.noise = n; nt.seamless = true; nt.width = 128; nt.height = 128
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_texture = nt; m.albedo_color = Color(0.55, 0.6, 0.7, 0.16)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.disable_receive_shadows = true
	m.proximity_fade_enabled = true; m.proximity_fade_distance = 1.0
	for c in [Vector3(36, 0.5, -3), Vector3(36, 0.6, 20), Vector3(-18, 0.5, -8), Vector3(8, 0.5, 18), Vector3(8, 0.5, -34), Vector3(54, 0.5, 6), Vector3(0, 0.35, -4), Vector3(18, 0.35, -18)]:
		for layer in 2:
			var mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(22, 22); mi.mesh = pm
			mi.material_override = m; mi.position = c + Vector3(0, layer * 0.45, 0); mi.rotation.y = layer * 0.7
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			map.add_child(mi); map.dust.append(mi)

# ---------------------------------------------------------------- grass (MultiMesh)
func _grass() -> void:
	var g := Gradient.new(); g.set_color(0, Color(0.33, 0.36, 0.2)); g.set_color(1, Color(0.12, 0.15, 0.08))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 32
	var m := StandardMaterial3D.new(); m.albedo_texture = gt; m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.roughness = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var mesh := _tuft_mesh(); mesh.surface_set_material(0, m)
	var spots: Array = []
	var areas := [Rect2(-26, -40, 15, 58), Rect2(-12, 11, 36, 10), Rect2(-12, -40, 56, 13), Rect2(47, -20, 12, 52), Rect2(26, 31, 26, 10), Rect2(27, -15, 18, 2), Rect2(27, 7, 18, 2.5)]
	for a in areas:
		var count := int(a.get_area() * 0.9)
		for i in count:
			spots.append(Vector3(rng.randf_range(a.position.x, a.end.x), 0, rng.randf_range(a.position.y, a.end.y)))
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh; mm.instance_count = spots.size()
	for i in spots.size():
		var s := rng.randf_range(0.5, 1.3)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.7, 1.4), s)), spots[i]))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 60.0; mmi.name = "GrassMM"
	map.add_child(mmi); map.dust.append(mmi)

## Three crossed tapered blades (12 tris) per tuft.
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var ang := k * PI / 3.0; var r := Vector3(cos(ang), 0, sin(ang)) * 0.22
		var lean := Vector3(sin(ang * 3.0), 0, cos(ang * 2.0)) * 0.08
		var top := Vector3(0, 0.45, 0) + lean
		for q in [[-r, r, top + r * 0.15, top - r * 0.15]]:
			st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(q[0])
			st.set_uv(Vector2(1, 1)); st.add_vertex(q[1])
			st.set_uv(Vector2(1, 0)); st.add_vertex(q[2])
			st.set_uv(Vector2(0, 1)); st.add_vertex(q[0])
			st.set_uv(Vector2(1, 0)); st.add_vertex(q[2])
			st.set_uv(Vector2(0, 0)); st.add_vertex(q[3])
	return st.commit()

func _height_fog() -> void:
	if map.game == null or map.game.env == null: return
	var e: Environment = map.game.env
	e.fog_height = 0.6; e.fog_height_density = 0.12
	e.fog_aerial_perspective = 0.25
