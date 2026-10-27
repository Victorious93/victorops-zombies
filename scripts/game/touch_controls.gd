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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var s := size
	var u := s.y / 720.0
	buttons = {
		"fire": [Vector2(s.x - 150 * u, s.y - 200 * u), 85 * u, "FIRE"],
		"ads": [Vector2(s.x - 300 * u, s.y - 110 * u), 55 * u, "AIM"],
		"reload": [Vector2(s.x - 290 * u, s.y - 260 * u), 50 * u, "RLD"],
		"use": [Vector2(s.x - 150 * u, s.y - 380 * u), 55 * u, "USE"],
		"swap": [Vector2(s.x - 60 * u, s.y - 330 * u), 45 * u, "SWAP"],
		"skill": [Vector2(s.x - 290 * u, s.y - 400 * u), 45 * u, "SKILL"],
		"sprint": [Vector2(250 * u, s.y - 320 * u), 45 * u, "RUN"],
	}
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
					"reload", "swap", "skill": _pulses[b] = true
				if b == "fire": look_idx = e.index  # fire button also steers aim while held
			elif e.position.x < size.x * 0.4 and stick_idx == -1:
				stick_idx = e.index; stick_origin = e.position; stick_pos = e.position
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
			var r := 90.0 * size.y / 720.0
			move = ((stick_pos - stick_origin) / r).limit_length(1.0)
			if move.y < -0.9 and not sprint: pass
			queue_redraw()
		elif e.index == look_idx:
			_look += e.relative

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
		var home := Vector2(180, size.y - 160) * Vector2(size.y / 720.0, 1.0)
		home = Vector2(180 * size.y / 720.0, size.y - 160 * size.y / 720.0)
		draw_arc(home, r, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0)
