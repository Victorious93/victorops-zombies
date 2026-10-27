class_name ModelLib
## Loads and caches the CC0 GLB models in assets/models (see ASSETS.md) and normalises
## their size/orientation at runtime so gameplay code can ask for "a 0.3 m pistol facing -Z".

static var _cache := {}
static var _aabbs := {}
## Muzzle direction of each gun model in its own space: yaw that turns it to face -Z.
const GUN_YAW := {pistol = PI / 2, smg = PI / 2, shotgun = PI / 2, rifle = PI / 2, lmg = PI / 2, launcher = PI / 2, raygun = 0.0, knife = 0.0}
## Viewmodel length (metres) per gun model.
const GUN_LEN := {pistol = 0.24, smg = 0.42, shotgun = 0.72, rifle = 0.74, lmg = 0.82, launcher = 0.7, raygun = 0.36}

static func scene(name: String) -> PackedScene:
	if not _cache.has(name):
		_cache[name] = load("res://assets/models/%s.glb" % name)
	return _cache[name]

static func raw(name: String) -> Node3D:
	var s := scene(name)
	return s.instantiate() if s else Node3D.new()

static func _merge(n: Node, xf: Transform3D, acc: Array) -> void:
	var x := xf
	if n is Node3D: x = xf * (n as Node3D).transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = x * n.mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children(): _merge(c, x, acc)

static func aabb_of(name: String, inst: Node3D = null) -> AABB:
	if not _aabbs.has(name):
		var n := inst if inst else raw(name)
		var acc := [null]; _merge(n, Transform3D(), acc)
		_aabbs[name] = acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ONE)
		if inst == null: n.free()
	return _aabbs[name]

## A prop scaled uniformly so its largest dimension (or height) matches `size`, resting on y=0.
static func prop(name: String, size: float, by_height := false, cast_shadow := true) -> Node3D:
	var root := Node3D.new(); root.name = name
	var m := raw(name)
	var a := aabb_of(name, m)
	var dim := a.size.y if by_height else maxf(a.size.x, maxf(a.size.y, a.size.z))
	var s := size / maxf(dim, 0.001)
	m.scale = Vector3.ONE * s
	m.position = Vector3(-(a.position.x + a.size.x / 2) * s, -a.position.y * s, -(a.position.z + a.size.z / 2) * s)
	root.add_child(m)
	if not cast_shadow: set_shadows(m, false)
	return root

static func set_shadows(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children(): set_shadows(c, on)

## Gun facing -Z, centred, with a "Muzzle" marker at the front tip.
static func gun(name: String) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new(); root.add_child(pivot)
	var m := raw(name); pivot.add_child(m)
	var a := aabb_of(name, m)
	var yaw: float = GUN_YAW.get(name, PI / 2)
	var long := a.size.z if is_zero_approx(yaw) else a.size.x
	var s: float = GUN_LEN.get(name, 0.4) / maxf(long, 0.001)
	m.scale = Vector3.ONE * s
	m.position = -(a.position + a.size / 2) * s
	pivot.rotation.y = yaw
	set_shadows(m, false)
	var mz := Marker3D.new(); mz.name = "Muzzle"
	mz.position = Vector3(0, a.size.y * s * 0.18, -GUN_LEN.get(name, 0.4) / 2 - 0.02)
	root.add_child(mz)
	return root

## Animated character with its AnimationPlayer; returns [root, AnimationPlayer].
static func character(name: String, height: float) -> Array:
	var root := Node3D.new()
	var m := raw(name); root.add_child(m)
	var a := aabb_of(name, m)
	var s := height / maxf(a.size.y, 0.001)
	m.scale = Vector3.ONE * s
	m.position.y = -a.position.y * s
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	return [root, ap]

## Finds the animation whose name ends with `suffix` (GLBs prefix them with armature names).
static func anim_name(ap: AnimationPlayer, suffixes: Array) -> String:
	if ap == null: return ""
	var names := ap.get_animation_list()
	for suf in suffixes:
		for n in names:
			if n == suf or n.ends_with("|" + suf): return n
	return ""
