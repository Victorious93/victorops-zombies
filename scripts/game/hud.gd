class_name Hud
extends CanvasLayer
## Points, round counter, ammo, prompts, hitmarkers, banners, bars, downed/game-over panel.

var game
var round_lbl: Label
var points_lbl: Label
var ammo_lbl: Label
var weapon_lbl: Label
var prompt_lbl: Label
var banner_lbl: Label
var bark_lbl: Label
var info_lbl: Label
var perks_lbl: Label
var health_bar: ProgressBar
var armor_bar: ProgressBar
var ability_lbl: Label
var vignette: ColorRect
var hit: Control
var hit_t := 0.0
var hit_kill := false
var banner_t := 0.0
var bark_t := 0.0
var dmg_t := 0.0
var over_panel: Control
var fps_lbl: Label
var hit_head := false
var hit_mark := 0
var dmg_angle := NAN
var feed_lbl: Label
var feed_t := 0.0
var streak := 0
var round_t := 0.0
var slam_lbl: Label
var pops: Array = []   ## v7.12 [{n, age, x}] points pop-ups beside the crosshair
const POP_LIFE := 0.9
func points_pop(n: int) -> void:
	pops.append({"n": n, "age": 0.0, "x": randf_range(-6.0, 6.0)})
	if pops.size() > 6: pops.pop_front()
static func pop_rise(age: float) -> float: return -60.0 * ease(clampf(age / POP_LIFE, 0.0, 1.0), 0.5)
static func pop_alpha(age: float) -> float: return clampf((POP_LIFE - age) / 0.35, 0.0, 1.0)
static func pop_color(n: int) -> Color:
	if n >= 100: return Color(1.0, 0.78, 0.2)
	if n >= 50: return Color(1.0, 0.95, 0.5)
	return Color(1.0, 1.0, 0.9)
static func pop_size(n: int) -> int: return 34 if n >= 100 else (28 if n >= 50 else 22)
var pickup_t := 0.0
var pickup_col := Color.WHITE
## v7.11 power-up grab flash: a full-screen wash in the drop's colour, fast in, eased out.
func pickup_flash(c: Color) -> void:
	pickup_t = 1.0; pickup_col = c
static func pickup_alpha(t: float) -> float: return clampf(t, 0.0, 1.0) * clampf(t, 0.0, 1.0) * 0.45
var slam_age := 99.0
const SLAM_TIME := 2.2   ## v7.10 big centre round-number slam duration
var pause_panel: Control
var touch_layout := false
var grenade_lbl: Label
var pu_lbl: Label
var stand_lbl: Label
var stamina_bar: ProgressBar
var shown_round := 0
const NEON_A := Color(0.1, 0.95, 1.0)    ## cyan
const NEON_B := Color(1.0, 0.15, 0.85)   ## magenta
var deco: Control            ## neon frame strokes + painted tally
var blood_rect: TextureRect  ## screen-space blood splatter when hurt
var blood_a := 0.0
var gas_t := 0.0
var power_t := 0.0   ## v7.9 power-on white-out flash
var shown_points := 0.0
var tick_cd := 0.0
var tut_panel: Control
var tut_lbl: Label
var gear: GearHud   ## v7.13 pak ring + backpack bar

