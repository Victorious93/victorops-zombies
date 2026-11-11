class_name HelpPanel
extends RefCounted
## VICTOR ZOMBIES by Victorious Framework — "How to play" card (main menu and pause screen).
## One screen: the loop, the controls for the device in hand, and what every purchase does.
## The text is built from the rule tables, so prices and effects cannot drift from the game.

static func controls(touch: bool) -> Array:
	if touch:
		return [
			"MOVE — left thumb stick        LOOK — drag on the right half (FIRE also steers)",
			"FIRE / AIM — FIRE and ADS buttons        RELOAD / SWITCH — their buttons",
			"USE — the button that appears near doors, guns and machines (hold it to rebuild or crank)",
			"SPRINT, JUMP, CROUCH (slide while sprinting), KNIFE, GRENADE — thumb arc around FIRE",
			"Settings ▸ Controls… moves and resizes every button",
		]
	return [
		"MOVE — WASD / left stick        LOOK — mouse / right stick",
		"FIRE / AIM — left / right mouse, RT / LT        RELOAD — R, RB        SWITCH — 1, 2, X, wheel, Y",
		"USE / BUY — E, pad X (hold to rebuild a window or crank the generator)",
		"SPRINT — Shift, L3        JUMP — Space, A        CROUCH / SLIDE — C or Ctrl, B",
		"KNIFE — V, R3        GRENADE — G, LB        ABILITY — Q, D-pad up        GADGET — F        PAUSE — Esc, Start",
	]

static func loop_lines() -> Array:
	return [
		"Kill zombies for points: +%d per hit, +%d per kill, +%d for a headshot kill, +%d with the knife." % [Economy.HIT, Economy.KILL, Economy.KILL_CRIT, Economy.KILL_KNIFE],
		"Spend points on doors, wall weapons and ammo. Rebuild boarded windows between rounds (hold USE).",
		"OBJECTIVE: open the Back Alley (%d) and crank the generator. Power switches on the %s and the tonic machines." % [Facility.DOORS.north.cost, OverchargeForge.NAME],
		"Three districts — Diner Block, Workshop Row, Main Street — joined in two loops, so there is always a way round.",
		"Every %d rounds a BRUTE arrives: armoured, weak in its glowing head. When a red ring appears, leave it; after the slam it is winded and unarmoured." % ZombieTypes.BRUTE_EVERY,
		"Down = last stand with the sidearm for %d s. Bleed out and the match ends." % int(LastStand.BLEED_OUT),
	]

static func shop_lines() -> Array:
	var out := []
	for id in Perks.CORE:
		out.append("%s (%d) — %s" % [Perks.ALL[id].name, Perks.ALL[id].cost, Perks.ALL[id].desc])
	out.append("%s (%d) — Mk.2: double damage and magazine, faster fire and reload, new look and tracer" % [OverchargeForge.NAME, OverchargeForge.new().cost])
	out.append("Mystery Crate (%d) — a random weapon you do not already carry" % MysteryCrate.COST)
	var pu := []
	for id in PowerUps.ALL: pu.append("%s %s: %s" % [PowerUps.ICONS[id], PowerUps.ALL[id].name, PowerUps.ALL[id].desc])
	out.append("Glowing drops (walk over them; timed ones last %d s) — %s" % [int(PowerUps.DURATION), "  ·  ".join(pu)])
	return out

static func _section(box: VBoxContainer, title: String, lines: Array) -> void:
	var t := Label.new(); t.text = title; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26); t.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0)); box.add_child(t)
	var l := Label.new(); l.text = "\n".join(lines); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 19); l.add_theme_color_override("font_color", Color(0.88, 0.9, 0.92)); box.add_child(l)

## Full-screen card with a Back button that closes it.
static func make(touch: bool) -> Control:
	var root := PanelContainer.new(); root.name = "HelpPanel"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.01, 0.015, 0.03, 0.96)
	sb.content_margin_left = 40; sb.content_margin_right = 40; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	root.add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(scroll)
	var box := VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8); scroll.add_child(box)
	var t := Label.new(); t.text = "HOW TO PLAY"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40); t.add_theme_color_override("font_color", Color(0.85, 0.1, 0.06)); box.add_child(t)
	_section(box, "SURVIVE", loop_lines())
	_section(box, "CONTROLS (%s)" % ("touch" if touch else "keyboard + mouse / gamepad"), controls(touch))
	_section(box, "WHAT POINTS BUY", shop_lines())
	var b := Button.new(); b.text = "Back"; b.custom_minimum_size = Vector2(300, 60); b.add_theme_font_size_override("font_size", 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; b.pressed.connect(root.queue_free); box.add_child(b)
	return root
