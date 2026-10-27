class_name FacilityMap
extends NavigationRegion3D
## "Blackwater Research Annex": original map built in code. Intake Hall (start) plus three buyable
## areas: Generator Wing (power switch), Lab Corridor, Cold Storage. Everything is primitives.

const H := 4.0
const T := 0.4

var game
var windows := {}      # id -> WindowBarricade
var doors := {}        # id -> StaticBody3D
var room_lights: Array = []    # white lights enabled by power
var emergency_lights: Array = []
var machine_lights: Array = []
var mats := {}

func _ready() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5; nm.agent_height = 2.0; nm.agent_max_climb = 0.25
	nm.cell_size = 0.25; nm.cell_height = 0.25
	navigation_mesh = nm

func _noise_tex(freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new(); n.frequency = freq; n.fractal_octaves = 4
	var tx := NoiseTexture2D.new(); tx.noise = n; tx.width = 256; tx.height = 256; tx.seamless = true
	return tx

func _mat(c: Color, tex := true, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rough; m.metallic = metal
	if tex:
		m.albedo_texture = _noise_tex(0.02); m.uv1_triplanar = true; m.uv1_scale = Vector3(0.35, 0.35, 0.35)
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
			_wall_piece(a, dir, along_x, c[0], c[1], 0.0, 1.0, wm)
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

func light(pos: Vector3, color: Color, energy: float, rng: float, flicker := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	if flicker: l.set_script(load("res://scripts/game/flicker_light.gd"))
	l.light_color = color; l.light_energy = energy; l.omni_range = rng; l.position = pos
	l.omni_attenuation = 1.2
	add_child(l)
	return l

func build(p_game) -> void:
	game = p_game
	mats.wall = _mat(Color(0.42, 0.42, 0.4))
	mats.floor = _mat(Color(0.26, 0.25, 0.24))
	mats.ground = _mat(Color(0.12, 0.14, 0.1))
	mats.trim = _mat(Color(0.1, 0.09, 0.08), false)
	mats.door = _mat(Color(0.3, 0.32, 0.35), true, 0.6, 0.5)
	mats.stripe = _mat(Color(0.75, 0.6, 0.1), false)
	mats.metal = _mat(Color(0.3, 0.31, 0.33), true, 0.5, 0.6)
	mats.ceiling = _mat(Color(0.2, 0.2, 0.2))
	mats.lamp = _emit(Color(1.0, 0.92, 0.75), 2.0)
	# ground (outside + floors share one slab so the navmesh is continuous outside)
	box(Vector3(70, 1, 70), Vector3(8, -0.5, -8), mats.ground)
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
	wall(Vector2(26, 10), Vector2(26, -26))
	# interior walls with buyable doors
	wall(Vector2(-10, -10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "north"}])
	wall(Vector2(10, 10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "east"}])
	wall(Vector2(10, -10), Vector2(10, -26), [{at = 8.0, w = 2.4, kind = "door", id = "cold"}])
	wall(Vector2(10, -10), Vector2(26, -10))
	# props: crates, pipes, desks (obstacles)
	for p in [Vector3(-7, 0.5, -7), Vector3(-7.6, 0.5, -6), Vector3(6.5, 0.5, 6.5), Vector3(22, 0.5, 6), Vector3(22, 0.5, -22), Vector3(-6, 0.5, -22), Vector3(5, 0.5, -20)]:
		box(Vector3(1, 1, 1), p, _mat(Color(0.32, 0.26, 0.18)))
	box(Vector3(3, 0.9, 1.0), Vector3(18, 0.45, -3), mats.metal)  # lab bench
	box(Vector3(3, 0.9, 1.0), Vector3(18, 0.45, 3.5), mats.metal)
	box(Vector3(1.2, 2.6, 4), Vector3(24.6, 1.3, -18), _mat(Color(0.75, 0.8, 0.85), true, 0.3, 0.3))  # cold units
	box(Vector3(4, 2.4, 2), Vector3(0, 1.2, -24.5), mats.metal)  # generator block
	for x in [-6, 0, 6]:
		box(Vector3(0.25, 0.25, 36), Vector3(x + 2, H - 0.3, -8), mats.metal, false)  # ceiling pipes
	# ceiling lamps: emergency red (power off) + white (power on)
	for p in [Vector3(0, H - 0.3, 0), Vector3(0, H - 0.3, -18), Vector3(18, H - 0.3, 0), Vector3(18, H - 0.3, -18)]:
		box(Vector3(1.4, 0.08, 0.4), p + Vector3(0, 0.1, 0), mats.lamp, false)
		var w := light(p + Vector3(0, -0.4, 0), Color(1.0, 0.9, 0.75), 2.2, 12.0)
		w.visible = false; room_lights.append(w)
		emergency_lights.append(light(p + Vector3(2, -0.5, 2), Color(1.0, 0.15, 0.08), 1.2, 9.0))
	# moon
	var moon := DirectionalLight3D.new(); moon.light_color = Color(0.45, 0.55, 0.8); moon.light_energy = 0.25
	moon.rotation_degrees = Vector3(-50, 30, 0); add_child(moon)
	_place_machines()

func _machine(pos: Vector3, rot_y: float, color: Color, title: String) -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; add_child(root)
	box(Vector3(1.2, 2.2, 0.8), Vector3(0, 1.1, 0), _mat(color.darkened(0.6), true, 0.4, 0.4), true, 1, root)
	var panel := box(Vector3(0.9, 0.9, 0.05), Vector3(0, 1.45, -0.42), _emit(color, 0.3), false, 1, root)
	var l := Label3D.new(); l.text = title; l.font_size = 36; l.pixel_size = 0.004; l.outline_size = 8
	l.shaded = false; l.position = Vector3(0, 2.35, -0.42); l.rotation.y = PI; l.modulate = color.lightened(0.3)
	root.add_child(l)
	var ml := OmniLight3D.new(); ml.light_color = color; ml.light_energy = 0.0; ml.omni_range = 4.0
	ml.position = Vector3(0, 1.5, -1.0); root.add_child(ml)
	machine_lights.append([ml, panel])
	return root

func _front(root: Node3D) -> Vector3:
	return root.to_global(Vector3(0, 1.0, -1.0))

func _place_machines() -> void:
	# Iron Hide Tonic (Generator Wing), Quickhand Draught (Lab), Fleetfoot Phial (Intake)
	var perk_spots := {"ironhide": [Vector3(-8.8, 0, -14), -PI / 2], "quickhand": [Vector3(24.8, 0, 6), PI / 2], "fleetfoot": [Vector3(8.8, 0, 7.5), PI / 2]}
	for id in perk_spots:
		var pd: Dictionary = Perks.ALL[id]
		var m := _machine(perk_spots[id][0], perk_spots[id][1], pd.color, pd.name)
		var pid: String = id
		game.add_interactable(_front(m), 2.2,
			func(pl): return game.perk_prompt(pl, pid),
			func(pl): game.buy_perk(pl, pid))
	# Overcharge Forge in Cold Storage
	var f := _machine(Vector3(18, 0, -24.8), PI, Color(0.7, 0.3, 1.0), OverchargeForge.NAME)
	game.add_interactable(_front(f), 2.4, func(pl): return game.forge_prompt(pl), func(pl): game.use_forge(pl))
	# Power switch in Generator Wing
	var sw := Node3D.new(); sw.position = Vector3(3, 0, -24.3); add_child(sw)
	box(Vector3(0.8, 1.2, 0.3), Vector3(0, 1.4, 0), mats.metal, true, 1, sw)
	var lever := box(Vector3(0.1, 0.5, 0.1), Vector3(0, 1.5, 0.25), _emit(Color(1, 0.2, 0.1), 2.0), false, 1, sw)
	lever.rotation.x = 0.6; lever.name = "Lever"
	label("POWER", Vector3(3, 2.3, -24.1), 0.0, 48, Color(1, 0.3, 0.2))
	game.add_interactable(Vector3(3, 1.0, -23.3), 2.2,
		func(pl): return "" if game.facility.power_on else "Throw the power switch",
		func(pl): game.throw_power(lever))
	# Mystery Crate in the Lab Corridor
	var crate := CrateNode.new(); crate.position = Vector3(18, 0, -8.6); add_child(crate); crate.build()
	game.crate_node = crate
	label("MYSTERY CRATE", Vector3(18, 2.4, -9.5), 0.0, 44, Color(0.5, 0.9, 1.0))
	game.add_interactable(Vector3(18, 1.0, -7.6), 2.2, func(pl): return game.crate_prompt(pl), func(pl): game.use_crate(pl))
	# Wall-buys (chalk outline + label on the wall)
	_wall_buy("smg", Vector3(-9.75, 1.6, -3), PI / 2)
	_wall_buy("rifle", Vector3(-9.75, 1.6, -20), PI / 2)
	_wall_buy("scatter", Vector3(14, 1.6, 9.75), PI)
	# Armor racks
	_armor_rack("light", Vector3(-4, 0, -9.6), 0.0)
	_armor_rack("medium", Vector3(25.6, 0, -4), -PI / 2)
	_armor_rack("heavy", Vector3(14, 0, -25.6), 0.0)

func _wall_buy(id: String, pos: Vector3, rot_y: float) -> void:
	var w := Weapons.make(id)
	var g := GunModel.build(w)
	g.position = pos; g.rotation.y = rot_y + PI / 2; g.scale = Vector3.ONE * 1.4
	add_child(g)
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	label("%s\n%d" % [w.name, Weapons.WALL_PRICES[id]], pos + Vector3(0, 0.55, 0) + fwd * 0.05, rot_y, 36, Color(0.95, 0.95, 0.9))
	game.add_interactable(pos + fwd * 1.0 - Vector3(0, 0.6, 0), 2.0,
		func(pl): return game.wall_prompt(pl, id), func(pl): game.buy_wall(pl, id))

func _armor_rack(pack_id: String, pos: Vector3, rot_y: float) -> void:
	var p: Dictionary = ArmorState.PACKS[pack_id]
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; add_child(root)
	box(Vector3(1.0, 1.6, 0.3), Vector3(0, 0.8, 0), mats.metal, true, 1, root)
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
		pair[1].material_override.emission_energy_multiplier = 3.0 if on else 0.3
