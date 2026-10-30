class_name CrateNode
extends Node3D
## The Mystery Crate: a ~4.5 s spinning roll that slows down as it settles, then the gun is
## yours to take for 9 s (it sinks back into the box as the timer runs out). Sometimes the
## Phantom shows up instead: a pale grinning mask rises, laughs, refunds you and the crate flies off.

enum State { IDLE, ROLLING, READY }
var state := State.IDLE
var result := ""
var t := 0.0
var cycle_t := 0.0
var display: Node3D
var light: OmniLight3D
var lid: MeshInstance3D
var game
var move_after := false
var glow_mat: StandardMaterial3D
const ROLL_TIME := 4.5
const TAKE_TIME := 9.0
var timer_lbl: Label3D
## v7.8 reveal drama: a soft light beam rises out of the open crate while it rolls, the lamp pulses on every
## reel tick, and the reveal lands with a gold flash, a punch-in on the gun and a spark burst.
const ROLL_COLOR := Color(0.3, 0.8, 1.0)
const REVEAL_COLOR := Color(1.0, 0.78, 0.35)
const BEAM_HEIGHT := 3.2
const PULSE_ENERGY := 6.5
const BASE_ROLL_ENERGY := 3.0
const REVEAL_FLASH := 11.0
var beam: MeshInstance3D
var beam_mat: StandardMaterial3D

func build() -> void:
	var wood := StandardMaterial3D.new(); wood.albedo_color = Color(0.25, 0.16, 0.08); wood.roughness = 0.8
	var trim := StandardMaterial3D.new(); trim.albedo_color = Color(0.85, 0.65, 0.2); trim.metallic = 0.8
	var glow := StandardMaterial3D.new(); glow_mat = glow; glow.albedo_color = Color(0.4, 0.9, 1.0)
	glow.emission_enabled = true; glow.emission = Color(0.3, 0.8, 1.0); glow.emission_energy_multiplier = 3.0
	var body := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.8, 0.8)
	body.mesh = bm; body.material_override = wood; body.position.y = 0.4; add_child(body)
	for x in [-0.85, 0.85]:
		var tr := MeshInstance3D.new(); var tm := BoxMesh.new(); tm.size = Vector3(0.08, 0.82, 0.82)
		tr.mesh = tm; tr.material_override = trim; tr.position = Vector3(x, 0.4, 0); add_child(tr)
	var q := MeshInstance3D.new(); var qm := BoxMesh.new(); qm.size = Vector3(0.3, 0.3, 0.02)
	q.mesh = qm; q.material_override = glow; q.position = Vector3(0, 0.45, 0.41); add_child(q)
	lid = MeshInstance3D.new(); var lm := BoxMesh.new(); lm.size = Vector3(1.8, 0.08, 0.8)
	lid.mesh = lm; lid.material_override = wood; lid.position.y = 0.84; add_child(lid)
	light = OmniLight3D.new(); light.light_color = Color(0.3, 0.8, 1.0); light.light_energy = 1.5
	light.omni_range = 5.0; light.position.y = 1.6; add_child(light)
	var col := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 0.9, 0.8); cs.shape = sh; cs.position.y = 0.45; col.add_child(cs); add_child(col)
	timer_lbl = Label3D.new(); timer_lbl.font_size = 48; timer_lbl.pixel_size = 0.004; timer_lbl.outline_size = 10
	timer_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; timer_lbl.position.y = 1.95; timer_lbl.modulate = Color(0.6, 0.95, 1.0)
	timer_lbl.visible = false; add_child(timer_lbl)
	beam = MeshInstance3D.new(); beam.name = "RevealBeam"
	var cm := CylinderMesh.new(); cm.top_radius = 0.2; cm.bottom_radius = 0.55; cm.height = BEAM_HEIGHT; cm.cap_top = false; cm.cap_bottom = false
	beam.mesh = cm; beam.position.y = 0.86 + BEAM_HEIGHT * 0.5
	beam_mat = StandardMaterial3D.new(); beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED; beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam_mat.albedo_texture = beam_texture(); beam_mat.albedo_color = Color(ROLL_COLOR.r, ROLL_COLOR.g, ROLL_COLOR.b) * 0.45
	beam.material_override = beam_mat; beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false; add_child(beam)

## Vertical fade: bright at the crate mouth, gone by the top (UV v=0 is the cylinder top).
static func beam_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0.35, 0.35, 0.35, 1), Color(1, 1, 1, 1)])
	var t := GradientTexture2D.new(); t.gradient = g; t.width = 4; t.height = 64
	t.fill_from = Vector2(0.5, 0.0); t.fill_to = Vector2(0.5, 1.0)
	return t

func _set_beam(c: Color, a: float) -> void:
	beam_mat.albedo_color = Color(c.r, c.g, c.b) * a

