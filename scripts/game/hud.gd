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
	round_lbl = _lbl(88, Color(0.75, 0.05, 0.03)); _place(round_lbl, Control.PRESET_TOP_LEFT, Vector2(28, 8), Vector2(300, 110))
	points_lbl = _lbl(40, Color(1, 0.92, 0.6), HORIZONTAL_ALIGNMENT_RIGHT); _place(points_lbl, Control.PRESET_TOP_RIGHT, Vector2(-24, 20))
	perks_lbl = _lbl(22, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_RIGHT); _place(perks_lbl, Control.PRESET_TOP_RIGHT, Vector2(-24, 70), Vector2(500, 90))
	fps_lbl = _lbl(16, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_RIGHT); _place(fps_lbl, Control.PRESET_TOP_RIGHT, Vector2(-24, 150), Vector2(200, 30))
	ammo_lbl = _lbl(42, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT); _place(ammo_lbl, Control.PRESET_BOTTOM_RIGHT, Vector2(-430, -70))
	weapon_lbl = _lbl(22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT); _place(weapon_lbl, Control.PRESET_BOTTOM_RIGHT, Vector2(-430, -110))
	prompt_lbl = _lbl(28, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER); _place(prompt_lbl, Control.PRESET_CENTER, Vector2(0, 120), Vector2(900, 50))
	banner_lbl = _lbl(64, Color(0.85, 0.08, 0.05), HORIZONTAL_ALIGNMENT_CENTER); _place(banner_lbl, Control.PRESET_CENTER, Vector2(0, -150), Vector2(1000, 90))
	bark_lbl = _lbl(30, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER); _place(bark_lbl, Control.PRESET_CENTER, Vector2(0, -60), Vector2(900, 50))
	info_lbl = _lbl(24, Color(0.7, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER); _place(info_lbl, Control.PRESET_CENTER, Vector2(0, 170), Vector2(900, 40))
	ability_lbl = _lbl(20, Color(0.7, 0.85, 1)); _place(ability_lbl, Control.PRESET_BOTTOM_LEFT, Vector2(28, -130), Vector2(400, 30))
	health_bar = _bar(Color(0.8, 0.1, 0.1)); _place(health_bar, Control.PRESET_BOTTOM_LEFT, Vector2(28, -90), Vector2(260, 16))
	armor_bar = _bar(Color(0.3, 0.6, 1.0)); _place(armor_bar, Control.PRESET_BOTTOM_LEFT, Vector2(28, -66), Vector2(260, 12))
	armor_bar.max_value = 200
	hit = Control.new(); hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit.draw.connect(_draw_center); add_child(hit)

func _bar(c: Color) -> ProgressBar:
	var b := ProgressBar.new(); b.show_percentage = false
	var fg := StyleBoxFlat.new(); fg.bg_color = c
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.5)
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
		var col := Color(1, 0.15, 0.1, hit_t / 0.25) if hit_kill else Color(1, 1, 1, hit_t / 0.25)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			hit.draw_line(c + d * 7, c + d * 16, col, 3.0)

func hitmarker(kill: bool) -> void:
	hit_t = 0.25; hit_kill = kill

func banner(text: String, dur := 3.0) -> void:
	banner_lbl.text = text; banner_t = dur

func bark(text: String) -> void:
	bark_lbl.text = text; bark_t = Barks.DURATION

func info(text: String) -> void:
	info_lbl.text = text; info_lbl.modulate.a = 1.0

func damage_flash() -> void:
	dmg_t = 0.5

func _process(dt: float) -> void:
	var p = game.player
	if p == null: return
	round_lbl.text = str(game.round) if game.round > 0 else ""
	points_lbl.text = str(p.economy.points)
	var a: Ammo = p.ammo()
	ammo_lbl.text = "RELOADING" if a.reloading() else "%d / ∞" % a.rounds
	weapon_lbl.text = p.weapon().display_name()
	var pk: Array = []
	for id in p.perks: pk.append(Perks.ALL[id].name)
	perks_lbl.text = "\n".join(pk)
	fps_lbl.text = "%d fps" % Engine.get_frames_per_second()
	health_bar.max_value = p.max_health; health_bar.value = p.health
	armor_bar.value = p.armor.value; armor_bar.visible = p.armor.value > 0
	var cd: float = p.ability_cd
	ability_lbl.text = "%s %s" % [p.cdef.ability_name, "READY [Q]" if cd <= 0 else "%ds" % ceili(cd)]
	var pr: String = game.current_prompt
	var touch_on: bool = game.touch != null and game.touch.visible
	prompt_lbl.text = "" if pr == "" else ("%s %s" % ["[USE]" if touch_on else "[E]", pr])
	hit_t = maxf(0.0, hit_t - dt)
	banner_t -= dt; banner_lbl.visible = banner_t > 0
	bark_t -= dt; bark_lbl.visible = bark_t > 0
	info_lbl.modulate.a = maxf(0.0, info_lbl.modulate.a - dt * 0.5)
	dmg_t = maxf(0.0, dmg_t - dt)
	var low: float = 1.0 - p.health / p.max_health
	vignette.color.a = clampf(dmg_t * 0.6 + low * 0.35, 0, 0.7)
	hit.queue_redraw()

func show_game_over(round: int, kills: int) -> void:
	over_panel = VBoxContainer.new()
	over_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.1, 0, 0, 0.75); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var t := _lbl(72, Color(0.85, 0.08, 0.05), HORIZONTAL_ALIGNMENT_CENTER); t.text = "OVERRUN"
	var s := _lbl(32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	s.text = "You survived %d round%s  ·  %d kills\n%s" % [round, "" if round == 1 else "s", kills, Barks.GAME_OVER]
	over_panel.add_child(t); over_panel.add_child(s)
	for pair in [["Play again", game.restart], ["Main menu", game.to_menu]]:
		var b := Button.new(); b.text = pair[0]; b.custom_minimum_size = Vector2(320, 70)
		b.add_theme_font_size_override("font_size", 30); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(pair[1]); over_panel.add_child(b)
	add_child(over_panel)
