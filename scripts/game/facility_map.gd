class_name FacilityMap
extends NavigationRegion3D
## "Ashgrove, Main Street": the original abandoned-town map of VICTOR ZOMBIES (Victorious Framework),
## built in code. The Victory Diner (start) joins the Back Alley (generator + power), Hollis Auto Repair
## (Overcharge Forge) and Mercer's General Store in one loop; the store opens onto Main Street, the
## street onto the Courtyard evacuation point, and the Side Alley closes a second loop back to the store.
## Area ids in the rules (intake / generator / cold / lab / yard / pump) are unchanged from v8, so doors,
## windows, spawns and the economy carry over. Surfaces: CC0 ambientCG PBR sets + original generated
## town art (tools/gen_town_art.py); props: CC0 Quaternius models. See ASSETS.md.

const H := 4.0
## Secondary lamps (x, z): three per area around its main lamp, plus two over the Courtyard.
const EXTRA_LAMPS := [Vector2(-6, 6), Vector2(6, 6), Vector2(-6, -6), Vector2(-6, -14), Vector2(6, -22), Vector2(-6, -22),
	Vector2(13, 6), Vector2(23, 6), Vector2(22, -6), Vector2(14, -14), Vector2(22, -22), Vector2(14, -22),
	Vector2(31, 14), Vector2(41, 26)]
const T := 0.4
## Roofed rooms (x0, z0, x1, z1): lamps inside hang from a ceiling, lamps outside hang from cables.
const ROOFED := [Rect2(-10, -10, 20, 20), Rect2(10, -10, 16, 20), Rect2(10, -26, 16, 16)]

var game
var kit: TownKit
var windows := {}      # id -> WindowBarricade
var doors := {}        # id -> StaticBody3D
var room_lights: Array = []    # lights enabled by power
var emergency_lights: Array = []
var bounce_lights: Array = []
const BOUNCE_OFF := 0.18
const BOUNCE_ON := 0.45
var machine_lights: Array = []
var mats := {}
var crate_spots: Array = []   # [pos, rot_y, area label]
var fuses := {}               # id -> [mesh material, light]
var dust: Array = []
var shadow_lights: Array = []
var forge_rings: Array = []
var forge_work := 0.0   ## seconds left on the current upgrade animation
## v7.3: perk-machine glow after power. The old 3.0 panel / 3.2 neon / 1.5 light blew the machine front
## out to a white slab at arm's length (glow + tonemap saturate the emission); these read as lit
## signage without clipping.
const MACHINE_PANEL_ON := 0.7
const MACHINE_NEON_ON := 1.3
const MACHINE_LIGHT_ON := 0.8
const MACHINE_EMBLEM := 0.7
var neon: Array = []          # [material, base energy]
var _t := 0.0
var alarm_lights: Array = []   ## pulsing red alarms that kick in after round 5
var alarm_mats: Array = []
const ALARM_ROUND := 6
var fires: Array = []          ## distant fire-glow materials (flickered in _process)
const SIGN_NEON_OFF := 0.12    ## the diner's neon before the generator is running
const SIGN_NEON_ON := 2.2
const LAMP_OFF := 0.06         ## dead lamp glass before the generator runs

func _ready() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5; nm.agent_height = 2.0; nm.agent_max_climb = 0.25
	nm.cell_size = 0.25; nm.cell_height = 0.25
	navigation_mesh = nm

func _tex(name: String, kind: String) -> Texture2D:
	return load("res://assets/textures/%s_%s.jpg" % [name, kind])

func _town(name: String) -> Texture2D:
	return load("res://assets/town/%s.png" % name)

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

func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

