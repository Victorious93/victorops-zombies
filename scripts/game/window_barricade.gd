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
