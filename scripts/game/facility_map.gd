class_name FacilityMap
extends NavigationRegion3D
## "Blackwater Research Annex": original map built in code. Intake Hall (start) plus four buyable
## areas: Generator Wing (power switch), Lab Corridor (catwalk), Cold Storage (Overcharge Forge) and the
## open-air Loading Yard (raised dock + island for training loops). PBR surfaces use CC0 ambientCG
## textures and props are CC0 Quaternius / Kenney models (see ASSETS.md).

const H := 4.0
const T := 0.4

var game
var windows := {}      # id -> WindowBarricade
var doors := {}        # id -> StaticBody3D
var room_lights: Array = []    # white lights enabled by power
var emergency_lights: Array = []
var machine_lights: Array = []
var mats := {}
var crate_spots: Array = []   # [pos, rot_y, area label]
var fuses := {}               # id -> [mesh material, light]
var dust: Array = []
var shadow_lights: Array = []
var forge_rings: Array = []
var forge_work := 0.0   ## seconds left on the current upgrade animation
var neon: Array = []          # [material, base energy]
var _t := 0.0
var alarm_lights: Array = []   ## pulsing red alarms that kick in after round 5
var alarm_mats: Array = []
const ALARM_ROUND := 6

func _ready() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5; nm.agent_height = 2.0; nm.agent_max_climb = 0.25
	nm.cell_size = 0.25; nm.cell_height = 0.25
	navigation_mesh = nm

func _tex(name: String, kind: String) -> Texture2D:
	return load("res://assets/textures/%s_%s.jpg" % [name, kind])

## PBR material from an ambientCG set (albedo/normal/roughness), triplanar so boxes of any size tile.
func _pbr(name: String, tint := Color.WHITE, scale := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(name, "albedo"); m.albedo_color = tint
	m.normal_enabled = true; m.normal_texture = _tex(name, "normal"); m.normal_scale = 1.0
	m.roughness_texture = _tex(name, "rough"); m.roughness = 1.0
	m.metallic = metal
	m.uv1_triplanar = true; m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Multiplies a large-scale grime/stain noise over a PBR set so surfaces stop looking freshly painted.
func _grimy(m: StandardMaterial3D) -> StandardMaterial3D:
	m.detail_enabled = true; m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = Zombie.grime_tex(); m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	return m

## Mobile-friendly light shaft: an additive, Y-billboarded gradient card (no volumetrics).
static var _shaft_mat: StandardMaterial3D
func shaft(pos: Vector3, h: float, w: float, col: Color, parent: Node = null) -> MeshInstance3D:
	if _shaft_mat == null:
		var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 0.0)); g.add_point(0.15, Color(1, 1, 1, 0.55)); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0.5, 0); gt.fill_to = Vector2(0.5, 1); gt.width = 8; gt.height = 64
		var sideg := Gradient.new(); sideg.set_color(0, Color(1, 1, 1, 0)); sideg.add_point(0.5, Color.WHITE); sideg.set_color(sideg.get_point_count() - 1, Color(1, 1, 1, 0))
		_shaft_mat = StandardMaterial3D.new(); _shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; _shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shaft_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y; _shaft_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shaft_mat.albedo_texture = gt; _shaft_mat.vertex_color_use_as_albedo = true; _shaft_mat.disable_fog = true
		_shaft_mat.detail_enabled = false
		var sgt := GradientTexture2D.new(); sgt.gradient = sideg; sgt.width = 32; sgt.height = 4
		_shaft_mat.detail_enabled = true; _shaft_mat.detail_albedo = sgt; _shaft_mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	var mi := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(w, h); mi.mesh = qm
	var m := _shaft_mat.duplicate() as StandardMaterial3D; m.albedo_color = col; mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi

## Night sky: procedural dark gradient + a glowing moon disc in the moon light's direction.
var moon_light: DirectionalLight3D
func build_sky() -> void:
	var moon := moon_light
	if game == null or game.env == null or moon == null: return
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.01, 0.015, 0.04); sm.sky_horizon_color = Color(0.06, 0.07, 0.12)
	sm.ground_bottom_color = Color(0.0, 0.0, 0.0); sm.ground_horizon_color = Color(0.05, 0.05, 0.08)
	sm.sun_angle_max = 1.0; sm.sun_curve = 0.05; sm.energy_multiplier = 1.0
	var sky := Sky.new(); sky.sky_material = sm; sky.radiance_size = Sky.RADIANCE_SIZE_32
	game.env.sky = sky; game.env.background_mode = Environment.BG_SKY
	game.env.fog_sky_affect = 0.35
	# moon disc + halo far away along -light direction
	var dir := moon.global_transform.basis.z.normalized()   # points toward the light source
	var at := Vector3(18, 0, -8) + dir * 120.0
	for pair in [[14.0, Color(0.85, 0.9, 1.0, 1.0)], [46.0, Color(0.35, 0.45, 0.8, 0.35)]]:
		var mi := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2.ONE * pair[0]; mi.mesh = qm
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.disable_fog = true; m.albedo_color = pair[1]; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var g := Gradient.new(); g.set_color(0, Color.WHITE); g.add_point(0.45 if pair[0] < 20 else 0.05, Color.WHITE); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0); gt.width = 64; gt.height = 64
		m.albedo_texture = gt; mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi); mi.global_position = at

