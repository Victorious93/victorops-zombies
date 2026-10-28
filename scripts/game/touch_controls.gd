class_name TouchControls
extends Control
## Mobile twin-stick: floating move stick on the left, swipe-to-look on the right, action buttons.

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
var buttons := {}  # name -> [center, radius, label]

var floating := true     ## floating stick appears under the thumb; fixed stays at home
var fire_scale := 1.3

func stick_home() -> Vector2:
	return Vector2(180 * size.y / 720.0, size.y - 160 * size.y / 720.0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	# thumb-arc layout around FIRE (see TouchLayout; tested for overlaps on common screens)
	buttons = TouchLayout.buttons(size, fire_scale)
	queue_redraw()

func consume_look() -> Vector2:
	var l := _look; _look = Vector2.ZERO; return l

func take(name: String) -> bool:
	var v: bool = _pulses.get(name, false); _pulses[name] = false; return v

func _button_at(p: Vector2) -> String:
	for n in buttons:
		if p.distance_to(buttons[n][0]) <= buttons[n][1] * 1.15: return n
	return ""

func _input(e: InputEvent) -> void:
	if not visible: return
	if e is InputEventScreenTouch:
		if e.pressed:
			var b := _button_at(e.position)
			if b != "":
				held[e.index] = b
				match b:
					"ads": ads = not ads
					"sprint": sprint = not sprint
					"reload", "swap", "skill", "knife", "grenade": _pulses[b] = true
					"pause": _pulses[b] = true
				if b == "fire": look_idx = e.index  # fire button also steers aim while held
			elif e.position.x < size.x * 0.4 and stick_idx == -1:
				stick_idx = e.index; stick_origin = e.position if floating else stick_home(); stick_pos = e.position
				if not floating: _set_move()
			elif look_idx == -1:
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

func _set_move() -> void:
	var r := 90.0 * size.y / 720.0
	move = AimAssist.stick(((stick_pos - stick_origin) / r).limit_length(1.0))

func _update_held() -> void:
	fire = held.values().has("fire")
	use = held.values().has("use")

func _draw() -> void:
	if size.y < 50: return
	var font := get_theme_default_font()
	for n in buttons:
		var b: Array = buttons[n]
		var active: bool = held.values().has(n) or (n == "ads" and ads) or (n == "sprint" and sprint)
		draw_circle(b[0], b[1], Color(1, 1, 1, 0.28 if active else 0.12))
		draw_arc(b[0], b[1], 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		var fs := int(b[1] * 0.38)
		var w := font.get_string_size(b[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, b[0] + Vector2(-w / 2, fs * 0.35), b[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))
	var r := 90.0 * size.y / 720.0
	if stick_idx != -1:
		draw_circle(stick_origin, r, Color(1, 1, 1, 0.1))
		draw_circle(stick_origin + move * r, r * 0.4, Color(1, 1, 1, 0.35))
	else:
		var home := stick_home()
		draw_arc(home, r, 0, TAU, 40, Color(1, 1, 1, 0.25 if floating else 0.4), 2.0)
		if not floating: draw_circle(home, r * 0.4, Color(1, 1, 1, 0.2))