func _emit(c: Color, e := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	return m

## Upper-storey facade: generated window texture with its own emission map (a few lit rooms).
func _facade(name: String, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_texture = _town(name); m.albedo_color = tint; m.roughness = 0.95
	m.emission_enabled = true; m.emission_texture = _town(name + "_emit"); m.emission = Color(1.0, 0.78, 0.5)
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY; m.emission_energy_multiplier = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _corr(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_texture = _town("corrugated_albedo"); m.albedo_color = tint
	m.normal_enabled = true; m.normal_texture = _town("corrugated_normal"); m.roughness = 0.7; m.metallic = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _build_mats() -> void:
	# coordinated town palette: brick, concrete, asphalt, glass, corroded metal, weathered signage
	mats.brick = _pbr("bricks090", Color(0.62, 0.56, 0.54), 0.45)
	mats.brick_dark = _pbr("bricks090", Color(0.42, 0.4, 0.42), 0.45)
	mats.wall_brick = mats.brick; mats.wall_ext = mats.brick_dark
	mats.diner_wall = _pbr("paintedplaster017", Color(0.74, 0.69, 0.58), 0.4)
	mats.store_wall = _pbr("paintedplaster016", Color(0.62, 0.62, 0.58), 0.3)
	mats.wall = mats.store_wall
	mats.conc = _pbr("concrete044c", Color(0.72, 0.72, 0.7), 0.5)
	mats.wall_low = mats.conc
	mats.kerb = _pbr("concrete034", Color(0.62, 0.62, 0.6), 0.5)
	mats.floor = _pbr("concrete031", Color(0.6, 0.6, 0.58), 0.3)
	mats.tile = _pbr("tiles074", Color(0.78, 0.76, 0.72), 0.5)
	mats.woodfloor = _pbr("woodfloor041", Color(0.7, 0.66, 0.6), 0.4)
	mats.ground = _pbr("asphalt026c", Color(0.62, 0.63, 0.64), 0.22)
	mats.cobble = _pbr("bricks076c", Color(0.66, 0.66, 0.66), 0.4)
	mats.dirt = _pbr("ground037", Color(0.5, 0.5, 0.46), 0.3)
	mats.wood = _pbr("planks021", Color(0.6, 0.5, 0.4), 0.6)
	mats.plank = _pbr("planks021", Color(0.42, 0.32, 0.22), 0.8)
	mats.door_wood = _pbr("planks021", Color(0.3, 0.26, 0.24), 0.7)
	mats.rust = _pbr("rust004", Color.WHITE, 0.6, 0.4)
	mats.trim = _pbr("metal049a", Color(0.3, 0.29, 0.28), 1.0, 0.5)
	mats.door = _pbr("metalplates006", Color(0.62, 0.64, 0.68), 0.6, 0.7)
	mats.stripe = _mat(Color(0.75, 0.6, 0.1), 0.7)
	mats.metal = _pbr("metal032", Color(0.7, 0.7, 0.72), 0.8, 0.8)
	mats.steel = _pbr("metal032", Color(0.46, 0.48, 0.5), 0.8, 0.6)
	mats.plate = _pbr("diamondplate008c", Color(0.75, 0.75, 0.78), 0.6, 0.85)
	mats.ceiling = _pbr("paintedplaster017", Color(0.5, 0.5, 0.48), 0.3)
	mats.roof = _pbr("concrete031", Color(0.34, 0.34, 0.36), 0.3)
	mats.lamp = _emit(Color(1.0, 0.86, 0.62), LAMP_OFF)
	mats.lamp_cool = _emit(Color(0.82, 0.9, 1.0), 1.6)
	mats.corr = _corr(Color(0.86, 0.88, 0.9)); mats.corr_red = _corr(Color(0.86, 0.42, 0.34))
	mats.corr_blue = _corr(Color(0.42, 0.56, 0.78)); mats.corr_olive = _corr(Color(0.56, 0.62, 0.42))
	mats.facade_brick = _facade("facade_brick"); mats.facade_plaster = _facade("facade_plaster")
	mats.facade_concrete = _facade("facade_concrete", Color(0.8, 0.82, 0.86))
	var sg := StandardMaterial3D.new(); sg.albedo_texture = _town("signs"); sg.roughness = 0.8
	sg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats.signs = sg
	var sl := sg.duplicate() as StandardMaterial3D; sl.emission_enabled = true; sl.emission_texture = _town("signs_emit")
	sl.emission = Color.WHITE; sl.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY; sl.emission_energy_multiplier = SIGN_NEON_OFF
	mats.signs_lit = sl
	mats.sign_back = _mat(Color(0.1, 0.1, 0.11), 0.6, 0.4)
	var gl := StandardMaterial3D.new(); gl.albedo_texture = _town("glass_broken"); gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gl.cull_mode = BaseMaterial3D.CULL_DISABLED; gl.roughness = 0.08; gl.metallic = 0.2; gl.metallic_specular = 0.9
	mats.glass = gl
	var rp := StandardMaterial3D.new(); rp.albedo_texture = _town("road_paint"); rp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rp.roughness = 0.9; rp.uv1_triplanar = true; rp.uv1_scale = Vector3.ONE * 0.5; rp.render_priority = -1
	mats.paint = rp
	var rpy := rp.duplicate() as StandardMaterial3D; rpy.albedo_color = Color(0.95, 0.78, 0.25); mats.paint_yellow = rpy
	var vn := StandardMaterial3D.new(); vn.albedo_texture = _town("vinyl_red"); vn.roughness = 0.45; vn.uv1_triplanar = true; vn.uv1_scale = Vector3.ONE * 1.6
	mats.vinyl = vn
	mats.formica = _mat(Color(0.78, 0.74, 0.66), 0.35)
	mats.chrome = _mat(Color(0.72, 0.74, 0.76), 0.25, 0.9)
	mats.dark = _mat(Color(0.05, 0.05, 0.06), 1.0)
	mats.pane = _mat(Color(0.06, 0.08, 0.11), 0.15, 0.3)
	mats.carton = _pbr("planks021", Color(0.62, 0.5, 0.36), 2.0)
	mats.tin = _mat(Color(0.5, 0.2, 0.16), 0.5, 0.4)
	mats.canvas = _mat(Color(0.3, 0.34, 0.24), 0.95)
	mats.sandbag = _mat(Color(0.5, 0.45, 0.34), 1.0)
	mats.awn_red = _mat(Color(0.5, 0.13, 0.11), 0.9); mats.awn_green = _mat(Color(0.16, 0.3, 0.22), 0.9)
	mats.awn_cream = _mat(Color(0.66, 0.62, 0.5), 0.9)
	mats.cream = _mat(Color(0.74, 0.7, 0.6), 0.5); mats.diner_red = _mat(Color(0.56, 0.1, 0.09), 0.4)
	mats.red_glow = _emit(Color(1.0, 0.12, 0.06), 1.6)
	mats.amber_glow = _emit(Color(1.0, 0.62, 0.2), 1.4)

## Box with optional collider; returns the body (or mesh when no collider). Used for things that move
## or need their own node (doors, machines); static architecture goes through `kit` instead.
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

## Occlusion culling: solid walls and roofs hide whatever is behind them, so standing in the diner
## does not draw the street. Boxes are slightly thinner than the wall so nothing visible is culled.
func occluder(size: Vector3, pos: Vector3) -> void:
	var oi := OccluderInstance3D.new(); var bo := BoxOccluder3D.new(); bo.size = size
	oi.occluder = bo; oi.position = pos; add_child(oi)

## Invisible collision box (world geometry whose visuals are batched by the kit).
func collider(size: Vector3, pos: Vector3, yaw := 0.0, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.collision_layer = layer; sb.collision_mask = 0; sb.position = pos; sb.rotation.y = yaw
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	sb.add_child(cs); add_child(sb)
	return sb

func label(text: String, pos: Vector3, rot_y: float, size := 48, color := Color(0.9, 0.9, 0.85)) -> Label3D:
	var l := Label3D.new(); l.text = text; l.font_size = size; l.pixel_size = 0.004
	l.modulate = color; l.outline_size = 8; l.position = pos; l.rotation.y = rot_y
	l.shaded = false; l.double_sided = false
	add_child(l); return l

## Axis-aligned wall from a to b (x,z). gaps: [{at, w, kind, id, out, skin}] measured from a.
## style: core (material of the wall body), top (height), out (body lit by the skylight),
## pos / neg ([material, outdoor]: cladding on the +x/+z or -x/-z face, e.g. brick outside, plaster inside).
func wall(a: Vector2, b: Vector2, gaps: Array = [], style: Dictionary = {}) -> void:
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
	var top: float = style.get("top", H)
	for s in segs:
		if s[1] - s[0] < 0.01: continue
		_wall_piece(a, dir, along_x, s[0], s[1], 0.0, top, style)
	for c in cuts:
		var g: Dictionary = c[2]
		var p := a + dir * float(g.at)
		match g.kind:
			"window":
				_wall_piece(a, dir, along_x, c[0], c[1], 0.0, 1.0, style)
				_wall_piece(a, dir, along_x, c[0], c[1], 2.3, top, style)
				_frame(p, along_x, g.w, 1.0, 2.3, mats.plank)
				_make_window(p, along_x, g)
			"door":
				_wall_piece(a, dir, along_x, c[0], c[1], 3.0, top, style)
				_frame(p, along_x, g.w, 0.0, 3.0, mats.trim, true)
				_make_door(p, along_x, g)
			"shop":
				_wall_piece(a, dir, along_x, c[0], c[1], 0.0, 0.8, style)
				_wall_piece(a, dir, along_x, c[0], c[1], 2.9, top, style)
				_frame(p, along_x, g.w, 0.8, 2.9, mats.trim)
				_make_shop(p, along_x, g)
			"open":
				_wall_piece(a, dir, along_x, c[0], c[1], 3.2, top, style)
				_frame(p, along_x, g.w, 0.0, 3.2, mats.kerb)

func _wall_piece(a: Vector2, dir: Vector2, along_x: bool, s0: float, s1: float, y0: float, y1: float, style: Dictionary) -> void:
	var mid := a + dir * ((s0 + s1) / 2.0)
	var len := s1 - s0
	var size := Vector3(len, y1 - y0, T) if along_x else Vector3(T, y1 - y0, len)
	collider(size, Vector3(mid.x, (y0 + y1) / 2.0, mid.y))
	if len > 1.0 and y1 - y0 > 2.5: occluder(size * Vector3(1.0 if along_x else 0.6, 1, 0.6 if along_x else 1.0), Vector3(mid.x, (y0 + y1) / 2.0, mid.y))
	var n := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var core: Material = style.get("core", mats.brick)
	# visuals in <= 8 m runs so no mesh collects more than the renderer's per-object light limit
	var parts := maxi(1, int(ceil(len / 8.0)))
	for i in parts:
		var c := a + dir * (s0 + len * (i + 0.5) / parts)
		var pl := len / parts
		var ps := Vector3(pl, y1 - y0, T) if along_x else Vector3(T, y1 - y0, pl)
		var pc := Vector3(c.x, (y0 + y1) / 2.0, c.y)
		kit.outdoor = style.get("out", false)
		kit.box(core, ps, pc)
		for side in ["pos", "neg"]:
			var sgn := 1.0 if side == "pos" else -1.0
			if style.has(side):
				kit.outdoor = style[side][1]
				var cs := Vector3(pl, y1 - y0, 0.06) if along_x else Vector3(0.06, y1 - y0, pl)
				kit.box(style[side][0], cs, pc + n * sgn * (T / 2.0 + 0.03))
			if y0 == 0.0 and style.get("plinth", true):   # concrete plinth course
				kit.outdoor = style[side][1] if style.has(side) else style.get("out", false)
				var gs := Vector3(pl, 0.3, 0.05) if along_x else Vector3(0.05, 0.3, pl)
				kit.box(mats.kerb, gs, Vector3(c.x, 0.15, c.y) + n * sgn * (T / 2.0 + (0.085 if style.has(side) else 0.025)))

## Reveal around an opening: two jambs and a head, proud of both wall faces so doors and windows keep a
## readable silhouette. `lamp` adds an amber marker light above (doors).
func _frame(p: Vector2, along_x: bool, w: float, y0: float, y1: float, m: Material, lamp := false) -> void:
	kit.outdoor = true
	var d := T + 0.3
	for s: float in [-1.0, 1.0]:
		var o := Vector3(s * (w / 2.0 + 0.06), 0, 0) if along_x else Vector3(0, 0, s * (w / 2.0 + 0.06))
		kit.box(m, Vector3(0.12, y1 - y0, d) if along_x else Vector3(d, y1 - y0, 0.12), Vector3(p.x, (y0 + y1) / 2.0, p.y) + o)
	kit.box(m, Vector3(w + 0.24, 0.14, d) if along_x else Vector3(d, 0.14, w + 0.24), Vector3(p.x, y1 + 0.07, p.y))
	if y0 > 0.1: kit.box(m, Vector3(w + 0.3, 0.08, d + 0.14) if along_x else Vector3(d + 0.14, 0.08, w + 0.3), Vector3(p.x, y0 - 0.04, p.y))
	if lamp:
		for s: float in [-1.0, 1.0]:
			var o := Vector3(0, 0, s * (d / 2.0 + 0.05)) if along_x else Vector3(s * (d / 2.0 + 0.05), 0, 0)
			kit.box(mats.amber_glow, Vector3(0.36, 0.12, 0.1) if along_x else Vector3(0.1, 0.12, 0.36), Vector3(p.x, y1 + 0.3, p.y) + o, 0.0, Vector2.ZERO, false)

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
	collider(Vector3(g.w, 1.4, T) if along_x else Vector3(T, 1.4, g.w), Vector3(p.x, 1.65, p.y), 0.0, 8)
	game.add_interactable(w.center() - Vector3(outv.x, 0, outv.y) * 0.6, 2.0,
		func(pl): return "Hold to rebuild barricade (+%d points)" % Economy.REPAIR if w.bar.hp < w.bar.max_hp() else "",
		func(pl): game.repair_window(pl, w), true)
	# a dim cool light outside to silhouette whatever is climbing in
	var ol := OmniLight3D.new(); ol.light_color = Color(0.45, 0.55, 0.75); ol.light_energy = 0.8; ol.omni_range = 6
	ol.position = Vector3(p.x + outv.x * 3, 2.5, p.y + outv.y * 3); add_child(ol)

## Buyable door. skin: "steel" (default), "shutter" (corrugated roller door), "wood" (boarded door),
## "gate" (iron bars you can see through).
func _make_door(p: Vector2, along_x: bool, g: Dictionary) -> void:
	var gw: float = g.w
	var skin: String = g.get("skin", "steel")
	var size := Vector3(gw, 3.0, 0.25) if along_x else Vector3(0.25, 3.0, gw)
	var dm: Material = {"steel": mats.door, "shutter": mats.corr, "wood": mats.door_wood, "gate": mats.trim}[skin]
	var body := box(size, Vector3(p.x, 1.5, p.y), dm)
	var mesh := body.get_child(1) as MeshInstance3D
	var wide := func(len: float, hh: float, thick: float) -> Vector3: return Vector3(len, hh, thick) if along_x else Vector3(thick, hh, len)
	match skin:
		"steel":
			for y: float in [-1.2, -0.6]: box(wide.call(gw * 0.9, 0.2, 0.3), Vector3(0, y, 0), mats.stripe, false, 1, body)
		"wood":
			for k in 3:
				var bd := box(wide.call(gw + 0.3, 0.2, 0.34), Vector3(0, -0.8 + k * 0.8, 0), mats.plank, false, 1, body)
				bd.rotation = Vector3(0, 0, [0.1, -0.14, 0.07][k]) if along_x else Vector3([0.1, -0.14, 0.07][k], 0, 0)
		"gate":
			mesh.visible = false
			var n := int(gw / 0.2)
			for k in n + 1:
				var o := -gw / 2.0 + gw * k / n
				box(Vector3(0.05, 3.0, 0.05), Vector3(o, 0, 0) if along_x else Vector3(0, 0, o), mats.trim, false, 1, body)
			for y: float in [-1.3, 0.2, 1.4]: box(wide.call(gw, 0.08, 0.08), Vector3(0, y, 0), mats.trim, false, 1, body)
			box(wide.call(0.5, 0.36, 0.14), Vector3(0, -0.2, 0), mats.rust, false, 1, body)   # chained padlock plate
	doors[g.id] = body
	var d: Dictionary = Facility.DOORS[g.id]
	var rot := 0.0 if along_x else PI / 2
	for side in [-1, 1]:
		var l := Label3D.new(); l.text = "%s\n%d" % [d.label, d.cost]; l.font_size = 40; l.pixel_size = 0.004
		var dist: String = Facility.DISTRICTS[Facility.district_of(d.opens)].name
		if dist != d.label: l.text = "%s\n%s  ·  %d" % [d.label, dist, d.cost]
		l.outline_size = 8; l.modulate = Color(1, 0.85, 0.3); l.shaded = false
		l.position = (Vector3(0, 0.7, 0.18 * side) if along_x else Vector3(0.18 * side, 0.7, 0))
		l.rotation.y = rot + (0.0 if side > 0 else PI)
		body.add_child(l)
	game.add_interactable(Vector3(p.x, 1.0, p.y), 2.4,
		func(pl): return "" if facility_open(g.id) else Game.price_text(pl.economy.points, "Open %s" % d.label, d.cost),
		func(pl): game.buy_door(pl, g.id))

## Shattered shop window: you can see through it but not pass or shoot through (jagged glass, bars and
## plywood). Purely scenery: zombies only enter through the boarded WindowBarricade openings.
func _make_shop(p: Vector2, along_x: bool, g: Dictionary) -> void:
	var gw: float = g.w
	collider(Vector3(gw, 2.1, T * 0.5) if along_x else Vector3(T * 0.5, 2.1, gw), Vector3(p.x, 1.85, p.y))
	kit.outdoor = true
	var yaw := 0.0 if along_x else PI / 2
	kit.quad(mats.glass, gw, 2.1, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 1.85, p.y)), Rect2(0, 0, gw / 2.6, 1))
	var b := Basis(Vector3.UP, yaw)
	for k in int(gw / 0.9):   # mullions
		kit.box_xf(mats.trim, Vector3(0.06, 2.1, 0.08), Transform3D(b, Vector3(p.x, 1.85, p.y) + b * Vector3(-gw / 2.0 + (k + 1) * gw / (int(gw / 0.9) + 1), 0, 0)))
	var seed := int(p.x * 13.0 + p.y * 7.0)
	if seed % 3 != 0:   # some panes got a plywood sheet before the owners left
		var side := -1.0 if seed % 2 == 0 else 1.0
		kit.box_xf(mats.plank, Vector3(gw * 0.42, 1.9, 0.03), Transform3D(b * Basis(Vector3(0, 0, 1), 0.03 * side), Vector3(p.x, 1.8, p.y) + b * Vector3(side * gw * 0.26, 0, 0.12)))

func facility_open(id: String) -> bool:
	return game.facility.open_doors.get(id, false)

func open_door(id: String) -> void:
	var b: Node3D = doors.get(id)
	if b:
		var game = get_parent()
		if game and game.get("fx"): game.fx.dirt_burst(b.global_position + Vector3.UP * 0.2)
		var x0: float = b.position.x
		var tw := create_tween()
		for i in 5:  # judder against its rusted rails before it gives way
			tw.tween_property(b, "position:x", x0 + (0.04 if i % 2 == 0 else -0.04), 0.06)
		tw.tween_property(b, "position:x", x0, 0.05)
		tw.tween_property(b, "position:y", -1.6, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): b.queue_free(); call_deferred("rebake"))

var _rebake_pending := false

## Only one async bake may run at a time; a request that lands mid-bake is queued and replayed when it ends.
func rebake() -> void:
	if is_baking():
		if not _rebake_pending:
			_rebake_pending = true
			bake_finished.connect(_on_bake_done, CONNECT_ONE_SHOT)
		return
	bake_navigation_mesh(true)

func _on_bake_done() -> void:
	_rebake_pending = false
	call_deferred("rebake")

# ---------------------------------------------------------------- sky + dusk light
## Blue-gray dusk: a cheap procedural gradient sky, one cool directional "skylight" from the bright
## western horizon (it skips roofed interiors, see TownKit.INDOOR_LAYER) and a pale early moon.
var moon_light: DirectionalLight3D
func build_sky() -> void:
	if game == null or game.env == null: return
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.25, 0.35); sm.sky_horizon_color = Color(0.56, 0.56, 0.58); sm.sky_curve = 0.3
	sm.ground_horizon_color = Color(0.5, 0.5, 0.52); sm.ground_bottom_color = Color(0.08, 0.09, 0.11)
	sm.sun_angle_max = 0.0; sm.sky_energy_multiplier = 1.0
	var sky := Sky.new(); sky.radiance_size = Sky.RADIANCE_SIZE_32; sky.sky_material = sm
	game.env.sky = sky; game.env.background_mode = Environment.BG_SKY
	game.env.fog_sky_affect = 0.0
	if moon_light == null: return
	var dir := Vector3(-0.35, 0.5, -0.8).normalized()
	var at := Vector3(18, 0, -8) + dir * 170.0
	for pair in [[9.0, Color(0.85, 0.9, 1.0, 0.9)], [34.0, Color(0.4, 0.5, 0.8, 0.22)]]:
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

