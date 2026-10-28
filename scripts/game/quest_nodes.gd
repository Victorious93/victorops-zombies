class_name QuestNodes
extends Node3D
## 3D side of the v7 side-quests: the three hidden Gloam Harp parts, the workbench and the Pact Stone.
## Lives under the map (so its colliders are part of the navmesh bake); rules live in WonderQuest/PactStone.

var game
var map: FacilityMap
var part_nodes := {}
var bench_slots := {}
var bench_gun: Node3D
var rune_mat: StandardMaterial3D
var stone_light: OmniLight3D
var _t := 0.0
const TEAL := Color(0.3, 1.0, 0.85)

func build(p_game, p_map: FacilityMap) -> void:
	game = p_game; map = p_map
	var q: WonderQuest = game.quest
	for part in WonderQuest.PARTS:
		var n := Node3D.new(); n.position = q.spot(part); add_child(n)
		n.add_child(_part_mesh(part, 1.0))
		var l := OmniLight3D.new(); l.light_color = TEAL; l.light_energy = 0.6; l.omni_range = 1.6; l.shadow_enabled = false
		n.add_child(l)
		part_nodes[part] = n
		game.add_interactable(n.position, 1.6, func(_p): return "" if q.found.has(part) else "Pick up %s" % WonderQuest.PART_NAMES[part],
			func(pl): game.collect_part(pl, part))
	# workbench
	var b := Node3D.new(); b.position = WonderQuest.BENCH; add_child(b)
	map.box(Vector3(1.8, 0.9, 0.7), Vector3(0, 0.45, 0), map.mats.metal, true, 1, b)
	map.box(Vector3(1.9, 0.06, 0.8), Vector3(0, 0.93, 0), map.mats.plate, false, 1, b)
	var lb := map.label("WORKBENCH", WonderQuest.BENCH + Vector3(0, 1.75, 0.2), 0.0, 40, TEAL)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var i := 0
	for part in WonderQuest.PARTS:
		var ghost := _part_mesh(part, 0.7); ghost.position = Vector3(-0.55 + i * 0.55, 1.05, 0); ghost.visible = false
		b.add_child(ghost); bench_slots[part] = ghost; i += 1
	bench_gun = ModelLib.gun("raygun")
	bench_gun.position = Vector3(0, 1.15, 0); bench_gun.visible = false; b.add_child(bench_gun)
	game.add_interactable(WonderQuest.BENCH + Vector3(0, 0, 0.6), 1.9, func(_p): return q.prompt(), func(pl): game.use_bench(pl))
	# Pact Stone: a dark monolith with a rune strip that brightens with every step
	var s := Node3D.new(); s.position = WonderQuest.STONE; add_child(s)
	var rock := StandardMaterial3D.new(); rock.albedo_color = Color(0.12, 0.11, 0.13); rock.roughness = 1.0
	var body := map.box(Vector3(0.9, 2.2, 0.6), Vector3(0, 1.1, 0), rock, true, 1, s)
	body.rotation.y = 0.35; body.rotation.z = 0.05
	rune_mat = StandardMaterial3D.new(); rune_mat.albedo_color = Color(0.5, 0.05, 0.05)
	rune_mat.emission_enabled = true; rune_mat.emission = Color(1.0, 0.15, 0.1); rune_mat.emission_energy_multiplier = 0.2
	for k in 4:
		var r := map.box(Vector3(0.5, 0.12, 0.02), Vector3(0, 0.6 + k * 0.4, 0.31), rune_mat, false, 1, body)
		r.rotation.z = 0.25 * (1 if k % 2 == 0 else -1)
	stone_light = OmniLight3D.new(); stone_light.light_color = Color(1, 0.2, 0.1); stone_light.light_energy = 0.0
	stone_light.omni_range = 4.0; stone_light.position = Vector3(0, 1.5, 0.8); s.add_child(stone_light)
	var ls := map.label("PACT STONE", WonderQuest.STONE + Vector3(0, 2.6, 0), 0.0, 36, Color(1, 0.35, 0.3))
	ls.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	game.add_interactable(WonderQuest.STONE, 2.0, func(_p): return game.pact.prompt(), func(pl): game.use_pact(pl))

func _part_mesh(part: String, k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	match part:
		"frame": var tm := TorusMesh.new(); tm.inner_radius = 0.12 * k; tm.outer_radius = 0.2 * k; mi.mesh = tm
		"core": var sm := SphereMesh.new(); sm.radius = 0.12 * k; sm.height = 0.24 * k; mi.mesh = sm
		_: var cm := CylinderMesh.new(); cm.top_radius = 0.05 * k; cm.bottom_radius = 0.05 * k; cm.height = 0.36 * k; mi.mesh = cm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.15, 0.3, 0.3); m.metallic = 0.8
	m.emission_enabled = true; m.emission = TEAL; m.emission_energy_multiplier = 1.4
	mi.material_override = m
	return mi

func part_taken(part: String) -> void:
	if part_nodes.has(part): part_nodes[part].queue_free(); part_nodes.erase(part)
	if bench_slots.has(part): bench_slots[part].visible = true

func bench_built() -> void:
	for p in bench_slots: bench_slots[p].visible = false
	bench_gun.visible = true

func bench_taken() -> void: bench_gun.visible = false

func stone_step(step: int, sealed: bool) -> void:
	rune_mat.emission_energy_multiplier = 0.2 + step * 1.2 + (2.0 if sealed else 0.0)
	stone_light.light_energy = step * 0.6 + (1.5 if sealed else 0.0)
	if sealed: rune_mat.emission = Color(1.0, 0.75, 0.2)

func _process(dt: float) -> void:
	_t += dt
	for p in part_nodes:
		var n: Node3D = part_nodes[p]; n.rotation.y += dt * 1.5; n.position.y = game.quest.spot(p).y + sin(_t * 2.0) * 0.06
	if bench_gun and bench_gun.visible: bench_gun.rotation.y += dt