func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

func _emit(c: Color, e := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	return m

## Box with optional collider; returns the body (or mesh when no collider).
func box(size: Vector3, pos: Vector3, mat: Material, collide := true, layer := 1, parent: Node3D = null) -> Node3D:
	if parent == null: parent = self
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat
	if not collide:
		mi.position = pos; parent.add_child(mi); return mi
	var sb := StaticBody3D.new(); sb.collision_layer = layer; sb.collision_mask = 0; sb.position = pos
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	sb.add_child(cs); sb.add_child(mi); parent.add_child(sb)
	return sb

func label(text: String, pos: Vector3, rot_y: float, size := 48, color := Color(0.9, 0.9, 0.85)) -> Label3D:
	var l := Label3D.new(); l.text = text; l.font_size = size; l.pixel_size = 0.004
	l.modulate = color; l.outline_size = 8; l.position = pos; l.rotation.y = rot_y
	l.shaded = false; l.double_sided = false
	add_child(l); return l

## Axis-aligned wall from a to b (x,z). gaps: [{at, w, kind, id, out}] measured from a.
func wall(a: Vector2, b: Vector2, gaps: Array = []) -> void:
	var along_x: bool = absf(a.y - b.y) < 0.01
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var cuts: Array = []
	for g in gaps: cuts.append([g.at - g.w / 2.0, g.at + g.w / 2.0, g])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var cur := 0.0
	var segs: Array = []
	for c in cuts:
		segs.append([cur, c[0]]); cur = c[1]
	segs.append([cur, length])
	var wm: StandardMaterial3D = mats.wall
	for s in segs:
		if s[1] - s[0] < 0.01: continue
		_wall_piece(a, dir, along_x, s[0], s[1], 0.0, H, wm)
	for c in cuts:
		var g: Dictionary = c[2]
		if g.kind == "window":
			_wall_piece(a, dir, along_x, c[0], c[1], 0.0, 1.0, mats.wall_low)
			_wall_piece(a, dir, along_x, c[0], c[1], 2.3, H, wm)
			_make_window(a + dir * g.at, along_x, g)
		elif g.kind == "door":
			_wall_piece(a, dir, along_x, c[0], c[1], 3.0, H, wm)
			_make_door(a + dir * g.at, along_x, g)

func _wall_piece(a: Vector2, dir: Vector2, along_x: bool, s0: float, s1: float, y0: float, y1: float, m: Material) -> void:
	var mid := a + dir * ((s0 + s1) / 2.0)
	var len := s1 - s0
	var size := Vector3(len, y1 - y0, T) if along_x else Vector3(T, y1 - y0, len)
	box(size, Vector3(mid.x, (y0 + y1) / 2.0, mid.y), m)
	# grime strip along the floor
	var gs := Vector3(len, 0.25, T + 0.04) if along_x else Vector3(T + 0.04, 0.25, len)
	if y0 == 0.0: box(gs, Vector3(mid.x, 0.12, mid.y), mats.trim, false)

func _make_window(p: Vector2, along_x: bool, g: Dictionary) -> void:
	var w := WindowBarricade.new()
	w.id = g.id; w.area = Facility.WINDOWS[g.id]
	add_child(w)
	w.position = Vector3(p.x, 0, p.y)
	var outv: Vector2 = g.out
	w.rotation.y = atan2(outv.x, outv.y)
	w.build(g.w)
	windows[g.id] = w
	# invisible blocker that stops players (layer 4) but not zombies or the navmesh
	var size := Vector3(g.w, 1.4, T) if along_x else Vector3(T, 1.4, g.w)
	box(size, Vector3(p.x, 1.65, p.y), null, true, 8).get_child(1).visible = false
	game.add_interactable(w.center() - Vector3(outv.x, 0, outv.y) * 0.6, 2.0,
		func(pl): return "Hold to rebuild barricade (+%d)" % Economy.REPAIR if w.bar.hp < w.bar.max_hp() else "",
		func(pl): game.repair_window(pl, w), true)
	# a dim light outside to silhouette the horde
	var ol := OmniLight3D.new(); ol.light_color = Color(0.35, 0.45, 0.6); ol.light_energy = 0.6; ol.omni_range = 6
	ol.position = Vector3(p.x + outv.x * 3, 2.5, p.y + outv.y * 3); add_child(ol)

func _make_door(p: Vector2, along_x: bool, g: Dictionary) -> void:
	var size := Vector3(g.w, 3.0, 0.25) if along_x else Vector3(0.25, 3.0, g.w)
	var body := box(size, Vector3(p.x, 1.5, p.y), mats.door)
	# warning stripes
	var ss := Vector3(g.w * 0.9, 0.2, 0.3) if along_x else Vector3(0.3, 0.2, g.w * 0.9)
	box(ss, Vector3(0, 0.3, 0), mats.stripe, false, 1, body)
	box(ss, Vector3(0, 0.9, 0), mats.stripe, false, 1, body)
	doors[g.id] = body
	var d: Dictionary = Facility.DOORS[g.id]
	var rot := 0.0 if along_x else PI / 2
	for side in [-1, 1]:
		var l := Label3D.new(); l.text = "%s\n%d" % [d.label, d.cost]; l.font_size = 40; l.pixel_size = 0.004
		l.outline_size = 8; l.modulate = Color(1, 0.85, 0.3); l.shaded = false
		l.position = (Vector3(0, 0.7, 0.15 * side) if along_x else Vector3(0.15 * side, 0.7, 0))
		l.rotation.y = rot + (0.0 if side > 0 else PI)
		body.add_child(l)
	game.add_interactable(Vector3(p.x, 1.0, p.y), 2.4,
		func(pl): return "" if facility_open(g.id) else "Open %s: %d" % [d.label, d.cost],
		func(pl): game.buy_door(pl, g.id))

func facility_open(id: String) -> bool:
	return game.facility.open_doors.get(id, false)

func open_door(id: String) -> void:
	var b: Node3D = doors.get(id)
	if b:
		var tw := create_tween()
		tw.tween_property(b, "position:y", -1.6, 0.8)
		tw.tween_callback(func(): b.queue_free(); call_deferred("rebake"))

func rebake() -> void:
	bake_navigation_mesh(true)

func prop(name: String, size: float, pos: Vector3, rot_y := 0.0, by_height := false, collide := true) -> Node3D:
	var n := ModelLib.prop(name, size, by_height)
	n.position = pos; n.rotation.y = rot_y; add_child(n)
	_lod(n, 38.0 if size > 1.5 else 24.0)
	if collide:
		var a := _bounds(n)
		var sb := StaticBody3D.new(); sb.collision_layer = 1; sb.collision_mask = 0
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = a.size; cs.shape = sh
		cs.position = a.get_center(); sb.add_child(cs); n.add_child(sb)
	return n

## Distance culling ("LOD") for props: small clutter disappears past a few rooms, with a fade margin.
func _lod(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		n.visibility_range_end = dist; n.visibility_range_end_margin = 2.0
		n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in n.get_children(): _lod(c, dist)

func _bounds(n: Node3D) -> AABB:
	var acc := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = n.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform if n.is_inside_tree() else _rel(n, mi)
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		acc = b if first else acc.merge(b); first = false
	return acc

func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY; var c: Node = n
	while c != root and c is Node3D:
		xf = (c as Node3D).transform * xf; c = c.get_parent()
	return xf

func build(p_game) -> void:
	game = p_game
	mats.wall = _grimy(_pbr("paintedplaster017", Color(0.6, 0.62, 0.58), 0.35))
	mats.wall_low = _pbr("concrete034", Color(0.7, 0.7, 0.7), 0.4)
	mats.floor = _grimy(_pbr("tiles074", Color(0.42, 0.42, 0.4), 0.45))
	mats.ground = _grimy(_pbr("concrete034", Color(0.5, 0.52, 0.5), 0.18))
	mats.trim = _pbr("metal032", Color(0.35, 0.33, 0.3), 1.0, 0.6)
	mats.door = _pbr("metalplates006", Color(0.6, 0.62, 0.66), 0.6, 0.7)
	mats.stripe = _mat(Color(0.75, 0.6, 0.1), 0.7)
	mats.metal = _pbr("metal032", Color(0.7, 0.7, 0.72), 0.8, 0.8)
	mats.plate = _pbr("diamondplate008c", Color(0.75, 0.75, 0.78), 0.6, 0.85)
	mats.ceiling = _pbr("metalplates006", Color(0.4, 0.4, 0.42), 0.3, 0.5)
	mats.lamp = _emit(Color(1.0, 0.92, 0.75), 2.0)
	# ground slab covers the building and the yard so the navmesh is continuous outside
	box(Vector3(90, 1, 76), Vector3(18, -0.5, -8), mats.ground)
	box(Vector3(36, 0.02, 36), Vector3(8, 0.01, -8), mats.floor, false)
	box(Vector3(36.4, 0.3, 36.4), Vector3(8, H + 0.15, -8), mats.ceiling, false)
	# outer walls
	wall(Vector2(-10, 10), Vector2(-10, -26), [
		{at = 8.0, w = 1.8, kind = "window", id = "w_west", out = Vector2(-1, 0)},
		{at = 28.0, w = 1.8, kind = "window", id = "w_gen", out = Vector2(-1, 0)}])
	wall(Vector2(-10, 10), Vector2(26, 10), [
		{at = 7.0, w = 1.8, kind = "window", id = "w_south", out = Vector2(0, 1)},
		{at = 28.0, w = 1.8, kind = "window", id = "w_lab", out = Vector2(0, 1)}])
	wall(Vector2(-10, -26), Vector2(26, -26), [
		{at = 28.0, w = 1.8, kind = "window", id = "w_cold", out = Vector2(0, -1)}])
	wall(Vector2(26, 10), Vector2(26, -26), [{at = 10.0, w = 2.6, kind = "door", id = "yard"}])
	# interior walls with buyable doors
	wall(Vector2(-10, -10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "north"}])
	wall(Vector2(10, 10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "east"}])
	wall(Vector2(10, -10), Vector2(10, -26), [{at = 8.0, w = 2.4, kind = "door", id = "cold"}])
	wall(Vector2(10, -10), Vector2(26, -10))
	_build_yard()
	_build_pump()
	_build_catwalk()
	_build_props()
	# ceiling lamps: emergency red (power off) + white (power on)
	for p in [Vector3(0, H - 0.3, 0), Vector3(0, H - 0.3, -18), Vector3(18, H - 0.3, 0), Vector3(18, H - 0.3, -18)]:
		box(Vector3(1.4, 0.08, 0.4), p + Vector3(0, 0.1, 0), mats.lamp, false)
		var w := light(p + Vector3(0, -0.4, 0), Color(1.0, 0.9, 0.75), 2.2, 12.0)
		w.visible = false; room_lights.append(w); shadow_lights.append(w)
		shaft(Vector3(0, -1.3, 0), 2.6, 1.6, Color(1.0, 0.9, 0.7, 0.16), w)
		emergency_lights.append(light(p + Vector3(2, -0.5, 2), Color(1.0, 0.15, 0.08), 1.2, 9.0))
		_dust(p + Vector3(0, -1.6, 0), Vector3(6, 1.6, 6))
	# alarm beacons (off until round 6): a red lamp housing + a pulsing light, no shadows
	for p in [Vector3(-9.5, 3.2, 2), Vector3(-2, 3.2, 9.5), Vector3(9.5, 3.2, -4), Vector3(18, 3.2, 9.5)]:
		var am := _emit(Color(1.0, 0.1, 0.05), 0.2); alarm_mats.append(am)
		box(Vector3(0.3, 0.3, 0.3), p, am, false)
		var al := light(p + Vector3(0, -0.4, 0), Color(1.0, 0.08, 0.04), 0.0, 10.0, false)
		al.visible = false; alarm_lights.append(al)
	# moon (dimmer: the scene is lit mostly by the gun flashlight, lamps and neon)
	var moon := DirectionalLight3D.new(); moon.light_color = Color(0.4, 0.5, 0.85); moon.light_energy = 0.22
	moon.rotation_degrees = Vector3(-50, 30, 0); moon.shadow_enabled = true; add_child(moon)
	moon.directional_shadow_max_distance = 40.0
	shadow_lights.append(moon)
	moon_light = moon
	_place_machines()
	_place_fuses()

