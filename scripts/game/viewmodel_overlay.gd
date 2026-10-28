class_name ViewmodelOverlay
extends CanvasLayer
## Separate viewmodel pass: arms + gun live on render layer 2, which the world camera skips. A
## transparent SubViewport sharing the world renders only layer 2 with a fixed 60° FOV and its own
## fog-free environment, then composites under the HUD. Result: the gun never clips into walls and
## doesn't stretch when the world FOV kicks out for sprinting/slides.

const LAYER := 2          ## bit value of render layer 2
const FOV := 60.0
var vp: SubViewport
var vcam: Camera3D
var world_cam: Camera3D

static func to_layer(n: Node) -> void:
	if n is VisualInstance3D: (n as VisualInstance3D).layers = LAYER
	for c in n.get_children(): to_layer(c)

func setup(cam: Camera3D, env: Environment) -> void:
	world_cam = cam; layer = -1
	cam.cull_mask &= ~LAYER
	vp = SubViewport.new(); vp.transparent_bg = true; vp.own_world_3d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	vcam = Camera3D.new(); vcam.cull_mask = LAYER; vcam.fov = FOV; vcam.near = 0.01; vcam.far = 3.0
	var e := Environment.new(); e.background_mode = Environment.BG_CLEAR_COLOR
	if env:
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = env.ambient_light_color
		e.ambient_light_energy = env.ambient_light_energy * 1.6; e.tonemap_mode = env.tonemap_mode
	vcam.environment = e
	vp.add_child(vcam); vcam.current = true
	var tr := TextureRect.new(); tr.texture = vp.get_texture(); tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(tr)
	_resize()
	get_viewport().size_changed.connect(_resize)

func _resize() -> void:
	vp.size = get_viewport().get_visible_rect().size

func _process(_dt: float) -> void:
	if is_instance_valid(world_cam): vcam.global_transform = world_cam.global_transform