func _dusk_light() -> void:
	var sun := DirectionalLight3D.new(); sun.name = "DuskLight"
	sun.light_color = Color(0.56, 0.64, 0.82); sun.light_energy = 0.95; sun.light_specular = 0.3
	sun.rotation_degrees = Vector3(-38, -62, 0); sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_cull_mask = 0xFFFFF & ~TownKit.INDOOR_LAYER
	add_child(sun); shadow_lights.append(sun); moon_light = sun

# ---------------------------------------------------------------- build
## Thin visual floor slab split into <= 10 m tiles (collision is the one big ground slab).
func floor_rect(mat: Material, x0: float, z0: float, x1: float, z1: float, y := 0.0, outdoor := true) -> void:
	kit.outdoor = outdoor
	var nx := maxi(1, int(ceil((x1 - x0) / 10.0))); var nz := maxi(1, int(ceil((z1 - z0) / 10.0)))
	var sx := (x1 - x0) / nx; var sz := (z1 - z0) / nz
	for i in nx:
		for j in nz:
			kit.box(mat, Vector3(sx, 0.04, sz), Vector3(x0 + (i + 0.5) * sx, y - 0.02 + 0.012, z0 + (j + 0.5) * sz), 0.0, Vector2.ZERO, false)

## Roof slab: its underside is the room's ceiling. Parapet + coping are skylit.
func roof(r: Rect2, ceil_mat: Material, band: Material, cap: Material, band_h := 0.7, uv_m := Vector2.ZERO) -> void:
	kit.outdoor = false
	var nx := maxi(1, int(ceil(r.size.x / 10.0))); var nz := maxi(1, int(ceil(r.size.y / 10.0)))
	for i in nx:
		for j in nz:
			kit.box(ceil_mat, Vector3(r.size.x / nx, 0.3, r.size.y / nz), Vector3(r.position.x + (i + 0.5) * r.size.x / nx, H + 0.15, r.position.y + (j + 0.5) * r.size.y / nz), 0.0, uv_m)
	occluder(Vector3(r.size.x - 0.4, 0.2, r.size.y - 0.4), Vector3(r.get_center().x, H + 0.15, r.get_center().y))
	kit.outdoor = true
	var c := r.get_center()
	for e in [[Vector3(r.size.x + 0.7, band_h, 0.3), Vector3(c.x, H + band_h / 2.0, r.position.y - 0.2)], [Vector3(r.size.x + 0.7, band_h, 0.3), Vector3(c.x, H + band_h / 2.0, r.end.y + 0.2)],
			[Vector3(0.3, band_h, r.size.y + 0.7), Vector3(r.position.x - 0.2, H + band_h / 2.0, c.y)], [Vector3(0.3, band_h, r.size.y + 0.7), Vector3(r.end.x + 0.2, H + band_h / 2.0, c.y)]]:
		kit.box(band, e[0], e[1], 0.0, uv_m)
		kit.box(cap, Vector3(e[0].x + 0.1, 0.1, e[0].z + 0.1), e[1] + Vector3(0, band_h / 2.0 + 0.05, 0))

