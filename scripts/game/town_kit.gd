class_name TownKit
extends RefCounted
## Victorious Framework town kit: batches the static architecture of the abandoned town into a few
## meshes per (material, 10 m cell) so a whole street of cornices, sills, kerbs and furniture costs a
## handful of draw calls, and every mesh stays under the mobile renderer's 8-lights-per-object limit.
## Collision is separate (FacilityMap.collider / FacilityMap.box) so visuals never change navigation.

const CELL := 10.0
## Roofed interiors render on this layer only, so the dusk skylight (which skips it) never leaks indoors
## when shadows are switched off on low-end phones.
const INDOOR_LAYER := 4
## Box faces: [normal, u axis, v axis] with u x v = normal (v is "up" on the four sides).
const FACES := [
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]]
## Signs atlas (assets/town/signs.png, drawn by tools/gen_town_art.py): banners are 2 columns x 6 rows
## of 512x128 px, posters four 256x256 px cells along the bottom.
const BANNERS := ["diner", "open", "garage", "store", "quarantine", "evac", "pharmacy", "hotel", "barber", "closed", "mainst", "curfew"]
const POSTERS := ["evac_notice", "missing", "infection", "special"]

var map: Node3D
var outdoor := false          ## boxes added while true are also lit by the dusk skylight (render layer 2)
var _st := {}                 ## key -> SurfaceTool
var _info := {}               ## key -> [material, outdoor, shadow]
var mesh_count := 0

func _init(m: Node3D) -> void:
	map = m

func _tool(mat: Material, at: Vector3, shadow: bool) -> SurfaceTool:
	var key := "%d|%d|%d|%d|%d" % [mat.get_instance_id(), floori(at.x / CELL), floori(at.z / CELL), int(outdoor), int(shadow)]
	if not _st.has(key):
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st; _info[key] = [mat, outdoor, shadow]
	return _st[key]

## Axis-aligned (optionally yawed) box. uv_m > 0 writes metre-based UVs (u along the face, v down from
## the top) divided by uv_m, for materials that are not triplanar (facades, corrugated sheet).
func box(mat: Material, size: Vector3, pos: Vector3, yaw := 0.0, uv_m := Vector2.ZERO, shadow := true, tilt := Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)), pos)
	box_xf(mat, size, xf, uv_m, shadow)

