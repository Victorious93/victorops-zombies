class_name WindowBarricade
extends Node3D
## Visual + state for one boarded window. Local X runs along the wall, local +Z points outside.

var id := ""
var area := ""
var bar := Barricade.new()
var width := 1.6
var planks: Array = []
var inside_point: Vector3
var outside_point: Vector3
var spawn_point: Vector3

func build(p_width: float) -> void:
	width = p_width
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14); wood.roughness = 0.9
	for i in bar.max_planks:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(width + 0.35, 0.15, 0.06)
		mi.mesh = bm; mi.material_override = wood
		mi.position = Vector3(0, 1.12 + i * 0.18, 0.16 + (i % 2) * 0.04)
		mi.rotation.z = randf_range(-0.18, 0.18)
		add_child(mi); planks.append(mi)
	inside_point = to_global(Vector3(0, 0, -1.0))
	outside_point = to_global(Vector3(0, 0, 1.1))
	spawn_point = to_global(Vector3(randf_range(-2, 2), 0, 7.0))
	refresh()

func refresh() -> void:
	var n := bar.planks()
	for i in planks.size():
		planks[i].visible = i < n

func center() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)

## Zombie rips the top plank: a loose copy is yanked outward, spins, drops and fades.
func rip_plank() -> void:
	var n := bar.planks()  # planks left before this rip
	if n <= 0 or n > planks.size(): refresh(); return
	var src: MeshInstance3D = planks[n - 1]
	var loose := MeshInstance3D.new(); loose.mesh = src.mesh; loose.material_override = src.material_override
	add_child(loose); loose.transform = src.transform
	var out := src.position + Vector3(randf_range(-0.4, 0.4), 0.25, 0.9)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(loose, "position", out, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(loose, "rotation", Vector3(randf_range(-1, 1), randf_range(-1.5, 1.5), randf_range(-2, 2)), 0.7)
	tw.chain().tween_property(loose, "position", Vector3(out.x, 0.05, out.z + 0.6), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_interval(2.5)
	tw.chain().tween_callback(loose.queue_free)
