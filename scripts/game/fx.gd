class_name Fx
extends Node3D
## Pooled-ish visual effects: blood floor pools, wall bullet holes, gibs, sparks, shells,
## splinters, explosions, points popups. Floor/wall "decals" are oriented quads so they also
## work on the gl_compatibility renderer (which has no Decal support).

const MAX_DECALS := 48
const MAX_GIBS := 30
var game
var decals: Array = []
var gibs_alive: Array = []
var particle_scale := 1.0
var _blood_tex: Texture2D
var _hole_tex: Texture2D
var _soft_tex: Texture2D
var _mats := {}

func _ready() -> void:
	_blood_tex = _radial(Color(0.35, 0.0, 0.0, 0.95), Color(0.2, 0.0, 0.0, 0.0), 128, true)
	_hole_tex = _radial(Color(0.03, 0.03, 0.03, 1.0), Color(0.15, 0.13, 0.1, 0.0), 32, false)
	_soft_tex = _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 32, false)

func _radial(a: Color, b: Color, size: int, splat: bool) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = size
	var blobs: Array = []
	if splat:
		for i in 9: blobs.append([Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)) * size, rng.randf_range(0.08, 0.22) * size])
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var d := p.distance_to(Vector2(size, size) / 2) / (size / 2.0)
			var v := clampf(1.0 - d, 0, 1)
			for bl in blobs: v = maxf(v, clampf(1.0 - p.distance_to(bl[0]) / bl[1], 0, 1))
			v = smoothstep(0.0, 0.35, v)
			img.set_pixel(x, y, b.lerp(a, v))
	return ImageTexture.create_from_image(img)

func _quad_mat(key: String, tex: Texture2D, color := Color.WHITE, unshaded := false, additive := false) -> StandardMaterial3D:
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new(); m.albedo_texture = tex; m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.3
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[key] = m
	return m

func _add_decal(n: Node3D) -> void:
	decals.append(n)
	while decals.size() > MAX_DECALS:
		var old: Node3D = decals.pop_front()
		if is_instance_valid(old): old.queue_free()

## Flat quad aligned to a surface normal.
func surface_quad(at: Vector3, normal: Vector3, size: float, mat: Material, life := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(size, size); mi.mesh = q
	mi.material_override = mat; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.global_position = at + normal * 0.012
	mi.look_at(at + normal * 2.0, up)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	if life > 0.0: get_tree().create_timer(life).timeout.connect(mi.queue_free)
	else: _add_decal(mi)
	return mi

func bullet_hole(at: Vector3, normal: Vector3) -> void:
	surface_quad(at, normal, randf_range(0.07, 0.11), _quad_mat("hole", _hole_tex))
	sparks(at, normal, Color(1.0, 0.8, 0.45), 5)

func blood_hit(at: Vector3, dir: Vector3) -> void:
	sparks(at, -dir, Color(0.55, 0.0, 0.0), 8, 0.25, 2.5)
	# spatter on the floor / wall behind
	var space := get_world_3d().direct_space_state
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * 2.5 + Vector3.DOWN * 1.2, 1))
	if not r.is_empty():
		surface_quad(r.position, r.normal, randf_range(0.3, 0.6), _quad_mat("blood", _blood_tex))

func blood_pool(at: Vector3) -> void:
	var m := surface_quad(at + Vector3.UP * 0.01, Vector3.UP, 0.2, _quad_mat("blood", _blood_tex))
	var tw := create_tween(); tw.tween_property(m, "scale", Vector3.ONE * randf_range(6.0, 9.0), 1.8).set_ease(Tween.EASE_OUT)