## Dark room behind a neighbouring building's window, so the horde climbs out of a believable interior
## instead of thin air. `out` points from the window into that building.
func room_shell(p: Vector2, out: Vector2, w := 8.0, depth := 10.0) -> void:
	kit.outdoor = false
	var o := Vector3(out.x, 0, out.y); var side := Vector3(-out.y, 0, out.x)
	var c := Vector3(p.x, 0, p.y)
	var yaw := atan2(out.x, out.y)
	kit.box(mats.store_wall, Vector3(w, H, 0.2), c + o * depth + Vector3(0, H / 2.0, 0), yaw)
	for s: float in [-1.0, 1.0]: kit.box(mats.store_wall, Vector3(0.2, H, depth), c + o * depth * 0.5 + side * s * w * 0.5 + Vector3(0, H / 2.0, 0), yaw)
	kit.box(mats.woodfloor, Vector3(w, 0.04, depth), c + o * (depth * 0.5 + 0.25) + Vector3(0, 0.0, 0), yaw, Vector2.ZERO, false)
	kit.box(mats.ceiling, Vector3(w, 0.2, depth), c + o * (depth * 0.5 + 0.25) + Vector3(0, H + 0.1, 0), yaw)

func build(p_game) -> void:
	game = p_game
	_build_mats()
	kit = TownKit.new(self)
	# one ground slab under the whole town: playable floors and the zombie approach lanes share a navmesh
	collider(Vector3(100, 1, 92), Vector3(18, -0.5, -3))
	_build_diner()
	_build_alley()
	_build_garage()
	_build_store()
	_build_street()
	_build_court()
	_build_annex()
	_build_catwalk()
	Scenery.new(self).build()
	_build_lamps()
	_dusk_light()
	_place_machines()
	_place_fuses()
	kit.commit()

## Victory Diner (area "intake", x -10..10, z -10..10): the start room.
func _build_diner() -> void:
	var ext := [mats.brick, true]
	floor_rect(mats.tile, -10, -10, 10, 10, 0.0, false)
	wall(Vector2(-10, 10), Vector2(-10, -10), [
		{at = 3.8, w = 2.6, kind = "shop"},
		{at = 8.0, w = 1.8, kind = "window", id = "w_west", out = Vector2(-1, 0)},
		{at = 17.4, w = 2.6, kind = "shop"}], {core = mats.diner_wall, neg = ext})
	wall(Vector2(-10, 10), Vector2(10, 10), [
		{at = 2.2, w = 2.2, kind = "shop"},
		{at = 7.0, w = 1.8, kind = "window", id = "w_south", out = Vector2(0, 1)},
		{at = 10.4, w = 2.6, kind = "shop"}], {core = mats.diner_wall, pos = ext})
	wall(Vector2(-10, -10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "north", skin = "wood"}], {core = mats.diner_wall, neg = ext})
	wall(Vector2(10, 10), Vector2(10, -10), [{at = 10.0, w = 2.4, kind = "door", id = "east"}], {core = mats.diner_wall, pos = [mats.store_wall, false]})
	roof(Rect2(-10, -10, 20, 20), mats.ceiling, mats.cream, mats.diner_red)
	kit.outdoor = true
	for r in [[Vector3(20.9, 0.16, 0.34), Vector3(0, H + 0.2, 10.22)], [Vector3(0.34, 0.16, 20.9), Vector3(-10.22, H + 0.2, 0)], [Vector3(20.9, 0.16, 0.34), Vector3(0, H + 0.2, -10.22)]]:
		kit.box(mats.diner_red, r[0], r[1])   # the red band every roadside diner wears

## Back Alley (area "generator", x -10..10, z -26..-10): open-air service lane, generator + power switch.
func _build_alley() -> void:
	floor_rect(mats.ground, -10, -26, 10, -10)
	var bd := {core = mats.brick_dark, out = true}
	wall(Vector2(-10, -10), Vector2(-10, -26), [{at = 8.0, w = 1.8, kind = "window", id = "w_gen", out = Vector2(-1, 0)}], bd)
	wall(Vector2(-10, -26), Vector2(10, -26), [{at = HiddenRoom.CRACK_POS.x + 10.0, w = HiddenRoom.CRACK_W, kind = "hidden"}], bd)
	room_shell(Vector2(-10, -18), Vector2(-1, 0))
	kit.outdoor = true
	# tenement to the west, an office block over the sealed annex to the north
	kit.block(Rect2(-18, -27, 8, 17.5), H, 11.2, mats.facade_brick, mats.brick_dark, mats.kerb)
	kit.block(Rect2(-10, -34, 20.5, 8), H + 0.3, 9.4, mats.facade_plaster, mats.conc, mats.kerb)

## Hollis Auto Repair (area "cold", x 10..26, z -26..-10): the workshop with the Overcharge Forge.
func _build_garage() -> void:
	floor_rect(mats.floor, 10, -26, 26, -10, 0.0, false)
	var cc := {core = mats.conc, out = false}
	wall(Vector2(10, -10), Vector2(10, -26), [{at = 8.0, w = 2.4, kind = "door", id = "cold", skin = "shutter"}], {core = mats.conc, neg = [mats.conc, true]})
	wall(Vector2(10, -26), Vector2(26, -26), [{at = 12.0, w = 1.8, kind = "window", id = "w_cold", out = Vector2(0, -1)}], cc)
	wall(Vector2(26, -10), Vector2(26, -26), [], {core = mats.conc, pos = [mats.conc, true]})
	wall(Vector2(10, -10), Vector2(26, -10), [{at = 15.0, w = 1.7, kind = "door", id = "service"}], {core = mats.store_wall, neg = [mats.conc, false]})
	roof(Rect2(10, -26, 16, 16), mats.corr, mats.corr, mats.trim, 1.3, Vector2(1.6, 1.6))
	room_shell(Vector2(22, -26), Vector2(0, -1), 7.0)
	kit.outdoor = false
	for x: float in [14.0, 18.0, 22.0]:   # steel roof trusses
		kit.box(mats.steel, Vector3(0.14, 0.3, 15.6), Vector3(x, H - 0.2, -18))
	kit.outdoor = true
	kit.block(Rect2(18, -36, 8.5, 10), H + 1.3, 10.5, mats.facade_brick, mats.brick_dark, mats.kerb)

## Mercer's General Store (area "lab", x 10..26, z -10..10): mezzanine, aisles, storefront on Main Street.
func _build_store() -> void:
	floor_rect(mats.woodfloor, 10, -10, 26, 10, 0.0, false)
	wall(Vector2(10, 10), Vector2(26, 10), [
		{at = 6.0, w = 1.8, kind = "window", id = "w_lab", out = Vector2(0, 1)},
		{at = 12.5, w = 2.4, kind = "door", id = "alley", skin = "wood"}], {core = mats.store_wall, pos = [mats.brick_dark, true]})
	wall(Vector2(26, 10), Vector2(26, -10), [
		{at = 6.2, w = 2.6, kind = "shop"},
		{at = 10.0, w = 2.6, kind = "door", id = "yard"},
		{at = 16.5, w = 2.6, kind = "shop"}], {core = mats.store_wall, pos = [mats.brick, true]})
	roof(Rect2(10, -10, 16, 20), mats.ceiling, mats.brick, mats.kerb, 0.3)
	kit.outdoor = true
	kit.block(Rect2(10, -10, 16.3, 20), H + 0.3, 8.2, mats.facade_plaster, mats.brick, mats.kerb)
	# Side Alley (x 20..26, z 10..14): store back door -> Courtyard, closing the street loop
	floor_rect(mats.cobble, 20.2, 10.2, 26, 14)
	wall(Vector2(20, 10.2), Vector2(20, 14), [], {core = mats.brick_dark, out = true})
	wall(Vector2(20, 14), Vector2(26, 14), [], {core = mats.brick_dark, out = true})
	room_shell(Vector2(16, 10), Vector2(0, 1))
	kit.outdoor = true
	kit.block(Rect2(8, 10.3, 12, 13), H, 9.6, mats.facade_brick, mats.brick_dark, mats.kerb)
	kit.block(Rect2(20.2, 14.2, 5.8, 9), 0.0, 9.6, mats.facade_brick, mats.brick_dark, mats.kerb)

