class_name TouchControls
extends Control
## v7 mobile HUD: floating move stick anywhere on the left half, drag-to-look on the right half,
## a large FIRE bottom-right (optional second FIRE on the left), and ADS / reload / jump / crouch /
## grenade / swap / knife / skill on a thumb arc around it (see TouchLayout). The buy/interact
## button only appears when something usable is in reach. Buttons are semi-transparent neon
## icon discs (original vector art, no text), sized/faded from Settings > Controls, and laid out
## inside the device safe area. [member edit_mode] turns the layer into the drag-to-customize editor.

signal layout_edited(name: String, frac: Vector2)

var move := Vector2.ZERO
var fire := false
var ads := false
var use := false
var sprint := false
var _look := Vector2.ZERO
var _pulses := {}
var stick_idx := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var look_idx := -1
var held := {}  # touch index -> button name
var buttons := {}  # name -> [center, radius]

var floating := true     ## floating stick appears under the thumb; fixed stays at home
var fire_scale := 1.3
var button_scale := 1.0
var opacity := 0.6
var left_fire := false
var custom := {}         ## name -> Vector2 fraction of the safe rect (layout editor)
var use_available := true   ## set by the game each frame: a buyable/interactable is in reach
var safe_override := Rect2() ## screenshots/tests: simulated notch + gesture bar (screen px)
var edit_mode := false
var _drag := ""
var _drag_idx := -1

const NEON := Color(0.25, 0.95, 1.0)
const NEON_FIRE := Color(1.0, 0.3, 0.38)
const NEON_USE := Color(0.45, 1.0, 0.5)

