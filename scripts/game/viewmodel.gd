class_name Viewmodel
extends Node3D
## First-person arms + gun. Gun meshes are CC0 Quaternius models; sleeves are procedural and the
## hands use the CC0 glove model. All motion (sway, bob, kick, reload, knife, throw) is procedural.

const HIP_POS := Vector3(0.13, -0.095, -0.42)
const SIGHT_H := 0.055   ## red-dot height above the gun's centre line
const ADS_POS := Vector3(0.0, -SIGHT_H, -0.27)

var gun: Node3D
var muzzle: Node3D
var arms: Node3D
var sight: Node3D
var knife: Node3D
var grenade_hand: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var flash_t := 0.0
var shown := ""
var sway := Vector2.ZERO
var bob := 0.0
var kick := 0.0
var knife_t := 0.0
var throw_t := 0.0
var swap_t := 0.0
var ads_k := 0.0
const FILL_HIP := Vector3(-0.25, 0.25, 0.15)
const FILL_ADS := Vector3(-0.18, 0.08, 0.32)
var sleeve_mat: StandardMaterial3D
var reload_phase := -1.0
var model_name := ""
var overlay := false   ## render on the viewmodel layer (see ViewmodelOverlay)
## Fore-end grip point, as a fraction of gun length ahead of centre.
const FORE_AT := 0.24
## v7.4: bulky guns sit lower, further right and further out at hip so they no longer fill the view.
const HIP_TRIM := {launcher = Vector3(0.07, -0.09, -0.16)}
static func hip_pos(model: String) -> Vector3: return HIP_POS + HIP_TRIM.get(model, Vector3.ZERO)
var fps_arms: FpsArms   ## set by Player before set_weapon(); null in tests -> legacy glove props

func setup(sleeve: Color) -> void:
	sleeve_mat = StandardMaterial3D.new(); sleeve_mat.albedo_color = sleeve.darkened(0.55); sleeve_mat.roughness = 0.8; sleeve_mat.rim_enabled = true; sleeve_mat.rim = 0.4
	flash = MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(0.16, 0.16); flash.mesh = q
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.45); fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; fm.albedo_texture = _star_tex()
	flash.material_override = fm; flash.visible = false; flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_light = OmniLight3D.new(); flash_light.light_color = Color(1, 0.75, 0.4); flash_light.omni_range = 7
	flash_light.light_energy = 0.0; flash_light.shadow_enabled = false
	knife = ModelLib.prop("knife", 0.26, true, false)
	knife.visible = false  # parented to the camera by Player
	grenade_hand = Node3D.new(); grenade_hand.visible = false
	var g := ModelLib.prop("grenade", 0.075, false, false); g.position = Vector3(0, -0.03, 0); grenade_hand.add_child(g)
	grenade_hand.add_child(_hand(Vector3(0, -0.06, 0.03), Vector3(0.3, 0, 0)))
	position = HIP_POS

func _star_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x - 31.5, y - 31.5) / 32.0
			var r := p.length(); var a := atan2(p.y, p.x)
			var star := clampf(1.0 - r / (0.35 + 0.65 * pow(absf(cos(a * 3.0)), 8.0)), 0, 1)
			var core := clampf(1.0 - r * 2.5, 0, 1)
			var v := clampf(star * 0.8 + core, 0, 1)
			img.set_pixel(x, y, Color(1, 0.85 + 0.15 * core, 0.5 + 0.5 * core, v))
	return ImageTexture.create_from_image(img)

func _hand(pos: Vector3, rot: Vector3) -> Node3D:
	var h := ModelLib.prop("glove", 0.11, false, false)
	h.position = pos; h.rotation = rot
	return h