## Dust motes hanging in the light (the mobile renderer has no volumetric fog).
func _dust(at: Vector3, extents: Vector3) -> void:
	var p := CPUParticles3D.new(); p.amount = 40; p.lifetime = 8.0; p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = extents
	p.gravity = Vector3(0, -0.01, 0); p.initial_velocity_min = 0.02; p.initial_velocity_max = 0.08
	p.direction = Vector3(1, 0.2, 0); p.spread = 180
	var q := QuadMesh.new(); q.size = Vector2(0.025, 0.025); p.mesh = q
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.95, 0.85, 0.25); q.material = m
	p.position = at; add_child(p); dust.append(p)

## Pump Station: x 26..46, z 10..30, south of the Loading Yard. Open-air, flooded sump, tanks + pipes.
func _build_pump() -> void:
	box(Vector3(40, 1, 14), Vector3(36, -0.5, 36), mats.ground)   # ground beyond the south fence for spawns
	box(Vector3(20, 0.02, 20), Vector3(36, 0.01, 20), mats.floor, false)
	wall(Vector2(26, 10), Vector2(26, 30))
	wall(Vector2(26, 30), Vector2(46, 30), [{at = 12.0, w = 1.8, kind = "window", id = "w_pump_s", out = Vector2(0, 1)}])
	wall(Vector2(46, 30), Vector2(46, 10), [{at = 10.0, w = 1.8, kind = "window", id = "w_pump_e", out = Vector2(1, 0)}])
	# two big tanks + a pipe run (cover to kite around)
	var tank_mat := StandardMaterial3D.new(); tank_mat.albedo_color = Color(0.22, 0.3, 0.28); tank_mat.roughness = 0.6; tank_mat.metallic = 0.5
	tank_mat.detail_enabled = mats.wall.detail_enabled; tank_mat.detail_albedo = mats.wall.detail_albedo; tank_mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	for tp in [Vector3(31, 0, 24), Vector3(41, 0, 16)]:
		var sb := StaticBody3D.new(); sb.position = tp; add_child(sb)
		var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 1.6; cm.bottom_radius = 1.6; cm.height = 4.0
		mi.mesh = cm; mi.material_override = tank_mat; mi.position.y = 2.0; sb.add_child(mi)
		var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 1.6; cy.height = 4.0; cs.shape = cy; cs.position.y = 2.0; sb.add_child(cs)
		box(Vector3(3.4, 0.12, 0.12), tp + Vector3(0, 3.2, 0), mats.stripe, false)
	for x in [27.0, 27.6]:
		box(Vector3(0.3, 0.3, 16.0), Vector3(x, 2.4 + (x - 27.0), 20.0), mats.metal, false)
	box(Vector3(10.0, 0.35, 0.35), Vector3(36, 2.6, 28.8), mats.metal, false)
	# flooded sump: a dark glossy sheet
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.05, 0.09, 0.08); wm.roughness = 0.05; wm.metallic = 0.3
	box(Vector3(5, 0.03, 4), Vector3(37, 0.03, 23), wm, false)
	prop("barrel", 0.95, Vector3(43.5, 0, 27), 0.3, true)
	prop("barrel_explosive", 0.95, Vector3(33.5, 0, 14), 0.0, true)
	prop("debris", 1.4, Vector3(29, 0, 19), 2.0, false, false)
	label("PUMP STATION", Vector3(36, 3.4, 29.7), PI, 64, Color(0.4, 1.0, 0.8))
	var gl := light(Vector3(36, 3.6, 20), Color(0.45, 1.0, 0.75), 1.8, 14.0)
	shadow_lights.append(gl)
	for sp in [Vector3(32, 3.0, 18), Vector3(40, 3.0, 25)]:
		shaft(sp, 6.0, 2.2, Color(0.4, 0.9, 0.75, 0.10))
	_dust(Vector3(36, 2, 20), Vector3(8, 1.5, 8))

