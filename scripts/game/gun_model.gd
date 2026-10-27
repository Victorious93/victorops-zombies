class_name GunModel
## Builds original low-poly gun meshes from primitives (no third-party models).

static func _mat(c: Color, metal := 0.4, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.position = pos; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Returns a Node3D whose forward is -Z; a child "Muzzle" marks the barrel end.
static func build(w: WeaponDef) -> Node3D:
	var root := Node3D.new()
	var body := _mat(w.color, 0.5)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.6)
	var accent := _mat(Color(0.2, 0.9, 1.0) if w.tier == 0 else w.color.lightened(0.4), 0.0, true)
	var length := 0.3
	match w.id:
		"sidearm":
			length = 0.24
			_box(root, Vector3(0.05, 0.07, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.045, 0.12, 0.06), Vector3(0, -0.08, -0.03), dark)
		"smg":
			length = 0.42
			_box(root, Vector3(0.07, 0.09, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.04, 0.16, 0.05), Vector3(0, -0.11, -0.2), dark)
			_box(root, Vector3(0.05, 0.1, 0.05), Vector3(0, -0.08, -0.04), dark)
		"scatter":
			length = 0.7
			_box(root, Vector3(0.08, 0.1, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.06, 0.06, 0.4), Vector3(0, -0.07, -0.42), dark)
		"rifle":
			length = 0.75
			_box(root, Vector3(0.07, 0.1, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.05, 0.18, 0.07), Vector3(0, -0.12, -0.3), dark)
			_box(root, Vector3(0.04, 0.05, 0.2), Vector3(0, 0.08, -0.25), dark)
		"cannon":
			length = 0.95
			_box(root, Vector3(0.1, 0.12, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.03, 0.03, length), Vector3(0, 0.08, -length / 2), accent)
		"nova":
			length = 0.6
			_box(root, Vector3(0.14, 0.14, length), Vector3(0, 0, -length / 2), body)
			_box(root, Vector3(0.18, 0.18, 0.08), Vector3(0, 0, -length + 0.05), accent)
		_:
			_box(root, Vector3(0.06, 0.08, length), Vector3(0, 0, -length / 2), body)
	_box(root, Vector3(0.02, 0.02, 0.06), Vector3(0, 0.05, -length + 0.04), accent)
	var muzzle := Marker3D.new(); muzzle.name = "Muzzle"; muzzle.position = Vector3(0, 0, -length - 0.02)
	root.add_child(muzzle)
	return root