func sparks(at: Vector3, normal: Vector3, color: Color, amount: int, life := 0.18, spd := 4.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.emitting = false; p.amount = maxi(1, int(amount * particle_scale)); p.lifetime = life
	p.explosiveness = 1.0; p.direction = normal; p.spread = 50.0
	p.initial_velocity_min = spd * 0.5; p.initial_velocity_max = spd; p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new(); q.size = Vector2(0.03, 0.03); p.mesh = q
	var m := _quad_mat("spark_%s" % color.to_html(), _soft_tex, color, true, color.r > 0.8)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.material_override = m
	add_child(p); p.global_position = at; p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

func splinters(at: Vector3) -> void:
	sparks(at, Vector3.UP, Color(0.45, 0.3, 0.15), 10, 0.5, 3.0)

## Chunky physics gibs (dark red boxes) that settle and fade.
func gibs(at: Vector3, n: int, z: Node3D = null, force := Vector3.ZERO) -> void:
	n = maxi(1, int(n * particle_scale))
	var flesh: StandardMaterial3D = _mats.get("gib")
	if flesh == null:
		flesh = StandardMaterial3D.new(); flesh.albedo_color = Color(0.32, 0.03, 0.03); flesh.roughness = 0.25
		_mats.gib = flesh
	for i in n:
		var rb := RigidBody3D.new(); rb.collision_layer = 0; rb.collision_mask = 1; rb.mass = 0.3
		var s := randf_range(0.07, 0.16)
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3.ONE * s; cs.shape = sh; rb.add_child(cs)
		var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(s, s * randf_range(0.6, 1.4), s); mi.mesh = bm
		mi.material_override = flesh; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; rb.add_child(mi)
		add_child(rb); rb.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.2), randf_range(-0.2, 0.2))
		rb.linear_velocity = Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)) + force * 0.4
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		gibs_alive.append(rb)
		get_tree().create_timer(randf_range(4.0, 6.0)).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free(); gibs_alive.erase(rb))
	while gibs_alive.size() > MAX_GIBS:
		var old = gibs_alive.pop_front()
		if is_instance_valid(old): old.queue_free()
	sparks(at, Vector3.UP, Color(0.5, 0.0, 0.0), 14, 0.4, 4.0)

## Ejected brass: a small cylinder thrown right/up from the viewmodel, then dropped in world.
func shell(from: Vector3, right: Vector3, up: Vector3, big := false) -> void:
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new()
	cm.top_radius = 0.006 if not big else 0.01; cm.bottom_radius = cm.top_radius; cm.height = 0.025 if not big else 0.05
	cm.radial_segments = 6; cm.rings = 1; mi.mesh = cm
	var brass: StandardMaterial3D = _mats.get("brass")
	if brass == null:
		brass = StandardMaterial3D.new(); brass.albedo_color = Color(0.85, 0.62, 0.25) if true else Color.RED; brass.metallic = 0.9; brass.roughness = 0.3
		_mats.brass = brass
	mi.material_override = brass; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); mi.global_position = from
	var vel := right * randf_range(1.6, 2.4) + up * randf_range(1.2, 2.0)
	var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var state := {v = vel, t = 0.0, bounced = false}
	var tick := func(dt: float) -> bool:
		state.t += dt
		state.v.y -= 9.8 * dt
		mi.global_position += state.v * dt
		mi.rotation += spin * dt
		if not state.bounced and state.t > 0.45:
			state.bounced = true
			if game and game.player and mi.global_position.distance_to(game.player.global_position) < 4.0:
				game.sfx.play_at("shell%d" % (randi() % 2 + 1), mi.global_position, -14, randf_range(0.9, 1.2))
		return state.t > 0.8
	_movers.append([mi, tick])

var _movers: Array = []
func _process(dt: float) -> void:
	for m in _movers.duplicate():
		if not is_instance_valid(m[0]) or m[1].call(dt):
			if is_instance_valid(m[0]): m[0].queue_free()
			_movers.erase(m)

func explosion(at: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = radius * 0.6; sm.height = radius * 1.2
	sm.radial_segments = 12; sm.rings = 6; mi.mesh = sm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.85); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m; add_child(mi); mi.global_position = at; mi.scale = Vector3.ONE * 0.2
	var tw := create_tween(); tw.tween_property(mi, "scale", Vector3.ONE, 0.18); tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_callback(mi.queue_free)
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.6, 0.25); l.light_energy = 6.0; l.omni_range = radius * 2.5
	add_child(l); l.global_position = at + Vector3.UP * 0.5
	var tl := create_tween(); tl.tween_property(l, "light_energy", 0.0, 0.4); tl.tween_callback(l.queue_free)
	sparks(at, Vector3.UP, Color(1.0, 0.7, 0.3), 24, 0.6, 9.0)
	sparks(at, Vector3.UP, Color(0.15, 0.13, 0.12), 16, 1.2, 3.0)
	surface_quad(at + Vector3.UP * 0.02, Vector3.UP, radius * 0.9, _quad_mat("scorch", _hole_tex, Color(1, 1, 1, 0.85)))

## Floating "+N" points popup in world space.
func popup(at: Vector3, text: String, color := Color(1.0, 0.86, 0.3)) -> void:
	var l := Label3D.new(); l.text = text; l.font_size = 44; l.pixel_size = 0.004; l.outline_size = 10
	l.modulate = color; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true; l.shaded = false
	add_child(l); l.global_position = at + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	var tw := create_tween(); tw.tween_property(l, "global_position:y", at.y + 0.8, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(l.queue_free)