func box_xf(mat: Material, size: Vector3, xf: Transform3D, uv_m := Vector2.ZERO, shadow := true) -> void:
	var st := _tool(mat, xf.origin, shadow)
	var h := size * 0.5
	for f in FACES:
		var n: Vector3 = f[0]; var u: Vector3 = f[1]; var v: Vector3 = f[2]
		var hu := absf(u.dot(h)); var hv := absf(v.dot(h))
		var c := n * absf(n.dot(h))
		var pts := [c - u * hu - v * hv, c + u * hu + v * hv, c + u * hu - v * hv, c - u * hu - v * hv, c - u * hu + v * hv, c + u * hu + v * hv]
		var uvs := [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
		var wn := (xf.basis * n).normalized()
		for i in 6:
			st.set_normal(wn)
			if uv_m != Vector2.ZERO: st.set_uv(Vector2(uvs[i].x * hu * 2.0 / uv_m.x, uvs[i].y * hv * 2.0 / uv_m.y))
			else: st.set_uv(uvs[i])
			st.add_vertex(xf * pts[i])

## Single quad facing +Z of xf (signs, posters, glass). uv = atlas rect in 0..1.
func quad(mat: Material, w: float, h: float, xf: Transform3D, uv := Rect2(0, 0, 1, 1), shadow := false) -> void:
	var st := _tool(mat, xf.origin, shadow)
	var a := Vector3(-w / 2, -h / 2, 0); var b := Vector3(w / 2, -h / 2, 0); var c := Vector3(w / 2, h / 2, 0); var d := Vector3(-w / 2, h / 2, 0)
	var ua := Vector2(uv.position.x, uv.end.y); var ub := uv.end; var uc := Vector2(uv.end.x, uv.position.y); var ud := uv.position
	var n := xf.basis.z.normalized()
	for pr in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		st.set_normal(n); st.set_uv(pr[1]); st.add_vertex(xf * pr[0])

## Upright (or tilted) cylinder with a top cap: posts, stools, drums, fountain rims.
func cyl(mat: Material, r: float, h: float, pos: Vector3, segs := 10, shadow := true, r_top := -1.0, tilt := Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(tilt), pos)
	var st := _tool(mat, pos, shadow)
	var rt := r if r_top < 0.0 else r_top
	for i in segs:
		var a0 := TAU * i / segs; var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0)); var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := d0 * r - Vector3(0, h / 2, 0); var b1 := d1 * r - Vector3(0, h / 2, 0)
		var t0 := d0 * rt + Vector3(0, h / 2, 0); var t1 := d1 * rt + Vector3(0, h / 2, 0)
		var u0 := float(i) / segs; var u1 := float(i + 1) / segs
		for pr in [[b0, d0, Vector2(u0, 1)], [t1, d1, Vector2(u1, 0)], [t0, d0, Vector2(u0, 0)], [b0, d0, Vector2(u0, 1)], [b1, d1, Vector2(u1, 1)], [t1, d1, Vector2(u1, 0)]]:
			st.set_normal((xf.basis * pr[1]).normalized()); st.set_uv(pr[2]); st.add_vertex(xf * pr[0])
		var top := Vector3(0, h / 2, 0)
		for pr in [top, t0, t1]:
			st.set_normal((xf.basis * Vector3.UP).normalized()); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(xf * pr)