## Main Street (area "yard", x 26..46, z -16..10): container blockade north, storefronts east.
func _build_street() -> void:
	floor_rect(mats.ground, 26, -16, 46, 10)
	floor_rect(mats.ground, 26, -46, 46, -16)
	var bk := {core = mats.brick, out = true}
	wall(Vector2(46, 10), Vector2(46, -16), [
		{at = 6.0, w = 1.8, kind = "window", id = "w_yard_s", out = Vector2(1, 0)},
		{at = 18.0, w = 1.8, kind = "window", id = "w_yard_n", out = Vector2(1, 0)}], bk)
	wall(Vector2(26, 10), Vector2(46, 10), [{at = 10.0, w = 2.6, kind = "door", id = "pump", skin = "gate"}], {core = mats.brick_dark, out = true, top = 4.6})
	room_shell(Vector2(46, 4), Vector2(1, 0)); room_shell(Vector2(46, -8), Vector2(1, 0))
	# north end: the army's container blockade (solid), with the checkpoint platform in front of it
	collider(Vector3(20, 6, T), Vector3(36, 3, -16))
	kit.outdoor = true
	var cm := [mats.corr_red, mats.corr_blue, mats.corr_olive]
	for i in 3:
		kit.container(cm[i], mats.trim, Vector3(29.3 + i * 6.7, 0, -17.5))
		if i < 2: kit.container(cm[(i + 1) % 3], mats.trim, Vector3(32.6 + i * 6.9, 2.6, -17.6), 0.03 - i * 0.07)
	collider(Vector3(10, 1.4, 5), Vector3(36, 0.7, -13.5))
	kit.box(mats.conc, Vector3(10, 1.4, 5), Vector3(36, 0.7, -13.5))
	kit.box(mats.kerb, Vector3(10.2, 0.08, 5.2), Vector3(36, 1.42, -13.5))
	for x: float in [29.0, 43.0]:
		var r := box(Vector3(4, 0.3, 3.2), Vector3(x, 0.62, -12.0), mats.conc)
		r.rotation.z = (1.0 if x < 36 else -1.0) * atan2(1.4, 4.0)
	box(Vector3(10, 0.1, 0.1), Vector3(36, 2.4, -11.0), mats.trim)  # guard rail
	# shops along the east side: three buildings of different heights
	kit.block(Rect2(46, -16.5, 8, 9.5), H, 9.0, mats.facade_plaster, mats.conc, mats.kerb)
	kit.block(Rect2(46, -7, 8, 9), H, 12.2, mats.facade_brick, mats.brick, mats.kerb)
	kit.block(Rect2(46, 2, 8, 8.2), H, 8.2, mats.facade_brick, mats.brick_dark, mats.kerb)
	# the street carries on beyond the blockade
	kit.block(Rect2(46, -46, 9, 29.5), 0.0, 10.6, mats.facade_plaster, mats.conc, mats.kerb)
	kit.block(Rect2(17, -46, 9, 10), 0.0, 12.4, mats.facade_brick, mats.brick, mats.kerb)

## Courtyard (area "pump", x 26..46, z 10..30): the abandoned evacuation point.
func _build_court() -> void:
	floor_rect(mats.cobble, 26, 10, 46, 30)
	var bk := {core = mats.brick_dark, out = true}
	wall(Vector2(26, 10.2), Vector2(26, 30), [{at = 1.9, w = 3.4, kind = "open"}], bk)
	wall(Vector2(26, 30), Vector2(46, 30), [{at = 12.0, w = 1.8, kind = "window", id = "w_pump_s", out = Vector2(0, 1)}], bk)
	wall(Vector2(46, 30), Vector2(46, 10), [{at = 10.0, w = 1.8, kind = "window", id = "w_pump_e", out = Vector2(1, 0)}], bk)
	room_shell(Vector2(38, 30), Vector2(0, 1)); room_shell(Vector2(46, 20), Vector2(1, 0))
	kit.outdoor = true
	kit.block(Rect2(46, 10.2, 8, 20), H, 11.6, mats.facade_brick, mats.brick_dark, mats.kerb)
	kit.block(Rect2(24, 30, 30, 8), H, 13.0, mats.facade_plaster, mats.conc, mats.kerb)
	kit.block(Rect2(18, 23.2, 8, 7), 0.0, 11.0, mats.facade_brick, mats.brick, mats.kerb)

func _build_catwalk() -> void:
	# Store mezzanine at 1.8 m along the north wall with a ramp down to the east.
	box(Vector3(8, 0.15, 2.2), Vector3(16, 1.8, -8.5), mats.plate)
	for x: float in [12.5, 19.5]:
		box(Vector3(0.12, 1.8, 0.12), Vector3(x, 0.9, -7.5), mats.metal)
	box(Vector3(8, 0.08, 0.08), Vector3(16, 2.85, -7.42), mats.stripe, false)
	var ramp := box(Vector3(4.4, 0.15, 2.2), Vector3(22, 0.9, -8.5), mats.plate)
	ramp.rotation.z = -atan2(1.8, 4.2)

func in_roofed(x: float, z: float) -> bool:
	for r in ROOFED:
		if r.has_point(Vector2(x, z)): return true
	return false

## Lamps. Each area's main lamp: a powered light (off until the generator runs), a red emergency lamp
## that works on batteries, and a soft bounce fill. Indoors they hang from the ceiling; outdoors from a
## cable strung between the buildings.
func _build_lamps() -> void:
	for p in [Vector3(0, H - 0.3, 0), Vector3(0, H - 0.3, -18), Vector3(18, H - 0.3, 0), Vector3(18, H - 0.3, -18)]:
		var inside := in_roofed(p.x, p.z)
		_fixture(p, 1.4, inside)
		var warm := Color(1.0, 0.82, 0.58) if p.z > -10 and p.x < 10 else Color(1.0, 0.9, 0.75)
		var w := light(p + Vector3(0, -0.4, 0), warm, 2.4, 12.0)
		w.visible = false; room_lights.append(w); shadow_lights.append(w)
		var em := light(p + Vector3(2, -0.5, 2), Color(1.0, 0.15, 0.08), 1.2, 9.0)
		emergency_lights.append(em)
		kit.outdoor = not inside
		kit.box(mats.red_glow, Vector3(0.24, 0.14, 0.24), p + Vector3(2, -0.02, 2), 0.0, Vector2.ZERO, false)
		# soft bounce fill (stand-in for baked GI on mobile): wide, no shadow/specular, brightens with power
		var bf := light(Vector3(p.x, 1.2, p.z), Color(0.55, 0.6, 0.75), BOUNCE_OFF, 13.0, false)
		bf.light_specular = 0.0; bf.omni_attenuation = 0.7; bf.light_bake_mode = Light3D.BAKE_STATIC
		bounce_lights.append(bf)
		if inside: _dust(p + Vector3(0, -1.6, 0), Vector3(6, 1.6, 6))
		_dress(Vector3(p.x, 0.0, p.z), 5.0)
	for q in EXTRA_LAMPS:
		var lp := Vector3(q.x, H - 0.3, q.y)
		_fixture(lp, 1.1, in_roofed(q.x, q.y))
		var xl := light(lp + Vector3(0, -0.4, 0), Color(1.0, 0.86, 0.66), 1.5, 8.0)
		xl.shadow_enabled = false; xl.visible = false; room_lights.append(xl)
	# alarm beacons (off until round 6): a red lamp housing + a pulsing light, no shadows
	for p in [Vector3(-9.5, 3.2, 2), Vector3(-2, 3.2, 9.5), Vector3(9.5, 3.2, -4), Vector3(18, 3.2, 9.5)]:
		var am := _emit(Color(1.0, 0.1, 0.05), 0.2); alarm_mats.append(am)
		box(Vector3(0.3, 0.3, 0.3), p, am, false)
		var al := light(p + Vector3(0, -0.4, 0), Color(1.0, 0.08, 0.04), 0.0, 10.0, false)
		al.visible = false; alarm_lights.append(al)

func _fixture(p: Vector3, w: float, inside: bool) -> void:
	kit.outdoor = not inside
	if inside:
		kit.box(mats.trim, Vector3(w + 0.1, 0.06, 0.5), p + Vector3(0, 0.26, 0))
		kit.box(mats.lamp, Vector3(w, 0.08, 0.4), p + Vector3(0, 0.2, 0), 0.0, Vector2.ZERO, false)
	else:   # enamel shade on a cable strung across the lane
		var x0 := -10.0 if p.x < 10 else 26.0; var x1 := 10.0 if p.x < 10 else 46.0
		kit.cable(mats.dark, Vector3(x0, p.y + 0.9, p.z), Vector3(p.x, p.y + 0.42, p.z), 0.12)
		kit.cable(mats.dark, Vector3(p.x, p.y + 0.42, p.z), Vector3(x1, p.y + 0.9, p.z), 0.12)
		kit.cyl(mats.trim, 0.34, 0.16, p + Vector3(0, 0.32, 0), 10, false, 0.08)
		kit.box(mats.lamp, Vector3(0.2, 0.1, 0.2), p + Vector3(0, 0.2, 0), 0.0, Vector2.ZERO, false)

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