func _lbl(size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _place(c: Control, preset: int, offset: Vector2, sz := Vector2(400, 60)) -> void:
	c.set_anchors_preset(preset)
	c.size = sz
	var anchor := Vector2(c.anchor_left, c.anchor_top)
	c.position = offset - sz * anchor
	add_child(c)

func _ready() -> void:
	vignette = ColorRect.new(); vignette.color = Color(0.6, 0, 0, 0); vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(vignette)
	blood_rect = TextureRect.new(); blood_rect.texture = _blood_screen_tex(); blood_rect.stretch_mode = TextureRect.STRETCH_SCALE
	blood_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); blood_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blood_rect.modulate.a = 0.0; add_child(blood_rect)
	deco = Control.new(); deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_deco); add_child(deco)
	# the painted tally is drawn by _draw_deco; the label only shows numbers past 10
	round_lbl = _lbl(80, NEON_B.lerp(Color.WHITE, 0.15)); _place(round_lbl, Control.PRESET_TOP_LEFT, Vector2(40, 14), Vector2(300, 110))
	round_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.12, 0.95)); round_lbl.add_theme_constant_override("outline_size", 14)
	slam_lbl = _lbl(220, Color(0.85, 0.05, 0.03), HORIZONTAL_ALIGNMENT_CENTER); slam_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slam_lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.0, 1.0)); slam_lbl.add_theme_constant_override("outline_size", 22)
	slam_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); slam_lbl.modulate.a = 0.0; add_child(slam_lbl)
	points_lbl = _lbl(42, Color(0.92, 1.0, 1.0), HORIZONTAL_ALIGNMENT_RIGHT); _place(points_lbl, Control.PRESET_TOP_RIGHT, Vector2(-30, 18))
	points_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.25, 0.35, 0.95)); points_lbl.add_theme_constant_override("outline_size", 10)
	perks_lbl = _lbl(22, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_RIGHT); _place(perks_lbl, Control.PRESET_TOP_RIGHT, Vector2(-24, 70), Vector2(500, 90))
	fps_lbl = _lbl(16, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_RIGHT); _place(fps_lbl, Control.PRESET_TOP_RIGHT, Vector2(-24, 150), Vector2(200, 30))
	ammo_lbl = _lbl(42, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT); _place(ammo_lbl, Control.PRESET_BOTTOM_RIGHT, Vector2(-430, -70))
	weapon_lbl = _lbl(22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT); _place(weapon_lbl, Control.PRESET_BOTTOM_RIGHT, Vector2(-430, -110))
	prompt_lbl = _lbl(28, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER); _place(prompt_lbl, Control.PRESET_CENTER, Vector2(0, 120), Vector2(900, 50))
	banner_lbl = _lbl(64, Color(0.85, 0.08, 0.05), HORIZONTAL_ALIGNMENT_CENTER); _place(banner_lbl, Control.PRESET_CENTER, Vector2(0, -150), Vector2(1000, 90))
	bark_lbl = _lbl(30, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER); _place(bark_lbl, Control.PRESET_CENTER, Vector2(0, -60), Vector2(900, 50))
	info_lbl = _lbl(24, Color(0.7, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER); _place(info_lbl, Control.PRESET_CENTER, Vector2(0, 170), Vector2(900, 40))
	ability_lbl = _lbl(20, Color(0.7, 0.85, 1)); _place(ability_lbl, Control.PRESET_BOTTOM_LEFT, Vector2(28, -130), Vector2(400, 30))
	health_bar = _bar(Color(0.95, 0.12, 0.35)); _place(health_bar, Control.PRESET_BOTTOM_LEFT, Vector2(28, -90), Vector2(260, 16))
	armor_bar = _bar(NEON_A); _place(armor_bar, Control.PRESET_BOTTOM_LEFT, Vector2(28, -66), Vector2(260, 12))
	armor_bar.max_value = 200
	hit = Control.new(); hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit.draw.connect(_draw_center); add_child(hit)
	feed_lbl = _lbl(26, Color(1, 0.3, 0.2), HORIZONTAL_ALIGNMENT_CENTER); _place(feed_lbl, Control.PRESET_CENTER, Vector2(0, 60), Vector2(600, 40))
	grenade_lbl = _lbl(22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT); _place(grenade_lbl, Control.PRESET_BOTTOM_RIGHT, Vector2(-430, -140))
	pu_lbl = _lbl(26, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER); _place(pu_lbl, Control.PRESET_CENTER_BOTTOM, Vector2(0, -60), Vector2(700, 40))
	stand_lbl = _lbl(40, Color(1, 0.25, 0.2), HORIZONTAL_ALIGNMENT_CENTER); _place(stand_lbl, Control.PRESET_CENTER, Vector2(0, 220), Vector2(900, 60))
	stamina_bar = _bar(Color(0.9, 0.85, 0.5)); _place(stamina_bar, Control.PRESET_BOTTOM_LEFT, Vector2(28, -50), Vector2(160, 6))
	gear = GearHud.new(); gear.game = game; add_child(gear)

## Touch screens: move bars/ammo away from the stick and button clusters.
func set_touch_layout(on: bool) -> void:
	if on == touch_layout: return
	touch_layout = on
	var vp := get_viewport().get_visible_rect().size
	var u := vp.y / 720.0
	if on:
		for pair in [[ability_lbl, Vector2(28, 118)], [health_bar, Vector2(28, 150)], [armor_bar, Vector2(28, 172)]]:
			var c: Control = pair[0]; c.set_anchors_preset(Control.PRESET_TOP_LEFT); c.position = pair[1]
		for pair in [[ammo_lbl, -70.0], [weapon_lbl, -110.0], [grenade_lbl, -140.0]]:
			var c: Control = pair[0]; c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.position = Vector2(vp.x / 2 - c.size.x / 2 + 40 * u, vp.y + pair[1])
		fps_lbl.position.y = 186
		perks_lbl.set_anchors_preset(Control.PRESET_TOP_LEFT); perks_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		perks_lbl.position = Vector2(28, 196)

func _bar(c: Color) -> ProgressBar:
	var b := ProgressBar.new(); b.show_percentage = false
	var fg := StyleBoxFlat.new(); fg.bg_color = c
	fg.corner_radius_top_right = 6; fg.corner_radius_bottom_right = 6
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.03, 0.0, 0.08, 0.6)
	bg.border_color = Color(NEON_A.r, NEON_A.g, NEON_A.b, 0.5); bg.set_border_width_all(1); bg.border_width_bottom = 2
	b.add_theme_stylebox_override("fill", fg); b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _draw_center() -> void:
	var c := hit.size / 2
	var p = game.player
	if p == null or game.over: return
	if not p.ads:
		var gap: float = 8.0 + p.weapon().spread_deg * 4.0 + p.recoil * 120.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			hit.draw_line(c + d * gap, c + d * (gap + 10), Color(1, 1, 1, 0.8), 2.0)
	else:
		hit.draw_circle(c, 2.0, Color(1, 0.3, 0.2))
	if hit_t > 0.0:
		var col := GunFeel.hitmarker_color(hit_mark); col.a = hit_t / 0.25
		var s := 1.0 + (0.4 if hit_kill else 0.0) + hit_t
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			hit.draw_line(c + d * 7 * s, c + d * 16 * s, col, 3.0 if not hit_kill else 4.0)
	# damage direction arcs: one per recent attacker, tracked in world space so they turn with you
	for ind in dmg_marks:
		var off: Vector3 = p.to_local(ind.from); off.y = 0
		if off.length() < 0.01: continue
		var ang := atan2(off.x, -off.z)
		var dir := Vector2(sin(ang), -cos(ang))
		var r := minf(hit.size.x, hit.size.y) * 0.28
		var a: float = clampf(ind.t / 0.9, 0, 1)
		var pts := PackedVector2Array()
		for i in 13:
			var aa := ang - 0.32 + 0.64 * i / 12.0
			pts.append(c + Vector2(sin(aa), -cos(aa)) * r)
		hit.draw_polyline(pts, Color(1, 0.08, 0.04, a), 9.0)
		var tip := c + dir * (r + 24); var side := dir.orthogonal() * 16
		hit.draw_colored_polygon(PackedVector2Array([tip, c + dir * (r + 6) + side, c + dir * (r + 6) - side]), Color(1, 0.1, 0.05, a))
	if power_t > 0.0:
		hit.draw_rect(Rect2(Vector2.ZERO, hit.size), Color(1.0, 0.96, 0.85, power_flash_alpha(power_t)))
	if round_t > 0.0:
		hit.draw_rect(Rect2(Vector2.ZERO, hit.size), Color(0.6, 0.0, 0.0, round_t * 0.25))
	var pf := ThemeDB.fallback_font
	for pp in pops:
		var n: int = pp.n; var a: float = pp.age
		var col := pop_color(n); col.a = pop_alpha(a)
		hit.draw_string_outline(pf, c + Vector2(46 + pp.x, -10 + pop_rise(a)), "+%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, pop_size(n), 6, Color(0, 0, 0, col.a * 0.8))
		hit.draw_string(pf, c + Vector2(46 + pp.x, -10 + pop_rise(a)), "+%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, pop_size(n), col)
	if pickup_t > 0.0:
		hit.draw_rect(Rect2(Vector2.ZERO, hit.size), Color(pickup_col.r, pickup_col.g, pickup_col.b, pickup_alpha(pickup_t)))
	var sb := slam_bar(slam_age)
	if sb > 0.0:
		var bw := hit.size.x * sb; var bh := hit.size.y * 0.035
		hit.draw_rect(Rect2(Vector2((hit.size.x - bw) / 2, c.y - hit.size.y * 0.2), Vector2(bw, bh)), Color(0.7, 0.02, 0.0, 0.8 * sb))
		hit.draw_rect(Rect2(Vector2((hit.size.x - bw) / 2, c.y + hit.size.y * 0.2 - bh), Vector2(bw, bh)), Color(0.7, 0.02, 0.0, 0.8 * sb))

func hitmarker(kill: bool, head := false, armored := false) -> void:
	hit_mark = GunFeel.hitmarker(kill, head, armored)
	if game and game.tutorial: game.tutorial.event("shoot")
	hit_t = 0.25; hit_kill = kill; hit_head = head

func kill_feed(head: bool) -> void:
	streak = streak + 1 if feed_t > 0.0 else 1
	feed_t = 1.6
	var t := "HEADSHOT" if head else "KILL"
	if streak >= 3: t += "  x%d" % streak
	feed_lbl.text = t
	feed_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if head else Color(1, 0.3, 0.2))
	feed_lbl.scale = Vector2.ONE * 1.3; feed_lbl.pivot_offset = feed_lbl.size / 2

## Round counter flips over (squash to a line, swap the number, spring back) with tally marks up to 5.
func tally_flip(r: int) -> void:
	var tw := create_tween()
	round_lbl.pivot_offset = Vector2(0, round_lbl.size.y / 2)
	tw.tween_property(round_lbl, "scale:y", 0.0, 0.25)
	tw.tween_callback(func(): shown_round = r)
	tw.tween_property(round_lbl, "scale", Vector2(1.6, 1.6), 0.2).set_trans(Tween.TRANS_BACK)
	tw.tween_property(round_lbl, "scale", Vector2.ONE, 0.6)

static func tally(r: int) -> String:
	if r <= 0: return ""
	if r <= 5: return "卌" if r == 5 else "|".repeat(r)
	return str(r)

## Rounds 1-10 are painted as tally strokes (two gates of five); past that a big neon number.
static func painted_strokes(r: int) -> int:
	return r if r <= 10 else 0

## Hand-painted look: each stroke is a tapered quad with per-round jitter, coloured cyan -> magenta.
func _draw_deco() -> void:
	var p = game.player if game else null
	if p == null or game.over: return
	var n := painted_strokes(shown_round)
	var rs := RandomNumberGenerator.new()
	var sc := round_lbl.scale.y
	for i in n:
		rs.seed = i * 977 + 13
		var grp := i / 5; var k := i % 5
		var base := Vector2(44 + grp * 120, 20)
		var col := NEON_A.lerp(NEON_B, float(i) / 9.0)
		var a: Vector2; var b: Vector2
		if k < 4:
			a = base + Vector2(k * 22 + rs.randf_range(-3, 3), rs.randf_range(0, 6))
			b = a + Vector2(rs.randf_range(-5, 5), 76 * sc)
		else:   # the gate slash
			a = base + Vector2(-10, 62 * sc); b = base + Vector2(84, 10)
		_stroke(a, b, 11.0, col, rs)
	# neon underline for points + a slim corner bracket
	var vp := deco.size
	var y := 72.0
	for j in 24:
		var t0 := j / 24.0
		deco.draw_line(Vector2(vp.x - 250 + t0 * 220, y), Vector2(vp.x - 250 + (t0 + 1.0 / 24.0) * 220, y), NEON_A.lerp(NEON_B, t0), 3.0)
	deco.draw_line(Vector2(24, 120), Vector2(24, 18), Color(NEON_A, 0.55), 2.0)
	deco.draw_line(Vector2(24, 18), Vector2(60, 18), Color(NEON_A, 0.55), 2.0)

func _stroke(a: Vector2, b: Vector2, w: float, col: Color, rs: RandomNumberGenerator) -> void:
	var d := (b - a).normalized(); var nrm := d.orthogonal()
	var pts := PackedVector2Array()
	var steps := 6
	for s2 in steps + 1:
		var t := float(s2) / steps
		var ww := w * (0.55 + 0.45 * sin(t * PI)) * rs.randf_range(0.85, 1.1)
		pts.append(a.lerp(b, t) + nrm * ww * 0.5)
	for s2 in range(steps, -1, -1):
		var t := float(s2) / steps
		var ww := w * (0.55 + 0.45 * sin(t * PI)) * rs.randf_range(0.85, 1.1)
		pts.append(a.lerp(b, t) - nrm * ww * 0.5)
	var glow := PackedVector2Array()
	for q in pts: glow.append(q + Vector2(2, 3))
	deco.draw_colored_polygon(glow, Color(0.03, 0.0, 0.08, 0.8))
	deco.draw_colored_polygon(pts, col)
	deco.draw_line(a + nrm * 1.5, b + nrm * 1.5, Color(1, 1, 1, 0.35), 2.0)   # wet highlight

func _blood_screen_tex() -> Texture2D:
	var w := 320; var h := 180
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rs := RandomNumberGenerator.new(); rs.seed = 4242
	var blobs: Array = []
	for i in 46:
		# splats hug the screen edges, more at the corners
		var side := rs.randi() % 4
		var pos := Vector2(rs.randf() * w, rs.randf() * h)
		match side:
			0: pos.x = rs.randf_range(0, w * 0.16)
			1: pos.x = w - rs.randf_range(0, w * 0.16)
			2: pos.y = rs.randf_range(0, h * 0.18)
			3: pos.y = h - rs.randf_range(0, h * 0.18)
		blobs.append([pos, rs.randf_range(4, 22)])
	var field := PackedFloat32Array(); field.resize(w * h)
	for bl in blobs:
		var c: Vector2 = bl[0]; var r: float = bl[1]
		for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 1)):
			for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 1)):
				var v := 1.0 - Vector2(x, y).distance_to(c) / r
				if v > field[y * w + x]: field[y * w + x] = v
	for y in h:
		for x in w:
			var v := field[y * w + x]
			if v > 0.0: img.set_pixel(x, y, Color(0.32 - v * 0.12, 0.0, 0.01, smoothstep(0.0, 0.25, v) * 0.92))
	return ImageTexture.create_from_image(img)