## Builds one MeshInstance3D per batch. Call once after all geometry has been added.
func commit() -> void:
	for key in _st:
		var st: SurfaceTool = _st[key]; var inf: Array = _info[key]
		var mesh := st.commit()
		mesh.surface_set_material(0, inf[0])
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.name = "Town_%d" % mesh_count
		mi.layers = 1 if inf[1] else INDOOR_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if inf[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map.add_child(mi); mesh_count += 1
	_st.clear(); _info.clear()

# ---------------------------------------------------------------- signs
static func banner_uv(id: String) -> Rect2:
	var i := BANNERS.find(id)
	return Rect2((i % 2) * 0.5, (i / 2) * 0.125, 0.5, 0.125)

static func poster_uv(id: String) -> Rect2:
	return Rect2(POSTERS.find(id) * 0.25, 0.75, 0.25, 0.25)

## Wall sign: backing board + printed face. `face` is the direction the sign faces (unit, horizontal).
func banner(id: String, pos: Vector3, face: Vector3, w: float, mats: Dictionary, lit := false) -> void:
	var h := w * 0.25
	var yaw := atan2(face.x, face.z)
	box(mats.sign_back, Vector3(w + 0.12, h + 0.12, 0.08), pos - face * 0.05, yaw)
	quad(mats.signs_lit if lit else mats.signs, w, h, Transform3D(Basis(Vector3.UP, yaw), pos), banner_uv(id))

func poster(id: String, pos: Vector3, face: Vector3, s: float, mats: Dictionary, roll := 0.0) -> void:
	var b := Basis(Vector3.UP, atan2(face.x, face.z)) * Basis(Vector3(0, 0, 1), roll)
	quad(mats.signs, s, s, Transform3D(b, pos + face * 0.012), poster_uv(id))

# ---------------------------------------------------------------- architecture pieces
## Upper storeys + cornice + parapet of a building whose footprint is `r` (x,z rect), rising from y0 to
## y1. `fronts` lists the outward directions that get the windowed facade material (the others get
## `side`). Visual only: the playable ground-floor walls come from FacilityMap.wall().
func block(r: Rect2, y0: float, y1: float, facade: Material, side: Material, trim: Material, tile := Vector2(8.0, 7.0)) -> void:
	var c := Vector3(r.position.x + r.size.x / 2.0, (y0 + y1) / 2.0, r.position.y + r.size.y / 2.0)
	box(facade, Vector3(r.size.x, y1 - y0, r.size.y), c, 0.0, tile)
	box(trim, Vector3(r.size.x + 0.5, 0.35, r.size.y + 0.5), Vector3(c.x, y1 + 0.1, c.z))                 # cornice
	box(side, Vector3(r.size.x + 0.1, 0.7, r.size.y + 0.1), Vector3(c.x, y1 + 0.6, c.z))                  # parapet
	box(trim, Vector3(r.size.x + 0.3, 0.22, r.size.y + 0.3), Vector3(c.x, y0 + 0.05, c.z))                # string course

## Fabric awning sloping out from a wall. `face` = outward direction.
func awning(mat: Material, frame: Material, pos: Vector3, face: Vector3, w: float, depth := 1.3, sag := 0.0) -> void:
	var yaw := atan2(face.x, face.z)
	var b := Basis(Vector3.UP, yaw)
	box_xf(mat, Vector3(w, 0.05, depth * 1.08), Transform3D(b * Basis(Vector3.RIGHT, 0.42 + sag), pos + face * depth * 0.5 - Vector3(0, 0.28, 0)))
	box_xf(mat, Vector3(w, 0.28, 0.04), Transform3D(b, pos + face * depth - Vector3(0, 0.66, 0)))        # valance
	for sx: float in [-1.0, 1.0]:
		box_xf(frame, Vector3(0.04, 0.04, depth), Transform3D(b, pos + b * Vector3(sx * w * 0.5, -0.6, depth * 0.5)))

## Recessed shop doorway painted onto a wall face: dark reveal, door leaf, transom and step.
func doorway(mats: Dictionary, pos: Vector3, face: Vector3, w := 1.1, boarded := false) -> void:
	var yaw := atan2(face.x, face.z); var b := Basis(Vector3.UP, yaw)
	box_xf(mats.dark, Vector3(w + 0.5, 2.5, 0.06), Transform3D(b, pos + Vector3(0, 1.25, 0) + face * 0.02))
	box_xf(mats.door_wood, Vector3(w, 2.1, 0.07), Transform3D(b, pos + Vector3(0, 1.05, 0) + face * 0.05))
	box_xf(mats.trim, Vector3(w + 0.6, 0.14, 0.16), Transform3D(b, pos + Vector3(0, 2.56, 0) + face * 0.06))
	for sx: float in [-1.0, 1.0]:
		box_xf(mats.trim, Vector3(0.12, 2.5, 0.14), Transform3D(b, pos + b * Vector3(sx * (w * 0.5 + 0.25), 1.25, 0.06)))
	box_xf(mats.kerb, Vector3(w + 0.7, 0.14, 0.5), Transform3D(b, pos + Vector3(0, 0.07, 0) + face * 0.25))
	if boarded:
		for k in 3:
			box_xf(mats.plank, Vector3(w + 0.5, 0.16, 0.04), Transform3D(b * Basis(Vector3(0, 0, 1), [0.12, -0.2, 0.06][k]), pos + Vector3(0, 0.7 + k * 0.62, 0) + face * 0.11))

## Boarded display window dressed onto a solid wall face (no hole): frame, dark pane, plywood sheets.
func display_window(mats: Dictionary, pos: Vector3, face: Vector3, w: float, h := 1.7, boards := 3) -> void:
	var yaw := atan2(face.x, face.z); var b := Basis(Vector3.UP, yaw)
	box_xf(mats.trim, Vector3(w + 0.24, h + 0.24, 0.06), Transform3D(b, pos + face * 0.02))
	box_xf(mats.pane, Vector3(w, h, 0.07), Transform3D(b, pos + face * 0.03))
	box_xf(mats.kerb, Vector3(w + 0.4, 0.1, 0.22), Transform3D(b, pos + Vector3(0, -h * 0.5 - 0.1, 0) + face * 0.1))
	for k in boards:
		var t := (k + 0.5) / boards
		box_xf(mats.plank, Vector3(w * 0.36, h * 1.02, 0.03), Transform3D(b * Basis(Vector3(0, 0, 1), [0.03, -0.05, 0.02, -0.02][k % 4]), pos + b * Vector3((t - 0.5) * w, 0, 0.08)))

## Wall-mounted bulkhead lamp housing (the light itself is added by the map). Returns the bulb position.
func wall_lamp(mats: Dictionary, pos: Vector3, face: Vector3, glow: Material) -> Vector3:
	var b := Basis(Vector3.UP, atan2(face.x, face.z))
	box_xf(mats.trim, Vector3(0.1, 0.1, 0.34), Transform3D(b, pos + face * 0.17))
	box_xf(mats.trim, Vector3(0.34, 0.08, 0.3), Transform3D(b, pos + face * 0.36 + Vector3(0, 0.05, 0)))
	box_xf(glow, Vector3(0.22, 0.1, 0.2), Transform3D(b, pos + face * 0.36 - Vector3(0, 0.04, 0)), Vector2.ZERO, false)
	return pos + face * 0.4 - Vector3(0, 0.2, 0)

## Sagging cable between two points (3 straight segments), e.g. power lines and lamp strings.
func cable(mat: Material, a: Vector3, b: Vector3, sag := 0.35, thick := 0.03) -> void:
	var prev := a
	for i in range(1, 5):
		var t := i / 4.0
		var p := a.lerp(b, t) - Vector3(0, sag * sin(t * PI), 0)
		var d := p - prev
		var z := d.normalized(); var x := Vector3.UP.cross(z).normalized(); var y := z.cross(x)
		box_xf(mat, Vector3(thick, thick, d.length() + 0.02), Transform3D(Basis(x, y, z), (p + prev) * 0.5), Vector2.ZERO, false)
		prev = p

# ---------------------------------------------------------------- furniture
## Diner booth: two vinyl benches facing a table. `along` = the wall direction the unit runs along (unit),
## `out` = direction away from the wall. Unit is 1.9 m long, 1.35 m deep.
func booth(mats: Dictionary, wall_pos: Vector3, along: Vector3, out: Vector3) -> void:
	var b := Basis(out, Vector3.UP, along)   # local x = out, z = along
	for s: float in [-1.0, 1.0]:
		var o := wall_pos + along * s * 0.68 + out * 0.68
		box_xf(mats.vinyl, Vector3(1.25, 0.16, 0.5), Transform3D(b, o + Vector3(0, 0.44, 0)))
		box_xf(mats.vinyl, Vector3(1.25, 0.62, 0.12), Transform3D(b, o + along * s * 0.25 + Vector3(0, 0.82, 0)))
		box_xf(mats.dark, Vector3(1.25, 0.36, 0.46), Transform3D(b, o + Vector3(0, 0.18, 0)))
	box_xf(mats.formica, Vector3(1.2, 0.05, 0.72), Transform3D(b, wall_pos + out * 0.68 + Vector3(0, 0.76, 0)))
	box_xf(mats.chrome, Vector3(1.22, 0.03, 0.74), Transform3D(b, wall_pos + out * 0.68 + Vector3(0, 0.73, 0)))
	cyl(mats.chrome, 0.06, 0.72, wall_pos + out * 0.68 + Vector3(0, 0.36, 0), 8)

## Free-standing table; `fallen` tips it on its side.
func table(mats: Dictionary, pos: Vector3, yaw := 0.0, fallen := false) -> void:
	if fallen:
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), PI / 2 - 0.08)
		box_xf(mats.formica, Vector3(1.1, 0.05, 0.75), Transform3D(b, pos + Vector3(0, 0.56, 0)))
		cyl(mats.chrome, 0.05, 0.7, pos + Basis(Vector3.UP, yaw) * Vector3(0.36, 0.56, 0), 8, true, -1.0, Vector3(0, 0, PI / 2 - 0.08))
		cyl(mats.chrome, 0.26, 0.03, pos + Basis(Vector3.UP, yaw) * Vector3(0.72, 0.56, 0), 10, true, -1.0, Vector3(0, 0, PI / 2 - 0.08))
	else:
		box(mats.formica, Vector3(1.1, 0.05, 0.75), pos + Vector3(0, 0.76, 0), yaw)
		cyl(mats.chrome, 0.05, 0.74, pos + Vector3(0, 0.37, 0), 8)
		cyl(mats.chrome, 0.26, 0.03, pos + Vector3(0, 0.015, 0), 10)