func prop(name: String, size: float, pos: Vector3, rot_y := 0.0, by_height := false, collide := true) -> Node3D:
	var n := ModelLib.prop(name, size, by_height)
	n.position = pos; n.rotation.y = rot_y; add_child(n)
	_lod(n, 38.0 if size > 1.5 else 24.0)
	if collide:
		var a := _bounds(n)
		var sb := StaticBody3D.new(); sb.collision_layer = 1; sb.collision_mask = 0
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = a.size; cs.shape = sh
		cs.position = a.get_center(); sb.add_child(cs); n.add_child(sb)
		# v7.12 fix3: the box is for movement only. Bullets test a mesh-accurate twin on SHOT_LAYER,
		# otherwise hollow props (the gas-tank cage) catch shots in thin air and hang bullet-hole
		# decals + dust in front of the camera (the "dark green blobs").
		sb.add_to_group(PROP_BOX_GROUP)
		var shot := StaticBody3D.new(); shot.collision_layer = SHOT_LAYER; shot.collision_mask = 0
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null: continue
			var tcs := CollisionShape3D.new(); tcs.shape = m.mesh.create_trimesh_shape()
			shot.add_child(tcs); tcs.transform = n.global_transform.affine_inverse() * m.global_transform if n.is_inside_tree() else _rel_xf(n, m)
		n.add_child(shot)
	return n

const PROP_BOX_GROUP := "prop_move_box"
const SHOT_LAYER := 64

static func _rel_xf(root: Node3D, m: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY; var c: Node = m
	while c != root and c is Node3D:
		xf = (c as Node3D).transform * xf; c = c.get_parent()
	return xf

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

## v7.13 graphics: room dressing around each main lamp - rubble chunks, loose planks, papers and a
## dragged blood trail. Floor-flat or tiny, no collision, so navigation and bullets are unaffected.
static var _dress_mats := {}
func _dress(at: Vector3, r: float) -> void:
	if _dress_mats.is_empty():
		var rub := StandardMaterial3D.new(); rub.albedo_color = Color(0.32, 0.3, 0.28); rub.roughness = 1.0
		rub.detail_enabled = true; rub.detail_albedo = Zombie.grime_tex(); rub.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		var wood := StandardMaterial3D.new(); wood.albedo_color = Color(0.36, 0.25, 0.16); wood.roughness = 0.95
		var paper := StandardMaterial3D.new(); paper.albedo_color = Color(0.72, 0.7, 0.62); paper.roughness = 1.0
		var blood := StandardMaterial3D.new(); blood.albedo_color = Color(0.28, 0.02, 0.02, 0.85); blood.roughness = 0.35
		blood.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; blood.albedo_texture = _blood_tex()
		_dress_mats = {rub = rub, wood = wood, paper = paper, blood = blood}
	var rr := RandomNumberGenerator.new(); rr.seed = int(at.x * 13 + at.z * 7 + 5)
	kit.outdoor = not in_roofed(at.x, at.z)
	for i in 7:   # rubble chunks
		var s := rr.randf_range(0.08, 0.22)
		kit.box(_dress_mats.rub, Vector3(s * rr.randf_range(1, 1.8), s * 0.6, s), at + Vector3(rr.randf_range(-r, r), s * 0.3 + 0.03, rr.randf_range(-r, r)), rr.randf() * TAU, Vector2.ZERO, false, Vector3(rr.randf_range(-0.3, 0.3), 0, rr.randf_range(-0.3, 0.3)))
	for i in 2:   # loose planks
		kit.box(_dress_mats.wood, Vector3(1.1, 0.04, 0.14), at + Vector3(rr.randf_range(-r, r), 0.06, rr.randf_range(-r, r)), rr.randf() * TAU, Vector2.ZERO, false)
	for i in 4:   # scattered papers
		kit.box(_dress_mats.paper, Vector3(0.21, 0.004, 0.3), at + Vector3(rr.randf_range(-r, r), 0.036, rr.randf_range(-r, r)), rr.randf() * TAU, Vector2.ZERO, false)
	# drag trail: a line of fading smears
	var p0 := at + Vector3(rr.randf_range(-r, r) * 0.6, 0.04, rr.randf_range(-r, r) * 0.6)
	var dir := Vector3(cos(rr.randf() * TAU), 0, sin(rr.randf() * TAU))
	for k in 6:
		var mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(0.55 - k * 0.05, 0.75)
		mi.mesh = pm; mi.material_override = _dress_mats.blood; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = p0 + dir * k * 0.62 + Vector3(0, k * 0.0004, 0); mi.rotation.y = atan2(dir.x, dir.z) + rr.randf_range(-0.2, 0.2)
		mi.transparency = k * 0.13; add_child(mi)

static func _blood_tex() -> Texture2D:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new(); n.frequency = 0.12; n.seed = 7
	for y in 64:
		for x in 32:
			var u := absf(x - 15.5) / 16.0
			var a := clampf((1.0 - u * u * 1.6) * (0.55 + n.get_noise_2d(x, y) * 0.9), 0, 1)
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.15, 0.5, a)))
	return ImageTexture.create_from_image(img)

## Dust motes hanging in the light (the mobile renderer has no volumetric fog).
func _dust(at: Vector3, extents: Vector3) -> void:
	var p := CPUParticles3D.new(); p.amount = 60; p.lifetime = 8.0; p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = extents
	p.gravity = Vector3(0, -0.01, 0); p.initial_velocity_min = 0.02; p.initial_velocity_max = 0.08
	p.direction = Vector3(1, 0.2, 0); p.spread = 180
	var q := QuadMesh.new(); q.size = Vector2(0.025, 0.025); p.mesh = q
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.95, 0.85, 0.32); q.material = m
	p.position = at; add_child(p); dust.append(p)

func light(pos: Vector3, color: Color, energy: float, rng: float, flicker := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	if flicker: l.set_script(load("res://scripts/game/flicker_light.gd"))
	l.light_color = color; l.light_energy = energy; l.omni_range = rng; l.position = pos
	l.omni_attenuation = 1.2
	add_child(l)
	if pos.y > 2.5 and energy >= 1.0: light_pool(l)
	return l

## v7.6 fake-baked light pool: a soft additive radial glow on the floor under every ceiling lamp, so lit
## areas read like a lightmapped level (bright pool, dark falloff) even on GL Compatibility / phones where
## real GI is unavailable. Child of the light, so it switches on/off (power, emergency) with it.
const POOL_FRACTION := 0.7     ## pool diameter as a fraction of the light's range
const POOL_STRENGTH := 0.9
static var _pool_tex: GradientTexture2D
static func pool_texture() -> GradientTexture2D:
	if _pool_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.7, 0.7, 0.7, 1), Color(0.22, 0.22, 0.22, 1), Color(0, 0, 0, 1)])
		_pool_tex = GradientTexture2D.new(); _pool_tex.gradient = g; _pool_tex.width = 128; _pool_tex.height = 128
		_pool_tex.fill = GradientTexture2D.FILL_RADIAL; _pool_tex.fill_from = Vector2(0.5, 0.5); _pool_tex.fill_to = Vector2(1.0, 0.5)
	return _pool_tex
static func pool_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = pool_texture(); m.albedo_color = Color(c.r, c.g, c.b) * POOL_STRENGTH
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED; m.disable_receive_shadows = true; m.render_priority = -2
	return m
var light_pools: Array = []
func light_pool(l: OmniLight3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = "LightPool"
	var q := PlaneMesh.new(); var d := l.omni_range * POOL_FRACTION; q.size = Vector2(d, d); mi.mesh = q
	mi.material_override = pool_material(l.light_color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, -l.position.y + 0.01, 0)   # on the floor under the lamp
	l.add_child(mi); light_pools.append(mi)
	lamp_cone(l)
	return mi

## v7.14 atmosphere: a faint dusty light cone hanging under every ceiling lamp (one additive Y-billboard
## card, shared material per lamp colour, child of the light so power/emergency toggles it). Hidden with
## the "dust" quality toggle, so low-end phones skip the extra fill-rate.
const CONE_ALPHA := 0.07
static var _cone_mats := {}
func lamp_cone(l: OmniLight3D) -> MeshInstance3D:
	var k := l.light_color.to_html()
	if not _cone_mats.has(k):
		shaft(Vector3.ZERO, 0.01, 0.01, Color.WHITE).queue_free()   # make sure the base material exists
		var m := _shaft_mat.duplicate() as StandardMaterial3D
		m.albedo_color = Color(l.light_color.r, l.light_color.g, l.light_color.b, CONE_ALPHA)
		_cone_mats[k] = m
	var mi := MeshInstance3D.new(); mi.name = "LampCone"
	var h := l.position.y - 0.15
	var qm := QuadMesh.new(); qm.size = Vector2(minf(2.4, l.omni_range * 0.32), h); mi.mesh = qm
	mi.material_override = _cone_mats[k]; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, -h * 0.5 - 0.1, 0)
	l.add_child(mi); dust.append(mi)
	return mi

func apply_quality(d: Dictionary) -> void:
	# GL Compatibility (the fallback on phones without Vulkan) mis-samples omni shadow maps for the
	# viewmodel overlay viewport when a shadowed lamp is right overhead (arms render black), so only
	# the dusk skylight keeps its shadow there.
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	for l in shadow_lights:
		if is_instance_valid(l): l.shadow_enabled = d.shadows and not (compat and l is OmniLight3D)
	for p in dust:
		if p is CPUParticles3D: p.emitting = d.dust
		p.visible = d.dust
	for z in get_tree().get_nodes_in_group("voz_zombie"):
		ModelLib.set_shadows(z.model, d.shadows)

