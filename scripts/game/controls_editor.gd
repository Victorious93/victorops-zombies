class_name ControlsEditor
extends Control
## Settings > Controls: button size / opacity / FIRE size sliders, left-FIRE toggle, and a live
## drag-to-customize copy of the touch HUD. Every change is written to GameSettings and saved
## locally via on_change (user://settings). Reset restores the default thumb-arc layout.

var st: GameSettings
var on_change: Callable
var preview: TouchControls

static func open(parent: Node, settings: GameSettings, changed: Callable) -> ControlsEditor:
	var e := ControlsEditor.new(); e.st = settings; e.on_change = changed
	parent.add_child(e); return e

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.05, 0.08, 0.92); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	preview = TouchControls.new(); preview.edit_mode = true; add_child(preview)
	preview.layout_edited.connect(func(n, f): st.layout[n] = f; on_change.call())
	var top := VBoxContainer.new(); top.position = Vector2(0, 0)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override("separation", 4); add_child(top)
	var t := Label.new(); t.text = "CONTROLS  ·  drag any button to move it"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26); t.add_theme_color_override("font_color", TouchControls.NEON); top.add_child(t)
	_slider(top, "Button size", 0.7, 1.4, st.button_scale, func(x): st.button_scale = x)
	_slider(top, "Opacity", 0.15, 1.0, st.button_opacity, func(x): st.button_opacity = x)
	_slider(top, "Fire button size", 1.0, 1.8, st.fire_size, func(x): st.fire_size = x)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 14); top.add_child(row)
	var lf := CheckButton.new(); lf.text = "Left FIRE"; lf.button_pressed = st.left_fire; lf.add_theme_font_size_override("font_size", 20)
	lf.toggled.connect(func(on): st.left_fire = on; _apply()); row.add_child(lf)
	for pair in [["Reset layout", func(): st.layout = {}; _apply()], ["Done", func(): queue_free()]]:
		var b := Button.new(); b.text = pair[0]; b.custom_minimum_size = Vector2(170, 46); b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(pair[1]); row.add_child(b)
	_apply.call_deferred()

func _slider(box: VBoxContainer, title: String, lo: float, hi: float, v: float, cb: Callable) -> void:
	var h := HBoxContainer.new(); h.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(h)
	var l := Label.new(); l.text = title; l.custom_minimum_size = Vector2(200, 0); l.add_theme_font_size_override("font_size", 20); h.add_child(l)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = 0.05; s.value = v; s.custom_minimum_size = Vector2(300, 36)
	s.value_changed.connect(func(x): cb.call(x); _apply()); h.add_child(s)

func _apply() -> void:
	preview.button_scale = st.button_scale; preview.opacity = st.button_opacity; preview.fire_scale = st.fire_size
	preview.left_fire = st.left_fire; preview.custom = st.layout.duplicate(); preview._layout()
	on_change.call()