## Onboarding strip: neon-bordered prompt + SKIP button, top-centre.
func show_tutorial(on: bool) -> void:
	if on and tut_panel == null:
		tut_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.02, 0.02, 0.06, 0.78)
		sb.border_color = NEON_A; sb.set_border_width_all(2); sb.set_corner_radius_all(6); sb.content_margin_left = 18; sb.content_margin_right = 12
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		tut_panel.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 18); tut_panel.add_child(row)
		tut_lbl = _lbl(26, Color(0.85, 1.0, 1.0)); row.add_child(tut_lbl)
		var skip := Button.new(); skip.text = "SKIP ▸"; skip.add_theme_font_size_override("font_size", 22)
		skip.add_theme_color_override("font_color", NEON_B); skip.focus_mode = Control.FOCUS_NONE
		skip.pressed.connect(game.end_tutorial); row.add_child(skip)
		tut_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); tut_panel.position.y = 96
		add_child(tut_panel)
	if tut_panel: tut_panel.visible = on

func set_tutorial(text: String) -> void:
	if tut_lbl == null: return
	tut_lbl.text = text
	tut_panel.reset_size(); tut_panel.position.x = (get_viewport().get_visible_rect().size.x - tut_panel.size.x) / 2

func gas_flash() -> void:
	gas_t = 0.6