func stick_home() -> Vector2:
	var sf := safe_rect()
	return Vector2(sf.position.x + 190 * size.y / 720.0, sf.end.y - 170 * size.y / 720.0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

## Device safe area (notch / rounded corners / gesture bar) in this control's coordinates.
func safe_rect() -> Rect2:
	if safe_override.size != Vector2.ZERO: return safe_override
	var full := Rect2(Vector2.ZERO, size)
	if not is_inside_tree(): return full
	var ws := Vector2(DisplayServer.window_get_size())
	var sa := Rect2(DisplayServer.get_display_safe_area())
	if ws.x <= 0 or sa.size.x <= 0: return full
	var k := size / ws
	var r := Rect2(sa.position * k, sa.size * k).intersection(full)
	return r if r.size.x > size.x * 0.5 else full

func _layout() -> void:
	buttons = TouchLayout.buttons(size, safe_rect(), button_scale, fire_scale, left_fire, custom)
	queue_redraw()

func consume_look() -> Vector2:
	var l := _look; _look = Vector2.ZERO; return l

func take(name: String) -> bool:
	var v: bool = _pulses.get(name, false); _pulses[name] = false; return v

func _shown(n: String) -> bool:
	return n != "use" or use_available or edit_mode

func _button_at(p: Vector2) -> String:
	var best := ""; var bd := INF
	for n in buttons:
		if not _shown(n): continue
		var d: float = p.distance_to(buttons[n][0])
		if d <= buttons[n][1] * TouchLayout.HIT_PAD and d < bd: best = n; bd = d
	return best

func set_use_available(on: bool) -> void:
	if on != use_available: use_available = on; queue_redraw()

func _input(e: InputEvent) -> void:
	if not visible: return
	if edit_mode: _edit_input(e); return
	if e is InputEventScreenTouch:
		if e.pressed:
			var b := _button_at(e.position)
			if b != "":
				held[e.index] = b
				match b:
					"ads": ads = not ads
					"sprint": sprint = not sprint
					"reload", "swap", "skill", "knife", "grenade", "gadget", "jump", "crouch", "pause": _pulses[b] = true
				if b == "fire" or b == "fire_l": look_idx = e.index if look_idx == -1 else look_idx  # fire also steers aim while held
			elif e.position.x < size.x * 0.5 and stick_idx == -1:
				stick_idx = e.index; stick_origin = e.position if floating else stick_home(); stick_pos = e.position
				if not floating: _set_move()
			elif e.position.x >= size.x * 0.5 and look_idx == -1:
				look_idx = e.index
		else:
			if e.index == stick_idx:
				stick_idx = -1; move = Vector2.ZERO
			if e.index == look_idx: look_idx = -1
			held.erase(e.index)
		_update_held()
		queue_redraw()
	elif e is InputEventScreenDrag:
		if e.index == stick_idx:
			stick_pos = e.position
			_set_move()
			queue_redraw()
		elif e.index == look_idx:
			_look += e.relative

## Layout editor: drag a button; drops that would overlap another button or leave the safe area snap back.
func _edit_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO; var idx := 0; var pressed := false; var drag := false
	if e is InputEventScreenTouch: pos = e.position; idx = e.index; pressed = e.pressed
	elif e is InputEventScreenDrag: pos = e.position; idx = e.index; drag = true
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: pos = e.position; pressed = e.pressed
	elif e is InputEventMouseMotion and _drag != "" and _drag_idx == 0: pos = e.position; drag = true
	else: return
	if drag:
		if _drag != "" and idx == _drag_idx:
			buttons[_drag][0] = pos; queue_redraw()
		return
	if pressed:
		_drag = _button_at(pos); _drag_idx = idx
		if _drag != "": set_meta("drag_from", buttons[_drag][0])
	elif _drag != "":
		var sf := safe_rect()
		var r: float = buttons[_drag][1] * TouchLayout.HIT_PAD
		var inside := sf.grow(-r).has_point(pos)
		if inside and TouchLayout.can_place(buttons, _drag, pos):
			var frac := (pos - sf.position) / sf.size
			custom[_drag] = frac; layout_edited.emit(_drag, frac)
		else:
			buttons[_drag][0] = get_meta("drag_from")
		_drag = ""; _layout()

func _set_move() -> void:
	var r := 90.0 * size.y / 720.0
	move = AimAssist.stick(((stick_pos - stick_origin) / r).limit_length(1.0))

func _update_held() -> void:
	fire = held.values().has("fire") or held.values().has("fire_l")
	use = held.values().has("use")

# ---------------------------------------------------------------- drawing (original neon icon set)
func _draw() -> void:
	if size.y < 50: return
	for n in buttons:
		if not _shown(n): continue
		var b: Array = buttons[n]
		var active: bool = held.values().has(n) or (n == "ads" and ads) or (n == "sprint" and sprint) or n == _drag
		var col := NEON_FIRE if n.begins_with("fire") else (NEON_USE if n == "use" else NEON)
		_disc(b[0], b[1], col, active)
		_icon(n, b[0], b[1] * 0.5, Color(col, clampf(opacity * 1.5, 0.3, 1.0)))
	var r := 90.0 * size.y / 720.0
	var a := opacity
	if stick_idx != -1:
		draw_circle(stick_origin, r, Color(0, 0, 0, 0.18 * a))
		draw_arc(stick_origin, r, 0, TAU, 48, Color(NEON, 0.5 * a), 2.5, true)
		draw_circle(stick_origin + move * r, r * 0.42, Color(NEON, 0.35 * a))
	else:
		var home := stick_home()
		draw_arc(home, r, 0, TAU, 48, Color(NEON, (0.22 if floating else 0.4) * a), 2.0, true)
		if not floating: draw_circle(home, r * 0.42, Color(NEON, 0.2 * a))
	if edit_mode:
		var sf := safe_rect()
		draw_rect(sf, Color(1, 0.8, 0.2, 0.6), false, 2.0)

func _disc(c: Vector2, r: float, col: Color, active: bool) -> void:
	var a := opacity
	draw_circle(c, r, Color(0.02, 0.04, 0.06, (0.45 if active else 0.28) * a))
	if active: draw_circle(c, r, Color(col, 0.22 * a))
	draw_arc(c, r + 2.0, 0, TAU, 56, Color(col, 0.18 * a), 6.0, true)     # soft glow
	draw_arc(c, r, 0, TAU, 56, Color(col, 0.85 * a), 2.2, true)

func _ln(pts: PackedVector2Array, c: Vector2, s: float, col: Color, w := 2.6) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(c + v * s)
	draw_polyline(p, Color(col, col.a * 0.3), w * 2.6, true)
	draw_polyline(p, col, w, true)

func _icon(n: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.09)
	match n:
		"fire", "fire_l":   # bullet
			_ln(PackedVector2Array([Vector2(-0.25, 0.7), Vector2(-0.25, -0.2), Vector2(0, -0.7), Vector2(0.25, -0.2), Vector2(0.25, 0.7), Vector2(-0.25, 0.7)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.25, 0.35), Vector2(0.25, 0.35)]), c, s, col, w)
		"ads":   # scope reticle
			draw_arc(c, s * 0.6, 0, TAU, 32, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_ln(PackedVector2Array([d * 0.25, d * 0.85]), c, s, col, w)
		"reload":   # circular arrow
			draw_arc(c, s * 0.55, -PI * 0.35, PI * 1.35, 28, col, w, true)
			_ln(PackedVector2Array([Vector2(0.2, -0.75), Vector2(0.5, -0.5), Vector2(0.18, -0.25)]), c, s, col, w)
		"jump":   # chevrons up
			_ln(PackedVector2Array([Vector2(-0.5, 0.05), Vector2(0, -0.45), Vector2(0.5, 0.05)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.5, 0.5), Vector2(0, 0.0), Vector2(0.5, 0.5)]), c, s, col, w)
		"crouch":   # chevron down onto a bar
			_ln(PackedVector2Array([Vector2(-0.5, -0.4), Vector2(0, 0.1), Vector2(0.5, -0.4)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.55, 0.5), Vector2(0.55, 0.5)]), c, s, col, w)
		"grenade":   # body + lever + pin ring
			draw_arc(c + Vector2(0, 0.15) * s, s * 0.45, 0, TAU, 24, col, w, true)
			_ln(PackedVector2Array([Vector2(-0.15, -0.3), Vector2(-0.15, -0.55), Vector2(0.35, -0.55), Vector2(0.45, -0.3)]), c, s, col, w)
			draw_arc(c + Vector2(-0.4, -0.6) * s, s * 0.15, 0, TAU, 12, col, w * 0.8, true)
		"swap":   # two opposed arrows
			_ln(PackedVector2Array([Vector2(-0.6, -0.25), Vector2(0.55, -0.25), Vector2(0.3, -0.5)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(0.6, 0.25), Vector2(-0.55, 0.25), Vector2(-0.3, 0.5)]), c, s, col, w)
		"knife":   # blade
			_ln(PackedVector2Array([Vector2(-0.6, 0.6), Vector2(-0.3, 0.3), Vector2(0.55, -0.6), Vector2(0.15, 0.05), Vector2(-0.3, 0.3)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.5, 0.15), Vector2(-0.15, 0.5)]), c, s, col, w)
		"gadget":   # backpack: bag body + flap
			_ln(PackedVector2Array([Vector2(-0.5, -0.2), Vector2(0.5, -0.2), Vector2(0.5, 0.6), Vector2(-0.5, 0.6), Vector2(-0.5, -0.2)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.25, -0.2), Vector2(-0.25, -0.5), Vector2(0.25, -0.5), Vector2(0.25, -0.2)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(-0.5, 0.15), Vector2(0.5, 0.15)]), c, s, col, w)
		"skill":   # lightning bolt
			_ln(PackedVector2Array([Vector2(0.15, -0.75), Vector2(-0.35, 0.1), Vector2(0.05, 0.1), Vector2(-0.15, 0.75), Vector2(0.4, -0.15), Vector2(0.0, -0.15), Vector2(0.15, -0.75)]), c, s, col, w)
		"use":   # hand / grab
			_ln(PackedVector2Array([Vector2(-0.45, 0.0), Vector2(-0.45, 0.45), Vector2(-0.1, 0.7), Vector2(0.35, 0.7), Vector2(0.5, 0.3), Vector2(0.5, -0.3)]), c, s, col, w)
			for x in [-0.25, 0.0, 0.25]:
				_ln(PackedVector2Array([Vector2(x, 0.15), Vector2(x, -0.55)]), c, s, col, w)
		"sprint":   # double chevron forward
			_ln(PackedVector2Array([Vector2(-0.5, 0.35), Vector2(-0.1, -0.1), Vector2(-0.5, -0.55)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(0.0, 0.55), Vector2(0.45, 0.05), Vector2(0.0, -0.45)]), c, s, col, w)
		"pause":
			_ln(PackedVector2Array([Vector2(-0.25, -0.5), Vector2(-0.25, 0.5)]), c, s, col, w)
			_ln(PackedVector2Array([Vector2(0.25, -0.5), Vector2(0.25, 0.5)]), c, s, col, w)
