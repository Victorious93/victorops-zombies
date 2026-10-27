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

func start(final_id: String) -> void:
	result = final_id; state = State.ROLLING; t = ROLL_TIME; cycle_t = 0.0
	lid.position = Vector3(0, 0.9, -0.35); lid.rotation.x = -1.2
	light.light_energy = 4.0

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
		display.position.y = 0.9 + minf(k * 1.3, 1.0) * 0.46
		display.rotation.y += dt * lerpf(14.0, 2.0, k)
		if t <= 0.0:
			if move_after:
				_overload(); return
			_set_display(result); display.position.y = 1.36
			state = State.READY; t = TAKE_TIME; timer_lbl.visible = true
			if game: game.sfx.play_at("crate_ready", global_position + Vector3.UP, -2)
	elif state == State.READY:
		display.rotation.y += dt
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
	light.light_energy = 1.5