func _build_yard() -> void:
	for sp in [Vector3(31, 3.0, -4), Vector3(40, 3.0, 4), Vector3(37, 3.0, -12)]:
		shaft(sp, 6.0, 2.4, Color(0.45, 0.55, 0.9, 0.11))
	# Loading Yard: x 26..46, z -16..10, open-air with a chain-link perimeter and two windows on x=46
	wall(Vector2(46, 10), Vector2(46, -16), [
		{at = 6.0, w = 1.8, kind = "window", id = "w_yard_s", out = Vector2(1, 0)},
		{at = 18.0, w = 1.8, kind = "window", id = "w_yard_n", out = Vector2(1, 0)}])
	wall(Vector2(26, 10), Vector2(46, 10), [{at = 10.0, w = 2.6, kind = "door", id = "pump"}])
	for seg in [[Vector2(26, -16), Vector2(46, -16)]]:
		var a: Vector2 = seg[0]; var b: Vector2 = seg[1]
		box(Vector3(b.x - a.x, H, T), Vector3((a.x + b.x) / 2, H / 2, a.y), mats.wall_low)
	# raised loading dock with two ramps (verticality)
	box(Vector3(10, 1.4, 5), Vector3(36, 0.7, -13.5), mats.wall_low)
	box(Vector3(10.2, 0.06, 5.2), Vector3(36, 1.43, -13.5), mats.plate, false)
	for x in [29.0, 43.0]:
		var r := box(Vector3(4, 0.3, 3.2), Vector3(x, 0.62, -12.0), mats.plate)
		r.rotation.z = (1.0 if x < 36 else -1.0) * atan2(1.4, 4.0)
	box(Vector3(10, 0.12, 0.12), Vector3(36, 2.4, -11.0), mats.stripe)  # guard rail
	# dock lights
	for x in [32.0, 40.0]:
		var l := light(Vector3(x, 3.6, -12), Color(1.0, 0.75, 0.45), 2.0, 12.0)
		shadow_lights.append(l)
	_dust(Vector3(36, 2, -6), Vector3(9, 1.5, 9))
	# central island for kiting
	prop("police_car", 4.6, Vector3(36, 0, -1), 0.4)
	prop("barrel", 0.95, Vector3(33.2, 0, 1.4), 0.0, true)
	prop("barrel_explosive", 0.95, Vector3(38.9, 0, -3.2), 0.0, true)
	prop("debris", 1.6, Vector3(41, 0, 5), 1.0, false, false)
	prop("fence", 3.0, Vector3(30, 0, 8.6), 0.0, false, false)
	label("LOADING YARD", Vector3(36, 3.2, -11.0), 0.0, 64, Color(1.0, 0.75, 0.3))
	var sl := light(Vector3(36, 3.5, 3), Color(0.5, 0.6, 0.9), 1.4, 14.0, false)
	shadow_lights.append(sl)

