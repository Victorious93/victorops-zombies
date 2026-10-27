class_name CrateNode
extends Node3D
## The Mystery Crate: rolls for ~3 s cycling weapons, then offers the result for 8 s.

enum State { IDLE, ROLLING, READY }
var state := State.IDLE
var result := ""
var t := 0.0
var cycle_t := 0.0
var display: Node3D
var light: OmniLight3D
var lid: MeshInstance3D

func build() -> void:
	var wood := StandardMaterial3D.new(); wood.albedo_color = Color(0.25, 0.16, 0.08); wood.roughness = 0.8
	var trim := StandardMaterial3D.new(); trim.albedo_color = Color(0.85, 0.65, 0.2); trim.metallic = 0.8
	var glow := StandardMaterial3D.new(); glow.albedo_color = Color(0.4, 0.9, 1.0)
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

func start(final_id: String) -> void:
	result = final_id; state = State.ROLLING; t = 3.0; cycle_t = 0.0
	lid.position = Vector3(0, 0.9, -0.35); lid.rotation.x = -1.2
	light.light_energy = 4.0

func _set_display(id: String) -> void:
	if display: display.queue_free()
	display = GunModel.build(Weapons.make(id))
	display.rotation.y = PI / 2
	display.position = Vector3(0.3, 1.25, 0)
	add_child(display)

func _process(dt: float) -> void:
	if state == State.IDLE: return
	t -= dt
	if state == State.ROLLING:
		cycle_t -= dt
		if cycle_t <= 0.0:
			_set_display(Weapons.ALL_IDS[randi() % Weapons.ALL_IDS.size()])
			cycle_t = 0.12
		display.position.y = 1.0 + (3.0 - t) * 0.12
		if t <= 0.0:
			_set_display(result); display.position.y = 1.36
			state = State.READY; t = 8.0
	elif state == State.READY:
		display.rotation.y += dt
		if t <= 0.0: close()

func take() -> String:
	var r := result; close(); return r

func close() -> void:
	state = State.IDLE
	if display: display.queue_free(); display = null
	lid.position = Vector3(0, 0.84, 0); lid.rotation.x = 0
	light.light_energy = 1.5