func stool(mats: Dictionary, pos: Vector3, fallen := false) -> void:
	if fallen:
		cyl(mats.chrome, 0.035, 0.6, pos + Vector3(0, 0.19, 0), 6, true, -1.0, Vector3(0, 0, PI / 2 - 0.1))
		cyl(mats.vinyl, 0.19, 0.08, pos + Vector3(-0.32, 0.2, 0), 10, true, -1.0, Vector3(0, 0, PI / 2 - 0.1))
		return
	cyl(mats.chrome, 0.035, 0.62, pos + Vector3(0, 0.31, 0), 6)
	cyl(mats.chrome, 0.2, 0.03, pos + Vector3(0, 0.015, 0), 10)
	cyl(mats.vinyl, 0.19, 0.08, pos + Vector3(0, 0.66, 0), 10)

func chair(mats: Dictionary, pos: Vector3, yaw := 0.0, fallen := false) -> void:
	var b := Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, -PI / 2 + 0.1) if fallen else Basis.IDENTITY)
	var o := pos + (Vector3(0, 0.24, 0) if fallen else Vector3.ZERO)
	box_xf(mats.vinyl, Vector3(0.42, 0.06, 0.42), Transform3D(b, o + b * Vector3(0, 0.45, 0)))
	box_xf(mats.vinyl, Vector3(0.42, 0.4, 0.05), Transform3D(b, o + b * Vector3(0, 0.78, -0.2)))
	for l in [Vector3(-0.18, 0.22, -0.18), Vector3(0.18, 0.22, -0.18), Vector3(-0.18, 0.22, 0.18), Vector3(0.18, 0.22, 0.18)]:
		box_xf(mats.chrome, Vector3(0.03, 0.44, 0.03), Transform3D(b, o + b * l))