func _build_catwalk() -> void:
	# Lab catwalk at 1.8 m along the north wall of the lab with a ramp down to the east.
	box(Vector3(8, 0.15, 2.2), Vector3(16, 1.8, -8.5), mats.plate)
	for x in [12.5, 19.5]:
		box(Vector3(0.12, 1.8, 0.12), Vector3(x, 0.9, -7.5), mats.metal)
	box(Vector3(8, 0.08, 0.08), Vector3(16, 2.85, -7.42), mats.stripe, false)
	var ramp := box(Vector3(4.4, 0.15, 2.2), Vector3(22, 0.9, -8.5), mats.plate)
	ramp.rotation.z = -atan2(1.8, 4.2)

func _build_props() -> void:
	prop("crate", 1.0, Vector3(-7, 0, -7), 0.3)
	prop("crate", 0.9, Vector3(-7.8, 0, -5.8), -0.2)
	prop("crate", 1.0, Vector3(6.5, 0, 6.5), 0.1)
	prop("desk", 1.8, Vector3(18, 0, -3), 0.0)
	prop("computer", 0.6, Vector3(18, 0.82, -3), PI, false, false)
	prop("desk", 1.8, Vector3(18, 0, 3.5), PI)
	prop("papers", 0.5, Vector3(17.4, 0.82, 3.5), 0.4, false, false)
	prop("shelf", 2.0, Vector3(24.8, 0, -18), PI / 2, true)
	prop("shelf", 2.0, Vector3(24.8, 0, -21), PI / 2, true)
	prop("gas_tank", 1.6, Vector3(-6, 0, -22), 0.0, true)
	prop("barrel", 0.95, Vector3(5, 0, -20), 0.0, true)
	prop("barrel", 0.95, Vector3(5.8, 0, -20.6), 0.0, true)
	prop("pipes_panel", 2.6, Vector3(-9.6, 0, -16), PI / 2, true, false)
	prop("bricks", 1.0, Vector3(-3, 0, 7.5), 0.6, false, false)
	prop("debris", 1.2, Vector3(4, 0, -4), 0.0, false, false)
	prop("signs", 1.2, Vector3(9.6, 1.6, 3), -PI / 2, false, false)
	box(Vector3(4, 2.4, 2), Vector3(0, 1.2, -24.5), mats.metal)  # generator block
	for x in [-6, 0, 6]:
		box(Vector3(0.25, 0.25, 36), Vector3(x + 2, H - 0.3, -8), mats.metal, false)  # ceiling pipes