func power_flash() -> void:
	power_t = 1.0

## Quick white-out that fades; capped well below opaque so the HUD stays readable.
static func power_flash_alpha(t: float) -> float: return clampf(t, 0.0, 1.0) * clampf(t, 0.0, 1.0) * 0.55

## v7.10 round slam: the new round number crashes into the centre of the screen (big, blood red),
## shudders, holds, then rises and fades while red bars wipe across.
func round_slam(r: int) -> void:
	slam_lbl.text = str(r); slam_age = 0.0
static func slam_scale(a: float) -> float:
	if a < 0.18: return lerpf(3.2, 0.92, ease(a / 0.18, 2.4))
	if a < 0.32: return lerpf(0.92, 1.0, (a - 0.18) / 0.14)
	return 1.0 + maxf(0.0, a - 1.4) * 0.25
static func slam_alpha(a: float) -> float:
	if a < 0.0 or a >= SLAM_TIME: return 0.0
	if a < 0.12: return a / 0.12
	return clampf((SLAM_TIME - a) / 0.8, 0.0, 1.0)
static func slam_bar(a: float) -> float:  ## 0..1 width of the red wipe bars
	return clampf(a / 0.25, 0.0, 1.0) * clampf((SLAM_TIME - a) / 0.6, 0.0, 1.0)