## Steel store shelving (gondola) with a few leftover boxes; r = footprint centre, runs along z.
func shelf_unit(mats: Dictionary, pos: Vector3, length: float, rng: RandomNumberGenerator, along_x := false) -> void:
	var yaw := PI / 2 if along_x else 0.0
	var b := Basis(Vector3.UP, yaw)
	box_xf(mats.steel, Vector3(0.06, 1.7, length), Transform3D(b, pos + Vector3(0, 0.85, 0)))
	for k in 4:
		box_xf(mats.steel, Vector3(0.86, 0.035, length), Transform3D(b, pos + Vector3(0, 0.12 + k * 0.42, 0)))
	for e: float in [-1.0, 1.0]:
		box_xf(mats.steel, Vector3(0.9, 1.75, 0.05), Transform3D(b, pos + b * Vector3(0, 0.875, e * length * 0.5)))
	for k in 3:   # sparse leftover stock: the shelves were stripped
		for side: float in [-1.0, 1.0]:
			for j in int(length / 0.8):
				if rng.randf() > 0.3: continue
				var s := Vector3(rng.randf_range(0.14, 0.3), rng.randf_range(0.1, 0.3), rng.randf_range(0.2, 0.42))
				var lp := Vector3(side * 0.24, 0.14 + k * 0.42 + s.y * 0.5, -length * 0.5 + 0.4 + j * 0.8 + rng.randf_range(-0.15, 0.15))
				box_xf(mats.carton if rng.randf() < 0.6 else mats.tin, s, Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), pos + b * lp))