func light(pos: Vector3, color: Color, energy: float, rng: float, flicker := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	if flicker: l.set_script(load("res://scripts/game/flicker_light.gd"))
	l.light_color = color; l.light_energy = energy; l.omni_range = rng; l.position = pos
	l.omni_attenuation = 1.2
	add_child(l)
	return l

func apply_quality(d: Dictionary) -> void:
	for l in shadow_lights:
		if is_instance_valid(l): l.shadow_enabled = d.shadows
	for p in dust:
		p.emitting = d.dust; p.visible = d.dust
	for z in get_tree().get_nodes_in_group("voz_zombie"):
		ModelLib.set_shadows(z.model, d.shadows)

# ---------------------------------------------------------------- machines
## Neon perk machine: cabinet + glowing tube outline + emblem + sign.
func _machine(pos: Vector3, rot_y: float, color: Color, title: String, emblem := "circle") -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; add_child(root)
	box(Vector3(1.2, 2.2, 0.8), Vector3(0, 1.1, 0), _pbr("metalplates006", color.darkened(0.45), 0.9, 0.6), true, 1, root)
	var panel := box(Vector3(0.9, 0.9, 0.05), Vector3(0, 1.45, -0.42), _emit(color, 0.3), false, 1, root)
	var tube := _emit(color.lightened(0.2), 0.4)
	for e in [[Vector3(1.26, 0.05, 0.05), Vector3(0, 2.22, -0.42)], [Vector3(1.26, 0.05, 0.05), Vector3(0, 0.02, -0.42)],
			[Vector3(0.05, 2.2, 0.05), Vector3(0.62, 1.1, -0.42)], [Vector3(0.05, 2.2, 0.05), Vector3(-0.62, 1.1, -0.42)]]:
		box(e[0], e[1], tube, false, 1, root)
	var em := MeshInstance3D.new(); em.material_override = tube
	match emblem:
		"heart":
			var sm := SphereMesh.new(); sm.radius = 0.16; sm.height = 0.32; em.mesh = sm; em.scale = Vector3(1, 1, 0.3)
		"bolt":
			var pm := PrismMesh.new(); pm.size = Vector3(0.3, 0.42, 0.05); em.mesh = pm; em.rotation.z = 0.4
		_:
			var tm := TorusMesh.new(); tm.inner_radius = 0.12; tm.outer_radius = 0.17; em.mesh = tm; em.rotation.x = PI / 2
	em.position = Vector3(0, 1.5, -0.47); root.add_child(em)
	var l := Label3D.new(); l.text = title.to_upper(); l.font_size = 40; l.pixel_size = 0.004; l.outline_size = 10
	l.shaded = false; l.position = Vector3(0, 2.45, -0.42); l.rotation.y = PI; l.modulate = color.lightened(0.45)
	l.outline_modulate = color.darkened(0.3)
	root.add_child(l)
	var ml := OmniLight3D.new(); ml.light_color = color; ml.light_energy = 0.0; ml.omni_range = 4.0
	ml.position = Vector3(0, 1.5, -1.0); root.add_child(ml)
	machine_lights.append([ml, panel.material_override if panel is MeshInstance3D else panel.get_child(1).material_override])
	neon.append([tube, 0.4, color])
	return root

func _front(root: Node3D) -> Vector3:
	return root.to_global(Vector3(0, 1.0, -1.0))

func _place_machines() -> void:
	var perk_spots := {"marksman": [Vector3(44.8, 0, 22), PI / 2, "circle"], "ironhide": [Vector3(-8.8, 0, -14), -PI / 2, "heart"], "quickhand": [Vector3(24.8, 0, 6), PI / 2, "circle"], "fleetfoot": [Vector3(8.8, 0, 7.5), PI / 2, "bolt"], "lazarus": [Vector3(3.5, 0, 9.1), 0.0, "heart"]}
	for id in perk_spots:
		var pd: Dictionary = Perks.ALL[id]
		var m := _machine(perk_spots[id][0], perk_spots[id][1], pd.color, pd.name, perk_spots[id][2])
		var pid: String = id
		game.add_interactable(_front(m), 2.2,
			func(pl): return game.perk_prompt(pl, pid),
			func(pl): game.buy_perk(pl, pid))
	_build_forge(Vector3(18, 0, -24.4))
	# Power switch in Generator Wing
	var sw := Node3D.new(); sw.position = Vector3(3, 0, -24.3); add_child(sw)
	box(Vector3(0.8, 1.2, 0.3), Vector3(0, 1.4, 0), mats.metal, true, 1, sw)
	var lever := box(Vector3(0.1, 0.5, 0.1), Vector3(0, 1.5, 0.25), _emit(Color(1, 0.2, 0.1), 2.0), false, 1, sw)
	lever.rotation.x = 0.6; lever.name = "Lever"
	label("POWER", Vector3(3, 2.3, -24.1), 0.0, 48, Color(1, 0.3, 0.2))
	game.add_interactable(Vector3(3, 1.0, -23.3), 2.2,
		func(pl): return "" if game.facility.power_on else "Throw the power switch",
		func(pl): game.throw_power(lever))
	# Mystery Crate: starts in the Lab, relocates between these spots
	crate_spots = [
		[Vector3(16, 0, 6.6), PI, "Lab Corridor"],
		[Vector3(36, 0, 8.4), PI, "Loading Yard"],
		[Vector3(-6, 0, -24.6), 0.0, "Generator Wing"],
		[Vector3(20, 0, -13.6), 0.0, "Cold Storage"],
		[Vector3(-6, 0, 8.6), PI, "Intake Hall"],
	]
	var crate := CrateNode.new(); crate.game = game; add_child(crate); crate.build()
	game.crate_node = crate
	var marker := label("MYSTERY CRATE", Vector3(0, 2.3, 0), 0.0, 44, Color(0.5, 0.9, 1.0))
	marker.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	remove_child(marker); crate.add_child(marker)
	game.crate_it = game.add_interactable(Vector3.ZERO, 2.2, func(pl): return game.crate_prompt(pl), func(pl): game.use_crate(pl))
	move_crate(crate_spots[0][0], crate_spots[0][1])
	# Wall-buys
	# Armory (menu): the chosen starter gun hangs in the spawn room; the others take the remaining spots.
	var order: Array = GameSettings.STARTER_GUNS.duplicate()
	var starter: String = game.settings.starter_gun if game.settings and game.settings.starter_gun in order else "smg"
	order.erase(starter); order.push_front(starter)
	_wall_buy(order[0], Vector3(-9.75, 1.6, -3), PI / 2)
	_wall_buy(order[1], Vector3(-9.75, 1.6, -20), PI / 2)
	_wall_buy(order[2], Vector3(14, 1.6, 9.75), PI)
	# Armor racks
	_armor_rack("light", Vector3(-4, 0, -9.6), 0.0)
	_armor_rack("medium", Vector3(25.6, 0, -4), -PI / 2)
	_armor_rack("heavy", Vector3(14, 0, -25.6), 0.0)

func move_crate(pos: Vector3, rot_y: float) -> void:
	var c: CrateNode = game.crate_node
	c.position = pos; c.rotation.y = rot_y
	if game.crate_it: game.crate_it.pos = pos + Vector3(sin(rot_y), 0, cos(rot_y)) * 1.0 + Vector3.UP

## Overcharge Forge: anvil block, three counter-rotating rings, sparks, hum.
func _build_forge(pos: Vector3) -> void:
	var c := Color(0.7, 0.3, 1.0)
	var root := _machine(pos, PI, c, OverchargeForge.NAME, "circle")
	var core := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44; core.mesh = sm
	core.material_override = _emit(Color(0.85, 0.5, 1.0), 2.5); core.position = Vector3(0, 2.9, 0); root.add_child(core)
	for i in 3:
		var r := MeshInstance3D.new(); var tm := TorusMesh.new()
		tm.inner_radius = 0.42 + i * 0.13; tm.outer_radius = 0.46 + i * 0.13; tm.rings = 24; tm.ring_segments = 6
		r.mesh = tm; r.material_override = _emit(c.lightened(0.2 * i), 1.6); r.position = core.position
		root.add_child(r); forge_rings.append(r)
	var sp := CPUParticles3D.new(); sp.amount = 24; sp.lifetime = 0.8; sp.position = core.position
	sp.direction = Vector3.UP; sp.spread = 70; sp.initial_velocity_min = 1.0; sp.initial_velocity_max = 2.5
	sp.gravity = Vector3(0, -4, 0); sp.scale_amount_min = 0.5
	var q := QuadMesh.new(); q.size = Vector2(0.04, 0.04); var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.9, 0.7, 1.0); q.material = qm; sp.mesh = q
	root.add_child(sp); dust.append(sp)
	var hum := AudioStreamPlayer3D.new(); hum.stream = load("res://audio/forge_hum.wav"); hum.unit_size = 3.0
	hum.max_distance = 18.0; hum.volume_db = -6; hum.position = Vector3(0, 1.5, 0); hum.autoplay = true
	root.add_child(hum)
	hum.finished.connect(hum.play)
	game.add_interactable(_front(root), 2.4, func(pl): return game.forge_prompt(pl), func(pl): game.use_forge(pl))