func round_flash() -> void:
	round_t = 1.0
	round_lbl.scale = Vector2.ONE * 1.6

func show_pause(on: bool) -> void:
	if pause_panel: pause_panel.queue_free(); pause_panel = null
	if not on: return
	pause_panel = SettingsPanel.make(game.settings, func(): game.apply_settings(); Game.save_settings(game.settings),
		[["Resume", game.toggle_pause], ["Main menu", game.to_menu]])
	add_child(pause_panel)

func banner(text: String, dur := 3.0) -> void:
	banner_lbl.text = text; banner_t = dur

func bark(text: String) -> void:
	bark_lbl.text = text; bark_t = Barks.DURATION

func info(text: String) -> void:
	info_lbl.text = text; info_lbl.modulate.a = 1.0

var dmg_marks: Array = []  ## [{from: Vector3, t: float}]
var desat := 0.0

func damage_flash(angle := NAN, from := Vector3.INF) -> void:
	dmg_t = 0.5; dmg_angle = angle
	if from != Vector3.INF:
		dmg_marks.append({from = from, t = 1.2})
		if dmg_marks.size() > 4: dmg_marks.pop_front()

func _process(dt: float) -> void:
	var p = game.player
	if p == null: return
	if shown_round == 0 and game.round > 0 and round_lbl.scale.y > 0.5: shown_round = game.round
	round_lbl.text = tally(shown_round)
	# points tick up instead of jumping, with a soft tick and a little pop
	var target := float(p.economy.points)
	if absf(target - shown_points) < 0.5 or shown_points > target: shown_points = target
	else:
		var before := int(shown_points)
		shown_points = move_toward(shown_points, target, maxf(60.0, (target - shown_points) * 6.0) * dt)
		tick_cd -= dt
		if int(shown_points) != before and tick_cd <= 0.0:
			tick_cd = 0.06; points_lbl.scale = Vector2.ONE * 1.12; points_lbl.pivot_offset = points_lbl.size * Vector2(1, 0.5)
			if game.sfx: game.sfx.play("tick", -14, randf_range(0.95, 1.08))
	points_lbl.text = str(int(shown_points))
	points_lbl.scale = points_lbl.scale.lerp(Vector2.ONE, clampf(dt * 12, 0, 1))
	round_lbl.visible = painted_strokes(shown_round) == 0
	deco.queue_redraw()
	var a: Ammo = p.ammo()
	ammo_lbl.text = "RELOADING" if a.reloading() else "%d / %d" % [a.rounds, a.reserve]
	ammo_lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if a.rounds == 0 and a.reserve == 0 else (Color(1, 0.85, 0.3) if a.reserve < a.weapon.mag_size else Color.WHITE))
	var pus: Array = []
	for id in game.power.timers: pus.append("%s %s %ds" % [PowerUps.ICONS[id], PowerUps.ALL[id].name, ceili(game.power.timers[id])])
	pu_lbl.text = "    ".join(pus)
	stand_lbl.visible = p.is_downed
	if p.is_downed:
		stand_lbl.text = ("GETTING UP  %.1f" if p.last_stand.will_revive else "BLEEDING OUT  %.1f") % maxf(p.last_stand.left, 0.0)
	stamina_bar.max_value = p.STAMINA_MAX * (1.6 if p.perks.get("fleetfoot", false) else 1.0); stamina_bar.value = p.stamina
	stamina_bar.visible = stamina_bar.value < stamina_bar.max_value - 0.01
	weapon_lbl.text = p.weapon().display_name()
	var pk: Array = []
	for id in Perks.held(p.perks): pk.append(Perks.ALL[id].name)
	perks_lbl.text = "\n".join(pk)
	fps_lbl.visible = game.settings.show_fps or game.force_fps_label
	if fps_lbl.visible: fps_lbl.text = perf_text(Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	health_bar.max_value = p.max_health; health_bar.value = p.health
	armor_bar.max_value = p.armor.max_value; armor_bar.value = p.armor.value; armor_bar.visible = p.armor.value > 0
	var cd: float = p.ability_cd
	ability_lbl.text = "%s %s" % [p.cdef.ability_name, "READY [Q]" if cd <= 0 else "%ds" % ceili(cd)]
	var pr: String = game.current_prompt
	var touch_on: bool = game.touch != null and game.touch.visible
	prompt_lbl.text = "" if pr == "" else ("%s %s" % ["[USE]" if touch_on else "[E]", pr])
	hit_t = maxf(0.0, hit_t - dt)
	set_touch_layout(game.touch != null and game.touch.visible)
	feed_t -= dt; feed_lbl.visible = feed_t > 0.0
	feed_lbl.scale = feed_lbl.scale.lerp(Vector2.ONE, clampf(dt * 10, 0, 1))
	round_t = maxf(0.0, round_t - dt * 0.8)
	slam_age += dt
	for pp in pops: pp.age += dt
	pops = pops.filter(func(pp): return pp.age < POP_LIFE)
	pickup_t = maxf(0.0, pickup_t - dt * 1.6)
	var sa := slam_alpha(slam_age); slam_lbl.modulate.a = sa
	if sa > 0.0:
		slam_lbl.pivot_offset = slam_lbl.size / 2; slam_lbl.scale = Vector2.ONE * slam_scale(slam_age)
		var shake := maxf(0.0, 0.45 - slam_age) * 30.0
		slam_lbl.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake) - maxf(0.0, slam_age - 1.4) * 60.0)
	round_lbl.scale = round_lbl.scale.lerp(Vector2.ONE, clampf(dt * 3, 0, 1))
	grenade_lbl.text = "Grenades %d  ·  Knife [V]" % p.equipment.grenades if not touch_layout else "Grenades %d" % p.equipment.grenades
	banner_t -= dt; banner_lbl.visible = banner_t > 0
	bark_t -= dt; bark_lbl.visible = bark_t > 0
	info_lbl.modulate.a = maxf(0.0, info_lbl.modulate.a - dt * 0.5)
	dmg_t = maxf(0.0, dmg_t - dt)
	for m in dmg_marks: m.t -= dt
	dmg_marks = dmg_marks.filter(func(m): return m.t > 0.0)
	var low: float = 1.0 - p.health / p.max_health
	# low health: drain colour and pulse the vignette with the heartbeat
	var crit := clampf((p.health / p.max_health - 0.45) / -0.35, 0.0, 1.0) if not p.is_downed else 1.0
	desat = lerpf(desat, crit, clampf(dt * 3.0, 0, 1))
	if game.env: game.env.adjustment_saturation = lerpf(1.0, 0.2, desat)
	low += desat * 0.25 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI * 1.3))
	blood_a = maxf(blood_a - dt * 0.35, low * low * 0.8)
	if dmg_t > 0.45: blood_a = minf(1.0, blood_a + 0.35)
	blood_rect.modulate.a = blood_a
	gas_t = maxf(0.0, gas_t - dt)
	power_t = maxf(0.0, power_t - dt * 1.4)
	vignette.color = Color(0.6, 0, 0, vignette.color.a).lerp(Color(0.3, 0.6, 0.05, vignette.color.a), clampf(gas_t * 2.0, 0, 1))
	vignette.color.a = clampf(gas_t * 0.6 + dmg_t * 0.6 + low * low * 0.55 + (0.3 if p.is_downed else 0.0), 0, 0.75)
	hit.queue_redraw()

