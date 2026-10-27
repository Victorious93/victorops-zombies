class_name Viewmodel
extends Node3D
## First-person arms + gun. Gun meshes are CC0 Quaternius models; sleeves are procedural and the
## hands use the CC0 glove model. All motion (sway, bob, kick, reload, knife, throw) is procedural.

const HIP_POS := Vector3(0.17, -0.17, -0.36)
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
var sleeve_mat: StandardMaterial3D
var reload_phase := -1.0
var model_name := ""

func setup(sleeve: Color) -> void:
	sleeve_mat = StandardMaterial3D.new(); sleeve_mat.albedo_color = sleeve.darkened(0.55); sleeve_mat.roughness = 0.95
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
	if w.tier > 0: _tint_upgraded(gun, w.color)
	var len: float = ModelLib.GUN_LEN.get(model_name, 0.4)
	# arms: right hand on the grip, left hand under the fore-end
	arms = Node3D.new(); add_child(arms)
	var grip := Vector3(0.0, -0.06, len * 0.18)
	var fore := Vector3(0.0, -0.045, -len * 0.22) if len > 0.3 else Vector3(-0.01, -0.07, len * 0.12)
	arms.add_child(_hand(grip + Vector3(0.012, -0.01, 0.02), Vector3(-0.4, PI, 0.15)))
	arms.add_child(_hand(fore + Vector3(-0.02, -0.01, 0.0), Vector3(-0.2, PI, -0.5)))
	_sleeve(grip + Vector3(0.02, -0.03, 0.06), grip + Vector3(0.14, -0.2, 0.42), 0.032)
	_sleeve(fore + Vector3(-0.03, -0.03, 0.04), fore + Vector3(-0.24, -0.22, 0.5), 0.032)
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
	if not first: swap_t = 1.0

func _tint_upgraded(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.6
				mi.set_surface_override_material(i, m)
	for ch in n.get_children(): _tint_upgraded(ch, c)

func fire(strength: float) -> void:
	kick = minf(kick + strength, 1.6)
	flash.visible = true; flash.rotation.z = randf() * TAU; flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	flash_light.light_energy = 3.0; flash_t = 0.045

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
	var target := HIP_POS.lerp(ADS_POS, ads_k)
	var bob_amt := lerpf(1.0, 0.2, ads_k) * move01
	var off := Vector3(sin(bob) * 0.012, -absf(cos(bob)) * 0.012, 0) * bob_amt
	off += Vector3(-sway.x * 0.25, sway.y * 0.25, 0) * lerpf(1.0, 0.3, ads_k)
	off.z += kick * 0.045
	if sprint: off += Vector3(-0.06, -0.06, 0.04)
	var rot := Vector3(kick * 0.12 + (-0.45 if sprint else 0.0), sway.x * 0.5, sin(bob * 0.5) * 0.03 * bob_amt)
	if sprint: rot.y += 0.6; rot.z += 0.25
	# reload: tilt + dip, magazine pull/insert beats
	if reload01 >= 0.0:
		var k := sin(clampf(reload01, 0, 1) * PI)
		off += Vector3(-0.03, -0.09, 0.02) * k
		rot += Vector3(-0.35, 0.25, 0.75) * k
		if reload01 > 0.45 and reload01 < 0.6: off.y += sin((reload01 - 0.45) / 0.15 * PI) * 0.03
	# swap: dip out and back
	off.y -= sin(swap_t * PI) * 0.25
	# knife / throw: lower the gun while the other hand acts
	var lower := maxf(sin(clampf(knife_t, 0, 1) * PI), sin(clampf(throw_t, 0, 1) * PI))
	off.y -= lower * 0.18; rot.x -= lower * 0.5
	position = position.lerp(target + off, clampf(dt * 18, 0, 1))
	rotation = rotation.lerp(rot, clampf(dt * 16, 0, 1))
	if sight: sight.visible = ads_k > 0.2
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
		flash_t -= dt
		if flash_t <= 0.0: flash.visible = false; flash_light.light_energy = 0.0