# ---------------------------------------------------------------- easter egg
func _place_fuses() -> void:
	var spots := {"catwalk": Vector3(16, 3.2, -9.7), "yard": Vector3(45.7, 3.5, 9.7), "cold": Vector3(25.7, 3.4, -25.7)}
	for id in spots:
		var sb := StaticBody3D.new(); sb.collision_layer = 1; sb.collision_mask = 0; sb.set_meta("fuse", id)
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(0.3, 0.4, 0.3); cs.shape = sh; sb.add_child(cs)
		var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.07; cm.bottom_radius = 0.07; cm.height = 0.34
		mi.mesh = cm; var m := _emit(Color(0.25, 0.6, 0.9), 0.35); mi.material_override = m; sb.add_child(mi)
		var cap := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.18, 0.06, 0.18); cap.mesh = bm
		cap.material_override = mats.metal; cap.position.y = 0.2; sb.add_child(cap)
		sb.position = spots[id]; add_child(sb)
		var l := OmniLight3D.new(); l.light_color = Color(0.3, 0.7, 1.0); l.light_energy = 0.25; l.omni_range = 1.6
		sb.add_child(l)
		fuses[id] = [m, l]

func fuse_lit(id: String) -> void:
	if not fuses.has(id): return
	var m: StandardMaterial3D = fuses[id][0]
	m.emission = Color(0.4, 1.0, 0.9); m.emission_energy_multiplier = 4.0
	fuses[id][1].light_energy = 2.0