var boss_root: Control
var boss_fill: ColorRect
var boss_lbl: Label

## Boss health bar across the top while the Warden lives.
func boss_bar(z) -> void:
	if z == null:
		if boss_root: boss_root.visible = false
		return
	if boss_root == null:
		boss_root = Control.new(); boss_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		boss_root.position = Vector2(-300, 70); boss_root.size = Vector2(600, 40); add_child(boss_root)
		var bg := ColorRect.new(); bg.color = Color(0, 0, 0, 0.6); bg.position = Vector2(0, 22); bg.size = Vector2(600, 14); boss_root.add_child(bg)
		boss_fill = ColorRect.new(); boss_fill.color = Color(0.7, 0.2, 0.9); boss_fill.position = Vector2(2, 24); boss_fill.size = Vector2(596, 10); boss_root.add_child(boss_fill)
		boss_lbl = _lbl(22, Color(0.85, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER); boss_lbl.text = "THE WARDEN"; boss_lbl.size = Vector2(600, 22); boss_root.add_child(boss_lbl)
	boss_root.visible = true
	boss_fill.size.x = 596.0 * clampf(float(z.hp) / maxf(1.0, float(z.max_hp)), 0.0, 1.0)

func show_game_over(round: int, kills: int, stats: RunStats = null, best := {}, is_best := false) -> void:
	over_panel = VBoxContainer.new()
	over_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.1, 0, 0, 0.8); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var t := _lbl(72, Color(0.85, 0.08, 0.05), HORIZONTAL_ALIGNMENT_CENTER); t.text = "OVERRUN"
	over_panel.add_child(t)
	var s := _lbl(28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if stats: s.text = "\n".join(stats.lines(round))
	else: s.text = "You survived %d round%s  ·  %d kills" % [round, "" if round == 1 else "s", kills]
	over_panel.add_child(s)
	var h := _lbl(30, Color(1.0, 0.85, 0.3) if is_best else Color(0.75, 0.75, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	if is_best: h.text = "NEW HIGH SCORE!"
	elif not best.is_empty(): h.text = "Best: round %d  ·  %d kills  ·  %d points" % [best.get("round", 0), best.get("kills", 0), best.get("points", 0)]
	over_panel.add_child(h)
	var q := _lbl(22, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER); q.text = Barks.GAME_OVER; over_panel.add_child(q)
	for pair in [["Play again", game.restart], ["Main menu", game.to_menu]]:
		var b := Button.new(); b.text = pair[0]; b.custom_minimum_size = Vector2(320, 64)
		b.add_theme_font_size_override("font_size", 28); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(pair[1]); over_panel.add_child(b)
	add_child(over_panel)

## "60 fps · 142 dc": draw calls flagged once they pass the mobile budget.
static func perf_text(fps: int, draw_calls: int) -> String:
	return "%d fps · %d dc%s" % [fps, draw_calls, " !" if draw_calls > Game.DRAW_CALL_BUDGET else ""]
