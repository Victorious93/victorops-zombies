class_name SentryModel
## v7.14 Sentry Pod model: bigger and readable at a glance in the dark — tripod legs, chunky armoured
## head with twin barrels, a glowing eye, a status bar (green → amber → red as life/ammo run out),
## a blinking top beacon and a faint ground ring showing it's yours. All primitives; shared materials.

const SCALE := 1.55            ## vs the v7.13 pod (≈0.85 m) → ≈1.3 m tall
const HEAD_Y := 0.82 * SCALE
const BAR_W := 0.42 * SCALE
static var _mats := {}

static func mat(key: String) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		match key:
			"body": m.albedo_color = Color(0.3, 0.33, 0.36); m.metallic = 0.6; m.roughness = 0.45
			"plate": m.albedo_color = Color(0.56, 0.5, 0.2); m.metallic = 0.3; m.roughness = 0.55   # olive-amber armour plates
			"dark": m.albedo_color = Color(0.08, 0.08, 0.09); m.metallic = 0.8; m.roughness = 0.3
			"eye": m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = Color(1.0, 0.55, 0.15) * 2.0
			"beacon": m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = Color(0.3, 1.0, 0.5) * 2.0
			"ring":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.albedo_color = Color(0.25, 0.8, 0.45, 0.35)
		_mats[key] = m
	return _mats[key]

## Status colour from the remaining fraction (min of life and ammo).
static func status_color(frac: float) -> Color:
	if frac > 0.5: return Color(0.3, 1.0, 0.45)
	if frac > 0.2: return Color(1.0, 0.75, 0.2)
	return Color(1.0, 0.2, 0.1)

static func remaining(st: Backpack.Sentry) -> float:
	return clampf(minf(st.life / Backpack.SENTRY_LIFE, float(st.ammo) / Backpack.SENTRY_AMMO), 0.0, 1.0)

static func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	mi.position = pos; mi.material_override = m; p.add_child(mi); return mi
static func _cyl(p: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, segs := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h
	cm.radial_segments = segs; cm.rings = 1; mi.mesh = cm; mi.position = pos; mi.material_override = m; p.add_child(mi); return mi

## Builds the pod. Returns {root, head, bar, bar_mat, beacon, ring, light}.
static func build() -> Dictionary:
	var S := SCALE
	var root := Node3D.new(); root.name = "SentryPod"
	# tripod
	for i in 3:
		var a := TAU * i / 3.0
		var leg := _cyl(root, 0.025 * S, 0.04 * S, 0.62 * S, Vector3(cos(a) * 0.17 * S, 0.27 * S, sin(a) * 0.17 * S), mat("dark"), 6)
		leg.rotation = Vector3(sin(a) * -0.45, 0, cos(a) * 0.45)
		_box(root, Vector3(0.09, 0.03, 0.14) * S, Vector3(cos(a) * 0.3 * S, 0.015 * S, sin(a) * 0.3 * S), mat("dark")).rotation.y = -a
	_cyl(root, 0.08 * S, 0.12 * S, 0.22 * S, Vector3(0, 0.6 * S, 0), mat("body"))
	# head
	var head := Node3D.new(); head.name = "Head"; head.position.y = HEAD_Y; root.add_child(head)
	_box(head, Vector3(0.42, 0.28, 0.52) * S, Vector3.ZERO, mat("body"))
	_box(head, Vector3(0.46, 0.1, 0.4) * S, Vector3(0, 0.17 * S, 0.02 * S), mat("plate"))
	_box(head, Vector3(0.05, 0.24, 0.42) * S, Vector3(0.235 * S, 0, 0), mat("plate"))
	_box(head, Vector3(0.05, 0.24, 0.42) * S, Vector3(-0.235 * S, 0, 0), mat("plate"))
	for sx in [-0.08, 0.08]:
		var b := _cyl(head, 0.03 * S, 0.035 * S, 0.42 * S, Vector3(sx * S, -0.03 * S, -0.44 * S), mat("dark"), 8)
		b.rotation.x = PI / 2
		_cyl(head, 0.045 * S, 0.045 * S, 0.06 * S, Vector3(sx * S, -0.03 * S, -0.64 * S), mat("dark"), 8).rotation.x = PI / 2
	var eye := MeshInstance3D.new(); var em := SphereMesh.new(); em.radius = 0.055 * S; em.height = 0.11 * S; em.radial_segments = 8; em.rings = 4
	eye.mesh = em; eye.material_override = mat("eye"); eye.position = Vector3(0, 0.06 * S, -0.27 * S); head.add_child(eye)
	# status bar on the back of the head (faces the player who dropped it)
	_box(head, Vector3(BAR_W + 0.04, 0.07, 0.02) * Vector3(1, S, S), Vector3(0, 0.02 * S, 0.27 * S), mat("dark"))
	var bar_mat := StandardMaterial3D.new(); bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; bar_mat.albedo_color = status_color(1.0)
	var bar := _box(head, Vector3(BAR_W, 0.045 * S, 0.02 * S), Vector3(0, 0.02 * S, 0.285 * S), bar_mat)
	# beacon
	var beacon := _cyl(head, 0.03 * S, 0.04 * S, 0.06 * S, Vector3(0, 0.25 * S, 0.12 * S), mat("beacon"), 8)
	# ground ring
	var ring := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.5 * S; tm.outer_radius = 0.56 * S; tm.rings = 24; tm.ring_segments = 4
	ring.mesh = tm; ring.material_override = mat("ring"); ring.position.y = 0.02; ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.65, 0.3); l.light_energy = 0.9; l.omni_range = 3.2; l.position.y = HEAD_Y + 0.3
	l.shadow_enabled = false; root.add_child(l)
	return {root = root, head = head, bar = bar, bar_mat = bar_mat, beacon = beacon, ring = ring, light = l}

## Per-frame visuals: bar length/colour, beacon blink (faster when nearly spent).
static func update_visuals(parts: Dictionary, st: Backpack.Sentry, t: float) -> void:
	var f := remaining(st)
	var bar: MeshInstance3D = parts.bar
	bar.scale.x = maxf(0.02, f); bar.position.x = -BAR_W * (1.0 - f) * 0.5
	(parts.bar_mat as StandardMaterial3D).albedo_color = status_color(f)
	var hz := 1.0 if f > 0.2 else 4.0
	(parts.beacon as Node3D).visible = fmod(t * hz, 1.0) < 0.5