func _sleeve(from: Vector3, to: Vector3, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new()
	cm.top_radius = r; cm.bottom_radius = r * 1.15; cm.height = from.distance_to(to); cm.radial_segments = 8; cm.rings = 1
	mi.mesh = cm; mi.material_override = sleeve_mat; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arms.add_child(mi)
	mi.position = (from + to) / 2
	var dir := (to - from).normalized()
	mi.basis = Basis(Quaternion(Vector3.UP, dir))
	return mi

func set_weapon(w: WeaponDef) -> void:
	var key := "%s:%d" % [w.id, w.tier]
	if key == shown: return
	var first := shown == ""
	shown = key
	if gun:
		if flash.get_parent(): flash.get_parent().remove_child(flash)
		if flash_light.get_parent(): flash_light.get_parent().remove_child(flash_light)
		gun.queue_free(); arms.queue_free()
	model_name = Weapons.MODELS.get(w.id, "pistol")
	gun = ModelLib.gun(model_name)
	add_child(gun)
	muzzle = gun.get_node("Muzzle")
	muzzle.add_child(flash); muzzle.add_child(flash_light)
	if w.tier > 0: _tint_upgraded(gun, w.color, camo_texture(w.tier))
	else: _shade_metal(gun)
	var fc: Color = AltAmmo.COLORS.get(w.alt_ammo, Color(1.0, 0.8, 0.45))   # alt ammo tints the muzzle flash
	(flash.material_override as StandardMaterial3D).albedo_color = Color(fc.r, fc.g, fc.b, (flash.material_override as StandardMaterial3D).albedo_color.a)
	flash_light.light_color = fc
	# small cool fill light so arms + gun are never pure silhouettes (short range: barely touches the world)
	if fill == null:
		fill = OmniLight3D.new(); fill.light_color = Color(0.7, 0.85, 1.0); fill.light_energy = 0.7
		fill.omni_range = 0.9; fill.position = Vector3(-0.25, 0.25, 0.15); fill.light_specular = 0.6; add_child(fill)
	var len: float = ModelLib.GUN_LEN.get(model_name, 0.4)
	# arms: right hand on the grip, left hand under the fore-end
	arms = Node3D.new(); add_child(arms)
	var grip := Vector3(0.0, -0.06, len * 0.18)
	var fore := Vector3(-0.01, -0.07, len * 0.12)
	if len > 0.3:   # v7.3: palm goes under the real fore-end surface, measured from the mesh
		fore = fore_point(model_name, len)
	if fps_arms: fps_arms.attach(gun, grip, fore, len > 0.3)   # rigged CC0 arms reach the gun via IK
	else:
		arms.add_child(_hand(grip + Vector3(0.012, -0.01, 0.02), Vector3(-0.4, PI, 0.15)))
		arms.add_child(_hand(fore + Vector3(-0.02, -0.01, 0.0), Vector3(-0.2, PI, -0.5)))
	# red-dot sight (unshaded so it reads in the dark)
	sight = Node3D.new(); gun.add_child(sight)
	var housing := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.012; tm.outer_radius = 0.016
	tm.rings = 12; tm.ring_segments = 6; housing.mesh = tm; housing.rotation.x = PI / 2
	var hm := StandardMaterial3D.new(); hm.albedo_color = Color(0.06, 0.06, 0.07); hm.metallic = 0.6; hm.roughness = 0.4
	housing.material_override = hm; sight.add_child(housing)
	var dot := MeshInstance3D.new(); var dq := SphereMesh.new(); dq.radius = 0.0014; dq.height = 0.0028; dot.mesh = dq
	var dm := StandardMaterial3D.new(); dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dm.albedo_color = Color(1, 0.1, 0.05)
	dm.no_depth_test = true; dm.render_priority = 10
	dot.material_override = dm; dot.position.z = -0.002; sight.add_child(dot)
	sight.position = Vector3(0, SIGHT_H, -0.02)
	ModelLib.set_shadows(self, false)
	if overlay: ViewmodelOverlay.to_layer(self)
	if not first: swap_t = 1.0

var fill: OmniLight3D

func _shade_metal(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.rim_enabled = true; m.rim = 0.5; m.rim_tint = 0.3; m.roughness = minf(m.roughness, 0.55)
				mi.set_surface_override_material(i, m)
	for ch in n.get_children(): _shade_metal(ch)

static var _camo_cache := {}

## Overcharge Forge camo: a procedural blotch pattern (original, generated at runtime) in the tier's palette.
static func camo_texture(tier: int) -> Texture2D:
	if _camo_cache.has(tier): return _camo_cache[tier]
	var pal := AltAmmo.camo(tier)
	if pal.is_empty(): return null
	var n := FastNoiseLite.new(); n.seed = 7000 + tier; n.frequency = 0.09; n.fractal_octaves = 2
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := n.get_noise_2d(x, y)
			var c: Color = pal[0] if v < -0.05 else (pal[1] if v > 0.22 else pal[0].lerp(pal[1], 0.45).darkened(0.3))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_camo_cache[tier] = tex
	return tex

func _tint_upgraded(n: Node, c: Color, camo: Texture2D = null) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.albedo_color = m.albedo_color.lerp(c, 0.35); m.metallic = maxf(m.metallic, 0.55); m.roughness = 0.35
				m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.12
				m.rim_enabled = true; m.rim = 0.8; m.rim_tint = 0.6   # reads as overcharged metal, not a flat purple blob
				if camo:
					m.albedo_texture = camo; m.albedo_color = Color(1, 1, 1); m.uv1_triplanar = true; m.uv1_scale = Vector3.ONE * 9.0
					m.emission_texture = camo; m.emission = Color(1, 1, 1); m.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(i, m)
	for ch in n.get_children(): _tint_upgraded(ch, c, camo)

func fire(strength: float) -> void:
	kick = minf(kick + strength, 2.2)
	flash.visible = true; flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * clampf(0.8 + strength * 0.35, 0.9, 1.8)
	flash_light.light_energy = clampf(2.5 + strength * 2.0, 3.0, 7.0); flash_t = 0.06

func add_sway(look_delta: Vector2) -> void:
	sway += look_delta * 0.6
	sway = sway.limit_length(0.08)

## state: ads (bool), speed01, sprint, reload01 (-1 if not reloading), dt
func tick(dt: float, ads: bool, move01: float, sprint: bool, reload01: float) -> void:
	ads_k = move_toward(ads_k, 1.0 if ads else 0.0, dt * 7.0)
	bob += dt * move01 * (12.0 if sprint else 8.0)
	sway = sway.lerp(Vector2.ZERO, clampf(dt * 8.0, 0, 1))
	kick = lerpf(kick, 0.0, clampf(dt * 12.0, 0, 1))
	swap_t = move_toward(swap_t, 0.0, dt * 3.0)
	var target := hip_pos(model_name).lerp(ADS_POS, ads_k)
	var bob_amt := lerpf(1.0, 0.2, ads_k) * move01
	var off := Vector3(sin(bob) * 0.012, -absf(cos(bob)) * 0.012, 0) * bob_amt
	off += Vector3(-sway.x * 0.25, sway.y * 0.25, 0) * lerpf(1.0, 0.3, ads_k)
	off.z += kick * 0.06
	off.y += kick * 0.012
	if sprint: off += Vector3(-0.06, -0.06, 0.04)
	var rot := Vector3(kick * 0.2 + (-0.45 if sprint else 0.0), sway.x * 0.5, sin(bob * 0.5) * 0.03 * bob_amt)
	if sprint: rot.y += 0.6; rot.z += 0.25
	# reload: tilt + dip, magazine pull/insert beats
	if reload01 >= 0.0:
		var rp := reload_pose(reload01); off += rp[0]; rot += rp[1]
	# swap: drop out of frame, then raise with a roll and a small settle overshoot
	var sp := swap_pose(swap_t); off += sp[0]; rot += sp[1]
	# knife / throw: lower the gun while the other hand acts
	var lower := maxf(sin(clampf(knife_t, 0, 1) * PI), sin(clampf(throw_t, 0, 1) * PI))
	off.y -= lower * 0.18; rot.x -= lower * 0.5
	position = position.lerp(target + off, clampf(dt * 18, 0, 1))
	rotation = rotation.lerp(rot, clampf(dt * 16, 0, 1))
	if sight: sight.visible = ads_k > 0.2
	if fps_arms: fps_arms.set_ads(ads_k)
	if fill:   # ADS: fill slides toward the eye-left so the gun's back face and the support glove are not a silhouette
		fill.position = FILL_HIP.lerp(FILL_ADS, ads_k); fill.light_energy = lerpf(0.7, 1.1, ads_k)
	if knife_t > 0.0:
		knife_t -= dt / 0.35
		var p := 1.0 - clampf(knife_t, 0, 1)
		knife.visible = knife_t > 0.0
		knife.position = Vector3(lerpf(0.22, -0.18, p), lerpf(-0.05, -0.12, p), -0.42 - sin(p * PI) * 0.12)
		knife.rotation = Vector3(-PI / 2 + 0.3, lerpf(0.8, -0.8, p), PI / 2)
	if throw_t > 0.0:
		throw_t -= dt / 0.6
		var p := 1.0 - clampf(throw_t, 0, 1)
		grenade_hand.visible = throw_t > 0.0 and p < 0.75
		grenade_hand.position = Vector3(-0.15, lerpf(-0.2, 0.05, p), lerpf(-0.3, -0.65, p))
	if flash_t > 0.0:
		var was := flash_t
		flash_t -= dt
		if was > 0.025 and flash_t <= 0.025:  # second frame: smaller, twisted, dimmer flicker
			flash.scale *= 0.6; flash.rotation.z += 0.8; flash_light.light_energy *= 0.45
		if flash_t <= 0.0: flash.visible = false; flash_light.light_energy = 0.0

static func _smooth(a: float, b: float, t: float) -> float: return smoothstep(a, b, t)

## Keyframed reload (procedural, eased): tilt in -> mag out (drop jolt) -> mag in (upward slap)
## -> charge (snap back) -> settle. Returns [offset, rotation] added to the hip pose.
static func reload_pose(t: float) -> Array:
	t = clampf(t, 0.0, 1.0)
	var tilt := _smooth(0.0, 0.18, t) * (1.0 - _smooth(0.82, 1.0, t))
	var off := Vector3(-0.03, -0.09, 0.02) * tilt
	var rot := Vector3(-0.3, 0.25, 0.75) * tilt
	off.y -= sin(clampf((t - 0.24) / 0.14, 0.0, 1.0) * PI) * 0.025          # mag out: gun dips
	off.y += sin(clampf((t - 0.5) / 0.1, 0.0, 1.0) * PI) * 0.035            # mag in: slap up
	rot.x += sin(clampf((t - 0.5) / 0.1, 0.0, 1.0) * PI) * 0.12
	var ch := sin(clampf((t - 0.72) / 0.1, 0.0, 1.0) * PI)                  # charge: pulled back
	off.z += ch * 0.04; rot.z -= ch * 0.2
	return [off, rot]

## swap_t runs 1 -> 0. First third: drop out; rest: raise with ease-out-back and a roll-in.
static func swap_pose(swap_t: float) -> Array:
	if swap_t <= 0.0: return [Vector3.ZERO, Vector3.ZERO]
	var p := 1.0 - clampf(swap_t, 0.0, 1.0)
	var down: float
	if p < 0.3: down = _smooth(0.0, 0.3, p)
	else:
		var u := (p - 0.3) / 0.7
		var c1 := 1.70158; var c3 := c1 + 1.0
		var back := 1.0 + c3 * pow(u - 1.0, 3) + c1 * pow(u - 1.0, 2)      # ease-out-back 0 -> 1 (overshoots)
		down = 1.0 - back
	return [Vector3(0.02, -0.25, 0.0) * down, Vector3(-0.5, 0.0, -0.35) * down]

## Fore-end underside grip point (gun space) per model, tuned against hip/ADS renders
## (v7.3 tools: /tmp/arms3.sh); falls back to a fraction of the gun length.
const FORE_GRIP := {
	smg = Vector3(0.0, 0.026, -0.16), rifle = Vector3(0.0, 0.034, -0.15), lmg = Vector3(0.0, 0.05, -0.15),
	shotgun = Vector3(0.0, -0.012, -0.12), launcher = Vector3(0.0, -0.1, -0.15), raygun = Vector3(0.0, 0.0, -0.1)}
static func fore_point(model: String, len: float) -> Vector3:
	return FORE_GRIP.get(model, Vector3(0.0, -0.015, -len * FORE_AT))
