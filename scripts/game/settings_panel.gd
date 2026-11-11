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

static func _choice(h: HBoxContainer, opts: Array, cur: String, cb: Callable) -> void:
	var grp := ButtonGroup.new()
	for o in opts:
		var b := Button.new(); b.toggle_mode = true; b.button_group = grp; b.text = String(o).capitalize()
		b.custom_minimum_size = Vector2(120, 48); b.add_theme_font_size_override("font_size", 22)
		b.button_pressed = cur == o
		b.pressed.connect(func(): cb.call(o))
		h.add_child(b)

## [title] heads the panel; [status] lines (pause screen: objective, weapons, tonics, timed effects)
## are listed above the settings. Action buttons sit directly under the status so Resume is always
## reachable without scrolling.
static func make(st: GameSettings, on_change: Callable, buttons: Array = [], title := "SETTINGS", status: Array = []) -> Control:
	var root := PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.02, 0.03, 0.82); root.add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10); scroll.add_child(box)
	var t := Label.new(); t.text = title; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44); t.add_theme_color_override("font_color", Color(0.85, 0.1, 0.06)); box.add_child(t)
	if not status.is_empty():
		var sl := Label.new(); sl.name = "Status"; sl.text = "\n".join(status); sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.add_theme_font_size_override("font_size", 20); sl.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0)); box.add_child(sl)
	if not buttons.is_empty():
		var brow := HFlowContainer.new(); brow.name = "Actions"; brow.alignment = FlowContainer.ALIGNMENT_CENTER
		brow.add_theme_constant_override("h_separation", 14); brow.add_theme_constant_override("v_separation", 10); box.add_child(brow)
		for pair in buttons:
			var b := Button.new(); b.text = pair[0]; b.custom_minimum_size = Vector2(230, 60)
			b.add_theme_font_size_override("font_size", 26)
			b.pressed.connect(pair[1]); brow.add_child(b)
		var st_t := Label.new(); st_t.text = "SETTINGS"; st_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_t.add_theme_font_size_override("font_size", 28); st_t.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0)); box.add_child(st_t)
	_slider(_row(box, "Look sensitivity"), 0.2, 3.0, st.sensitivity, 0.05, func(x): st.set_sensitivity(x); on_change.call())
	_slider(_row(box, "Camera shake"), 0.0, 1.5, st.shake, 0.05, func(x): st.shake = clampf(x, 0.0, 1.5); on_change.call())
	var ih := _row(box, "Invert vertical look")
	var ic := CheckButton.new(); ic.button_pressed = st.invert_y; ic.custom_minimum_size = Vector2(80, 48)
	ic.toggled.connect(func(on): st.invert_y = on; on_change.call()); ih.add_child(ic)
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
	var fh := _row(box, "Show FPS counter")
	var fc := CheckButton.new(); fc.button_pressed = st.show_fps; fc.custom_minimum_size = Vector2(80, 48)
	fc.toggled.connect(func(on): st.show_fps = on; on_change.call()); fh.add_child(fc)
	var afh := _row(box, "Auto-fire on target")
	var af := CheckButton.new(); af.button_pressed = st.auto_fire; af.custom_minimum_size = Vector2(80, 48)
	af.toggled.connect(func(on): st.auto_fire = on; on_change.call()); afh.add_child(af)
	_choice(_row(box, "Gyro aim"), GameSettings.GYRO_MODES, st.gyro, func(v): st.gyro = v; on_change.call())
	_choice(_row(box, "Joystick"), ["floating", "fixed"], st.joystick, func(v): st.joystick = v; on_change.call())
	_slider(_row(box, "Look curve"), 1.0, 1.8, st.look_curve, 0.05, func(x): st.look_curve = x; on_change.call())
	_slider(_row(box, "Fire button size"), 1.0, 1.8, st.fire_size, 0.05, func(x): st.fire_size = x; on_change.call())
	var ch := _row(box, "Touch controls")
	var cbt := Button.new(); cbt.text = "Controls…"; cbt.custom_minimum_size = Vector2(220, 52); cbt.add_theme_font_size_override("font_size", 22)
	cbt.pressed.connect(func(): ControlsEditor.open(root, st, on_change)); ch.add_child(cbt)
	var bth := _row(box, "Rap beats (music)")
	var bt := CheckButton.new(); bt.button_pressed = st.beats; bt.custom_minimum_size = Vector2(80, 48)
	bt.toggled.connect(func(on): st.beats = on; on_change.call()); bth.add_child(bt)
	_slider(_row(box, "Music"), 0.0, 1.0, st.music, 0.05, func(x): st.music = x; on_change.call())
	_slider(_row(box, "Effects"), 0.0, 1.0, st.sfx, 0.05, func(x): st.sfx = x; on_change.call())
	return root
