class_name SettingsPanel
extends RefCounted
## Builds the settings UI (sensitivity, graphics preset, aim assist, music/SFX volume) used by
## the main menu and the in-game pause screen. on_change is called after every edit.

static func _row(box: VBoxContainer, title: String) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new(); l.text = title; l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", 24); h.add_child(l)
	box.add_child(h); return h

static func _slider(h: HBoxContainer, lo: float, hi: float, v: float, step: float, cb: Callable) -> void:
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = step; s.value = v
	s.custom_minimum_size = Vector2(320, 48)
	var val := Label.new(); val.text = "%.2f" % v; val.custom_minimum_size = Vector2(70, 0)
	val.add_theme_font_size_override("font_size", 22)
	s.value_changed.connect(func(x): val.text = "%.2f" % x; cb.call(x))
	h.add_child(s); h.add_child(val)

static func make(st: GameSettings, on_change: Callable, buttons: Array = []) -> Control:
	var root := PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.02, 0.03, 0.82); root.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14); root.add_child(box)
	var t := Label.new(); t.text = "SETTINGS"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44); t.add_theme_color_override("font_color", Color(0.85, 0.1, 0.06)); box.add_child(t)
	_slider(_row(box, "Look sensitivity"), 0.2, 3.0, st.sensitivity, 0.05, func(x): st.set_sensitivity(x); on_change.call())
	var gh := _row(box, "Graphics")
	var grp := ButtonGroup.new()
	for id in GameSettings.ORDER:
		var b := Button.new(); b.toggle_mode = true; b.button_group = grp; b.text = id.capitalize()
		b.custom_minimum_size = Vector2(130, 52); b.add_theme_font_size_override("font_size", 22)
		b.button_pressed = st.preset == id
		b.tooltip_text = GameSettings.PRESETS[id].label
		b.pressed.connect(func(): st.set_preset(id); on_change.call())
		gh.add_child(b)
	var ah := _row(box, "Aim assist (touch)")
	var cb := CheckButton.new(); cb.button_pressed = st.aim_assist; cb.custom_minimum_size = Vector2(80, 48)
	cb.toggled.connect(func(on): st.aim_assist = on; on_change.call()); ah.add_child(cb)
	_slider(_row(box, "Music"), 0.0, 1.0, st.music, 0.05, func(x): st.music = x; on_change.call())
	_slider(_row(box, "Effects"), 0.0, 1.0, st.sfx, 0.05, func(x): st.sfx = x; on_change.call())
	for pair in buttons:
		var b := Button.new(); b.text = pair[0]; b.custom_minimum_size = Vector2(320, 64)
		b.add_theme_font_size_override("font_size", 28); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(pair[1]); box.add_child(b)
	return root