## 5-second upgrade show: rings spin up, core flares, sparks pour out.
func forge_working(secs: float) -> void:
	forge_work = secs

func _process(dt: float) -> void:
	_t += dt
	forge_work = maxf(0.0, forge_work - dt)
	var on: bool = game != null and game.facility.power_on
	for i in forge_rings.size():
		var r: Node3D = forge_rings[i]
		var spd := (1.4 if on else 0.25) * (1.0 + i * 0.4) * (1 if i % 2 == 0 else -1) * (1.0 + 7.0 * sin(clampf(forge_work / OverchargeForge.FORGE_TIME, 0, 1) * PI))
		r.scale = Vector3.ONE * (1.0 + (0.25 * sin(_t * 20.0) if forge_work > 0.0 else 0.0))
		r.rotation.x += dt * spd; r.rotation.y += dt * spd * 0.7
	var alarm: bool = game != null and game.round >= ALARM_ROUND and not game.over
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for i in alarm_lights.size():
		var al: OmniLight3D = alarm_lights[i]
		al.visible = alarm
		if alarm:
			var k := pow(0.5 + 0.5 * sin(_t * 5.0 + i * 1.3), 3.0)
			al.light_energy = 2.6 * k; alarm_mats[i].emission_energy_multiplier = 0.5 + 5.0 * k
	for n in neon:
		var m: StandardMaterial3D = n[0]
		var base: float = 3.2 if on else 0.4
		m.emission_energy_multiplier = base * (0.92 + 0.08 * sin(_t * 9.0 + n[1] * 10.0)) * (0.2 if not on and fmod(_t * 1.7 + n[1], 3.0) < 0.1 else 1.0)

func _wall_buy(id: String, pos: Vector3, rot_y: float) -> void:
	var w := Weapons.make(id)
	var g := ModelLib.gun(Weapons.MODELS.get(id, "pistol"))
	g.position = pos; g.rotation.y = rot_y + PI / 2; g.scale = Vector3.ONE * 1.6
	add_child(g)
	# chalk outline behind the gun
	var fwd0 := Vector3(sin(rot_y), 0, cos(rot_y))
	var ch := box(Vector3(1.4, 0.55, 0.02) if absf(fwd0.z) > 0.5 else Vector3(0.02, 0.55, 1.4), pos - fwd0 * 0.02, _emit(Color(0.85, 0.85, 0.8), 0.15), false)
	ch.transparency = 0.6
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	label("%s\n%d" % [w.name, Weapons.WALL_PRICES[id]], pos + Vector3(0, 0.55, 0) + fwd * 0.05, rot_y, 36, Color(0.95, 0.95, 0.9))
	game.add_interactable(pos + fwd * 1.0 - Vector3(0, 0.6, 0), 2.0,
		func(pl): return game.wall_prompt(pl, id), func(pl): game.buy_wall(pl, id))

func _armor_rack(pack_id: String, pos: Vector3, rot_y: float) -> void:
	var p: Dictionary = ArmorState.PACKS[pack_id]
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; add_child(root)
	box(Vector3(1.0, 1.6, 0.3), Vector3(0, 0.8, 0), mats.plate, true, 1, root)
	box(Vector3(0.6, 0.7, 0.15), Vector3(0, 1.1, 0.2), _emit(Color(0.2, 0.9, 0.4), 0.8), false, 1, root)
	var l := Label3D.new(); l.text = "%s\n+%d armor  %d" % [p.name, p.armor, p.cost]; l.font_size = 30; l.pixel_size = 0.004
	l.outline_size = 8; l.shaded = false; l.position = Vector3(0, 1.85, 0.2); root.add_child(l)
	var pid: String = pack_id
	game.add_interactable(root.to_global(Vector3(0, 1.0, 1.0)), 2.0,
		func(pl): return "%s (+%d armor): %d" % [p.name, p.armor, p.cost],
		func(pl): game.buy_armor(pl, pid))

func set_power(on: bool) -> void:
	for l in room_lights: l.visible = on
	for l in emergency_lights: l.base = 0.3 if on else 1.2
	for pair in machine_lights:
		pair[0].light_energy = 1.5 if on else 0.0
		pair[1].emission_energy_multiplier = 3.0 if on else 0.3