## ISO shipping container (6.06 x 2.59 x 2.44 m), long axis along local x.
func container(mat: Material, frame: Material, pos: Vector3, yaw := 0.0) -> void:
	box(mat, Vector3(6.06, 2.59, 2.44), pos + Vector3(0, 1.295, 0), yaw, Vector2(1.6, 2.59))
	var b := Basis(Vector3.UP, yaw)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box_xf(frame, Vector3(0.14, 2.63, 0.14), Transform3D(b, pos + b * Vector3(sx * 3.0, 1.3, sz * 1.19)))
	for sz: float in [-1.0, 1.0]:
		for y: float in [0.06, 2.56]:
			box_xf(frame, Vector3(6.1, 0.14, 0.12), Transform3D(b, pos + b * Vector3(0, y, sz * 1.2)))

func sandbags(mat: Material, a: Vector3, b: Vector3, rows := 3) -> void:
	var d := b - a; var n := int(d.length() / 0.62); var yaw := atan2(d.x, d.z) + PI / 2
	for r in rows:
		for i in n - (r % 2):
			var p := a + d * ((i + 0.5 + (r % 2) * 0.5) / n)
			box(mat, Vector3(0.6, 0.2, 0.34), p + Vector3(0, 0.1 + r * 0.19, 0), yaw + sin(i * 7.3 + r) * 0.12, Vector2.ZERO, r == rows - 1)

## Folding camp table with abandoned supply cartons.
func supply_table(mats: Dictionary, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	box_xf(mats.steel, Vector3(1.8, 0.04, 0.75), Transform3D(b, pos + Vector3(0, 0.74, 0)))
	for l in [Vector3(-0.8, 0.37, -0.3), Vector3(0.8, 0.37, -0.3), Vector3(-0.8, 0.37, 0.3), Vector3(0.8, 0.37, 0.3)]:
		box_xf(mats.steel, Vector3(0.04, 0.74, 0.04), Transform3D(b, pos + b * l))
	for i in 4:
		var s := Vector3(rng.randf_range(0.28, 0.42), rng.randf_range(0.18, 0.32), rng.randf_range(0.26, 0.36))
		box_xf(mats.carton, s, Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), pos + b * Vector3(-0.66 + i * 0.44, 0.76 + s.y * 0.5, rng.randf_range(-0.12, 0.12))))

func bench(mats: Dictionary, pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for k in 3:
		box_xf(mats.plank, Vector3(1.7, 0.04, 0.12), Transform3D(b, pos + b * Vector3(0, 0.45, -0.14 + k * 0.14)))
	for k in 2:
		box_xf(mats.plank, Vector3(1.7, 0.1, 0.04), Transform3D(b, pos + b * Vector3(0, 0.66 + k * 0.16, -0.24)))
	for sx: float in [-0.7, 0.7]:
		box_xf(mats.trim, Vector3(0.06, 0.86, 0.06), Transform3D(b, pos + b * Vector3(sx, 0.43, -0.24)))
		box_xf(mats.trim, Vector3(0.06, 0.45, 0.4), Transform3D(b, pos + b * Vector3(sx, 0.22, 0.0)))

## Canvas relief tent: four poles, pitched roof, one side wall.
func tent(mats: Dictionary, pos: Vector3, yaw: float, w := 3.2, d := 3.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box_xf(mats.steel, Vector3(0.05, 2.2, 0.05), Transform3D(b, pos + b * Vector3(sx * w * 0.5, 1.1, sz * d * 0.5)))
		box_xf(mats.canvas, Vector3(w * 0.56, 0.04, d + 0.3), Transform3D(b * Basis(Vector3(0, 0, 1), -sx * 0.42), pos + b * Vector3(sx * w * 0.25, 2.5, 0)))
	box_xf(mats.canvas, Vector3(0.04, 2.1, d), Transform3D(b, pos + b * Vector3(-w * 0.5, 1.1, 0)))