func _reveal() -> void:
	light.light_color = REVEAL_COLOR; light.light_energy = REVEAL_FLASH
	_set_beam(REVEAL_COLOR, 0.8)
	if display:
		display.scale = Vector3.ONE * 1.35
		var tw := create_tween(); tw.tween_property(display, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if game and game.fx: game.fx.sparks(global_position + Vector3.UP * 1.36, Vector3.UP, REVEAL_COLOR, 24, 0.5, 3.5, 0.035)

func start(final_id: String) -> void:
	result = final_id; state = State.ROLLING; t = ROLL_TIME; cycle_t = 0.0
	lid.position = Vector3(0, 0.9, -0.35); lid.rotation.x = -1.2
	light.light_energy = PULSE_ENERGY; light.light_color = ROLL_COLOR
	beam.visible = true; _set_beam(ROLL_COLOR, 0.45)

func _set_display(id: String) -> void:
	if display: display.queue_free()
	var w := Weapons.make(id)
	display = Node3D.new()
	var g := ModelLib.gun(Weapons.MODELS.get(id, "pistol"))
	g.rotation.y = PI / 2; g.scale = Vector3.ONE * 1.5
	display.add_child(g)
	display.position = Vector3(0, 1.25, 0)
	add_child(display)
	ModelLib.set_shadows(display, false)

func _process(dt: float) -> void:
	if state == State.IDLE: return
	t -= dt
	if state == State.ROLLING:
		var k := 1.0 - t / ROLL_TIME   # 0 -> 1, the reel slows down toward the end
		cycle_t -= dt
		if cycle_t <= 0.0:
			_set_display(Weapons.ALL_IDS[randi() % Weapons.ALL_IDS.size()])
			cycle_t = lerpf(0.06, 0.35, k * k)
			if game: game.sfx.play_at("tink", global_position + Vector3.UP, -14, 1.0 + k * 0.3)
			light.light_energy = PULSE_ENERGY   # pulse on every reel tick
		light.light_energy = lerpf(light.light_energy, BASE_ROLL_ENERGY, clampf(dt * 10.0, 0, 1))
		_set_beam(ROLL_COLOR, 0.3 + 0.35 * k)
		display.position.y = 0.9 + minf(k * 1.3, 1.0) * 0.46
		display.rotation.y += dt * lerpf(14.0, 2.0, k)
		if t <= 0.0:
			if move_after:
				_overload(); return
			_set_display(result); display.position.y = 1.36
			state = State.READY; t = TAKE_TIME; timer_lbl.visible = true
			_reveal()
			if game: game.sfx.play_at("crate_ready", global_position + Vector3.UP, -2)
	elif state == State.READY:
		display.rotation.y += dt
		light.light_energy = lerpf(light.light_energy, 4.0, clampf(dt * 3.0, 0, 1))
		_set_beam(REVEAL_COLOR, 0.25 + 0.55 * clampf(t / TAKE_TIME, 0, 1))   # beam fades as the take timer runs out
		timer_lbl.text = "%d" % ceili(t)
		if t < 3.0: display.position.y = 1.36 - (3.0 - t) * 0.17   # sinking back in: last chance
		if t <= 0.0: close()

## The crate refuses this roll (refund) and jumps to a new spot.
func _overload() -> void:
	move_after = false
	state = State.IDLE
	if display: display.queue_free(); display = null
	# the Phantom: an original pale mask that rises out of the crate and laughs
	var ph := Label3D.new(); ph.text = "◉‿◉"; ph.font_size = 140; ph.pixel_size = 0.005; ph.outline_size = 24
	ph.modulate = Color(0.85, 0.95, 1.0, 0.95); ph.outline_modulate = Color(0.1, 0.4, 0.6)
	ph.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ph.position.y = 1.0; add_child(ph)
	var nm := Label3D.new(); nm.text = "THE PHANTOM"; nm.font_size = 40; nm.pixel_size = 0.004; nm.outline_size = 8
	nm.billboard = BaseMaterial3D.BILLBOARD_ENABLED; nm.position.y = -0.45; nm.modulate = Color(0.6, 0.9, 1.0); ph.add_child(nm)
	var pt := create_tween(); pt.tween_property(ph, "position:y", 2.0, 0.9).set_trans(Tween.TRANS_BACK)
	pt.tween_interval(1.0); pt.tween_property(ph, "modulate:a", 0.0, 0.4); pt.tween_callback(ph.queue_free)
	if game:
		game.player.economy.points += MysteryCrate.COST
		game.hud.banner("THE PHANTOM", 2.0)
		game.hud.info("The Phantom took the crate! %d refunded" % MysteryCrate.COST)
		game.sfx.play_at("phantom_laugh", global_position + Vector3.UP, 2)
		game.sfx.play_at("crate_move", global_position + Vector3.UP, 0)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(self, "position:y", 6.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 8.0, 1.0)
	tw.tween_callback(func():
		close()
		if game: game.relocate_crate())

func take() -> String:
	var r := result; close(); return r

func close() -> void:
	state = State.IDLE
	if timer_lbl: timer_lbl.visible = false
	if display: display.queue_free(); display = null
	lid.position = Vector3(0, 0.84, 0); lid.rotation.x = 0
	light.light_energy = 1.5; light.light_color = ROLL_COLOR
	if beam: beam.visible = false