# ---------------------------------------------------------------- machines
## Neon perk machine: cabinet + glowing tube outline + emblem + sign.
func _machine(pos: Vector3, rot_y: float, color: Color, title: String, emblem := "circle") -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; add_child(root)
	box(Vector3(1.2, 2.2, 0.8), Vector3(0, 1.1, 0), _pbr("metalplates006", color.darkened(0.45), 0.9, 0.6), true, 1, root)
	var pnl := _emit(color, 0.3); pnl.albedo_color = color.darkened(0.6); pnl.roughness = 0.9   # dark glass, lit from inside
	var panel := box(Vector3(0.9, 0.9, 0.05), Vector3(0, 1.45, -0.42), pnl, false, 1, root)
	var tube := _emit(color.lightened(0.2), 0.4)
	for e in [[Vector3(1.26, 0.05, 0.05), Vector3(0, 2.22, -0.42)], [Vector3(1.26, 0.05, 0.05), Vector3(0, 0.02, -0.42)],
			[Vector3(0.05, 2.2, 0.05), Vector3(0.62, 1.1, -0.42)], [Vector3(0.05, 2.2, 0.05), Vector3(-0.62, 1.1, -0.42)]]:
		box(e[0], e[1], tube, false, 1, root)
	var em := MeshInstance3D.new()
	# v7.3: emblem gets its own matte, low-emission material; sharing the pulsing tube neon plus the
	# flashlight hotspot made it a white-hot blob at arm's length
	var emm := _emit(color, MACHINE_EMBLEM); emm.roughness = 1.0; emm.metallic_specular = 0.0
	em.material_override = emm
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
	var ml := OmniLight3D.new(); ml.light_color = color; ml.light_energy = 0.0; ml.omni_range = 3.0
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
	# v7.13 Tech Locker: buy a random backpack gadget (no power needed)
	var tl := _machine(Vector3(6.5, 0, 9.1), 0.0, Color(0.35, 0.6, 1.0), "Tech Locker", "bolt")
	game.add_interactable(_front(tl), 2.2,
		func(pl): return game.tech_locker_prompt(pl),
		func(pl): game.use_tech_locker(pl))
	# Power switch: the breaker box bolted to the generator trailer in the Back Alley
	var sw := Node3D.new(); sw.position = Vector3(3, 0, -24.3); add_child(sw)
	box(Vector3(0.8, 1.2, 0.3), Vector3(0, 1.4, 0), mats.metal, true, 1, sw)
	box(Vector3(0.12, 0.8, 0.12), Vector3(0, 0.4, 0), mats.trim, false, 1, sw)
	var lever := box(Vector3(0.1, 0.5, 0.1), Vector3(0, 1.5, 0.25), _emit(Color(1, 0.2, 0.1), 2.0), false, 1, sw)
	lever.rotation.x = 0.6; lever.name = "Lever"
	power_label = label("GENERATOR\nNO POWER", Vector3(3, 2.45, -24.1), 0.0, 44, Color(1, 0.3, 0.2))
	# v10 power objective: hold USE to crank the starter (Facility.POWER_CRANKS pulls)
	game.add_interactable(Vector3(3, 1.0, -23.3), 2.2,
		func(pl): return game.crank_prompt(pl),
		func(pl): game.crank_power(lever), true)
	_power_cues()
	# Mystery Crate: starts in the Lab, relocates between these spots
	crate_spots = [
		[Vector3(16, 0, 6.6), PI, "General Store"],
		[Vector3(32, 0, 8.6), PI, "Main Street"],
		[Vector3(-6.6, 0, -24.6), 0.0, "Back Alley"],
		[Vector3(20, 0, -13.6), 0.0, "Garage"],
		[Vector3(-6, 0, 8.6), PI, "Victory Diner"],
	]
	var crate := CrateNode.new(); crate.game = game; add_child(crate); crate.build()
	game.crate_node = crate
	var marker := label("MYSTERY CRATE\n%d  ·  random weapon" % game.crate.cost, Vector3(0, 2.3, 0), 0.0, 40, Color(0.5, 0.9, 1.0))
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
	_wall_buy(order[2], Vector3(12.6, 1.6, 9.75), PI)
	# Armor racks
	_armor_rack("light", Vector3(-4, 0, -9.6), 0.0)
	_armor_rack("medium", Vector3(25.6, 0, -4), -PI / 2)
	_armor_rack("heavy", Vector3(13.6, 0, -25.6), 0.0)
	_annex_stations()

## v10 environmental cues for the power objective: a heavy cable runs from the diner's back door to
## the generator with amber marker lamps along it, a beacon strobes over the breaker, and a sign over
## the diner's north door names the job. All of it turns green once the generator runs.
var power_label: Label3D
var power_beacon_light: OmniLight3D
var power_cue_mat: StandardMaterial3D
var power_signs: Array = []
const POWER_CUE_OFF := Color(1.0, 0.6, 0.1)
const POWER_CUE_ON := Color(0.3, 1.0, 0.45)
func _power_cues() -> void:
	power_cue_mat = _emit(POWER_CUE_OFF, 2.2)
	var cable := _mat(Color(0.03, 0.03, 0.035), 0.7)
	# cable: diner back door (0,-10) -> along the alley -> breaker (3,-24.3); two straight runs
	var pts := [Vector3(1.6, 0.04, -10.6), Vector3(1.6, 0.04, -22.6), Vector3(3.0, 0.04, -22.6), Vector3(3.0, 0.04, -24.0)]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]; var b: Vector3 = pts[i + 1]
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var len := a.distance_to(b) + 0.1
		box(Vector3(len, 0.08, 0.1) if along_x else Vector3(0.1, 0.08, len), (a + b) / 2.0, cable, false)
	for z: float in [-12.0, -15.0, -18.0, -21.0]:
		box(Vector3(0.16, 0.1, 0.16), Vector3(1.6, 0.1, z), power_cue_mat, false)
	# strobing beacon on a post above the breaker
	box(Vector3(0.22, 0.22, 0.22), Vector3(3, 3.0, -24.3), power_cue_mat, false)
	power_beacon_light = OmniLight3D.new(); power_beacon_light.light_color = POWER_CUE_OFF; power_beacon_light.light_energy = 2.0
	power_beacon_light.omni_range = 7.0; power_beacon_light.position = Vector3(3, 2.9, -23.8); add_child(power_beacon_light)
	# signs: inside the diner over the back door, and on the alley side
	for s in [[Vector3(0, 3.25, -9.72), 0.0], [Vector3(0, 3.25, -10.28), PI]]:
		var l := label("NO POWER\nGENERATOR ▸ BACK ALLEY", s[0], s[1], 60, POWER_CUE_OFF)
		power_signs.append(l)

## Called once the generator runs: cues go green and stop strobing.
func power_beacon(on: bool) -> void:
	var c := POWER_CUE_ON if on else POWER_CUE_OFF
	if power_cue_mat: power_cue_mat.albedo_color = c; power_cue_mat.emission = c
	if power_beacon_light: power_beacon_light.light_color = c
	if power_label: power_label.text = "GENERATOR\nRUNNING" if on else "GENERATOR\nNO POWER"; power_label.modulate = c
	for l in power_signs:
		(l as Label3D).text = "POWER ON\nFORGE ▸ HOLLIS AUTO REPAIR" if on else "NO POWER\nGENERATOR ▸ BACK ALLEY"; (l as Label3D).modulate = c

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
	if power_beacon_light:   # strobe until the generator runs, then a steady glow
		power_beacon_light.light_energy = 1.2 if on else 2.6 * pow(0.5 + 0.5 * sin(_t * 6.0), 3.0)
		if power_cue_mat: power_cue_mat.emission_energy_multiplier = 1.6 if on else 0.6 + 2.6 * pow(0.5 + 0.5 * sin(_t * 6.0), 3.0)
	var alarm: bool = game != null and game.round >= ALARM_ROUND and not game.over
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	for i in alarm_lights.size():
		var al: OmniLight3D = alarm_lights[i]
		al.visible = alarm
		if alarm:
			var k := pow(0.5 + 0.5 * sin(_t * 5.0 + i * 1.3), 3.0)
			al.light_energy = 2.6 * k; alarm_mats[i].emission_energy_multiplier = 0.5 + 5.0 * k
	for i in fires.size():
		(fires[i] as StandardMaterial3D).albedo_color.a = 0.4 + 0.14 * sin(_t * 2.3 + i * 2.1) + 0.06 * sin(_t * 7.1 + i)
	for n in neon:
		var m: StandardMaterial3D = n[0]
		var base: float = MACHINE_NEON_ON if on else 0.4
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

## ---- v7.12 Sealed Annex: a vault room behind a cracked panel in the generator room's north wall ----
var crack_body: StaticBody3D
var hint_light: OmniLight3D
var reaper_display: Node3D

func _build_annex() -> void:
	var a := HiddenRoom.ROOM_MIN; var b := HiddenRoom.ROOM_MAX
	wall(Vector2(a.x, b.y), Vector2(a.x, a.y)); wall(Vector2(a.x, a.y), Vector2(b.x, a.y)); wall(Vector2(b.x, a.y), Vector2(b.x, b.y))
	var c := Vector3((a.x + b.x) / 2.0, 0, (a.y + b.y) / 2.0); var sz := Vector3(b.x - a.x, 0, b.y - a.y)
	box(Vector3(sz.x + T, 0.3, sz.z + T), Vector3(c.x, H + 0.15, c.z), mats.wall_brick)          # roof
	box(Vector3(sz.x, 0.04, sz.z), Vector3(c.x, 0.02, c.z), _mat(Color(0.12, 0.14, 0.13), 0.6, 0.3), false)
	# the cracked panel: plaster on the room side we see, shootable/knifeable (meta "crack")
	var cp := HiddenRoom.CRACK_POS
	crack_body = box(Vector3(HiddenRoom.CRACK_W, H, T), Vector3(cp.x, H / 2.0, cp.z), mats.wall) as StaticBody3D
	crack_body.set_meta("crack", true)
	var dark := _mat(Color(0.05, 0.05, 0.05))
	for k in [[Vector3(0.0, 0.2, 0), 0.5, 1.4], [Vector3(-0.35, -0.5, 0), -0.7, 1.0], [Vector3(0.4, -0.3, 0), 1.1, 0.8], [Vector3(0.1, 0.9, 0), -0.3, 0.9]]:
		var crk := box(Vector3(0.04, k[2], 0.02), Vector3(0, 0, T / 2.0 + 0.01) + k[0], dark, false, 1, crack_body)
		crk.rotation.z = k[1]
	# hint: a scratched symbol and a light that keeps sputtering green
	var sym := Label3D.new(); sym.text = "\\ | //\n-- o --\n// | \\\\"; sym.font_size = 40; sym.pixel_size = 0.004
	sym.modulate = Color(0.55, 0.75, 0.6, 0.55); sym.shaded = false; sym.double_sided = false
	sym.position = Vector3(0, -0.8, T / 2.0 + 0.03); crack_body.add_child(sym)
	hint_light = OmniLight3D.new(); hint_light.light_color = Color(0.4, 1.0, 0.6); hint_light.light_energy = 1.4
	hint_light.omni_range = 3.5; hint_light.position = Vector3(cp.x, 3.2, cp.z + 0.8); add_child(hint_light)
	var tw := create_tween().set_loops()
	for e: float in [1.4, 0.1, 1.2, 0.0, 0.0, 1.5, 0.2, 1.3]:
		tw.tween_property(hint_light, "light_energy", e, 0.06); tw.tween_interval(randf_range(0.05, 0.5))
	# room light (off until revealed so nothing leaks)
	var rl := OmniLight3D.new(); rl.name = "AnnexLight"; rl.light_color = Color(0.45, 1.0, 0.65); rl.light_energy = 0.0
	rl.omni_range = 9.0; rl.position = Vector3(c.x, H - 0.5, c.z); add_child(rl)

## Breaks the panel open. Returns the dust points for the fx.
func reveal_annex() -> void:
	if crack_body: crack_body.queue_free(); crack_body = null
	if hint_light: hint_light.queue_free(); hint_light = null
	var rl := get_node_or_null("AnnexLight") as OmniLight3D
	if rl: create_tween().tween_property(rl, "light_energy", 1.6, 1.2)
	call_deferred("rebake")

func _annex_stations() -> void:
	# armor: Vault Plating (3 tiers)
	var v := Node3D.new(); v.position = HiddenRoom.VAULT_POS; v.rotation.y = PI / 2; add_child(v)
	box(Vector3(1.4, 2.0, 0.4), Vector3(0, 1.0, 0), mats.plate, true, 1, v)
	box(Vector3(0.9, 1.0, 0.15), Vector3(0, 1.2, 0.25), _emit(Color(0.3, 0.6, 1.0), 1.2), false, 1, v)
	var vl := Label3D.new(); vl.text = "VAULT PLATING"; vl.font_size = 28; vl.pixel_size = 0.0035; vl.shaded = false; vl.outline_size = 8
	vl.position = Vector3(0, 1.85, 0.26); v.add_child(vl)
	game.add_interactable(v.to_global(Vector3(0, 1.0, 1.0)), 2.0, func(pl): return game.vault_prompt(pl), func(pl): game.use_vault(pl))
	# gun: Rift Bench (cheap first overcharge, no power needed)
	var r := Node3D.new(); r.position = HiddenRoom.RIFT_POS; r.rotation.y = -PI / 2; add_child(r)
	box(Vector3(1.8, 0.9, 0.8), Vector3(0, 0.45, 0), mats.metal, true, 1, r)
	box(Vector3(1.2, 0.06, 0.5), Vector3(0, 0.93, 0), _emit(Color(0.6, 0.3, 0.9), 0.7), false, 1, r)
	var rlab := Label3D.new(); rlab.text = "RIFT BENCH"; rlab.font_size = 34; rlab.pixel_size = 0.004; rlab.shaded = false
	rlab.position = Vector3(0, 1.6, 0); r.add_child(rlab)
	game.add_interactable(r.to_global(Vector3(0, 0.9, 1.0)), 2.0, func(pl): return game.rift_prompt(pl), func(pl): game.use_rift(pl))
	# alien LMG pedestal
	var pd := Node3D.new(); pd.position = HiddenRoom.PEDESTAL_POS; add_child(pd)
	var cyl := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.6; cm.bottom_radius = 0.75; cm.height = 1.0
	cyl.mesh = cm; cyl.material_override = Viewmodel.alien_material(); cyl.position.y = 0.5; pd.add_child(cyl)
	var col := box(Vector3(1.2, 1.0, 1.2), Vector3(0, 0.5, 0), mats.metal, true, 1, pd); (col.get_child(1) as MeshInstance3D).visible = false
	reaper_display = ModelLib.gun("lmg"); Viewmodel.alienize(reaper_display)
	reaper_display.scale = Vector3.ONE * 1.8; reaper_display.position = Vector3(0, 1.55, 0); pd.add_child(reaper_display)
	var spin := create_tween().set_loops(); spin.tween_property(reaper_display, "rotation:y", TAU, 6.0).from(0.0)
	var gl := OmniLight3D.new(); gl.light_color = Color(0.3, 1.0, 0.55); gl.light_energy = 1.2; gl.omni_range = 3.0; gl.position.y = 1.6; pd.add_child(gl)
	var pl3 := Label3D.new(); pl3.text = "HIVE REAPER\n%d" % Weapons.ALIEN_PRICE; pl3.font_size = 28; pl3.pixel_size = 0.0035; pl3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pl3.shaded = false; pl3.modulate = Color(0.5, 1.0, 0.7); pl3.position = Vector3(0, 2.15, 0); pd.add_child(pl3)
	game.add_interactable(pd.to_global(Vector3(0, 1.0, 1.4)), 2.0, func(pl): return game.reaper_prompt(pl), func(pl): game.buy_reaper(pl))

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

## v7.9 power-on drama: lights come on in a wave out from the lever, each one sputtering
## (on-off-on) before it holds. Delay grows with distance and is capped so the wave stays short.
const CASCADE_PER_M := 0.07
const CASCADE_MAX := 2.4
const SPUTTER := [0.0, 0.08, 0.16, 0.3]   ## on, off, on, (hold) offsets in seconds
static func cascade_delay(dist: float) -> float: return minf(maxf(dist, 0.0) * CASCADE_PER_M, CASCADE_MAX)

## Turns power on, then re-darkens room lights and machine glows and brings them back in a wave.
## Returns the total duration of the wave.
func power_cascade(origin: Vector3) -> float:
	set_power(true)
	var last := 0.0
	for l in room_lights:
		var d: float = cascade_delay(origin.distance_to(l.global_position if l.is_inside_tree() else l.position))
		l.visible = false; last = maxf(last, d + SPUTTER[3])
		var tw: Tween = l.create_tween()
		tw.tween_interval(d); tw.tween_callback(func(): l.visible = true)
		tw.tween_interval(SPUTTER[1]); tw.tween_callback(func(): l.visible = false)
		tw.tween_interval(SPUTTER[2] - SPUTTER[1]); tw.tween_callback(func(): l.visible = true)
	for pair in machine_lights:
		var ml: Light3D = pair[0]
		var d: float = cascade_delay(origin.distance_to(ml.global_position if ml.is_inside_tree() else ml.position)) + 0.15
		ml.light_energy = 0.0; last = maxf(last, d + 0.5)
		var tw: Tween = ml.create_tween()
		tw.tween_interval(d); tw.tween_property(ml, "light_energy", MACHINE_LIGHT_ON * 1.6, 0.12)
		tw.tween_property(ml, "light_energy", MACHINE_LIGHT_ON, 0.4)
	return last

func set_power(on: bool) -> void:
	if mats.has("signs_lit"): (mats.signs_lit as StandardMaterial3D).emission_energy_multiplier = SIGN_NEON_ON if on else SIGN_NEON_OFF
	if mats.has("lamp"): (mats.lamp as StandardMaterial3D).emission_energy_multiplier = 2.0 if on else LAMP_OFF
	for l in room_lights: l.visible = on
	for l in emergency_lights: l.base = 0.3 if on else 1.2
	for l in bounce_lights: l.light_energy = BOUNCE_ON if on else BOUNCE_OFF
	for l in bounce_lights: l.light_color = Color(1.0, 0.9, 0.76) if on else Color(0.55, 0.6, 0.75)
	for pair in machine_lights:
		pair[0].light_energy = MACHINE_LIGHT_ON if on else 0.0
		pair[1].emission_energy_multiplier = MACHINE_PANEL_ON if on else 0.3
