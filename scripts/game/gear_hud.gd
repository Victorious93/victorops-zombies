class_name GearHud
extends Control
## v7.13 HUD for Upgrade Paks and the Backpack.
## Pak: icon inside a countdown ring (fraction of CAP, so kills visibly grow it), seconds left,
## floating "+1.5s" pops on each extension and a red pulse in the last WARN seconds.
## Backpack: SLOTS small squares with gadget glyph and stack count; the selected one is outlined.

var game
var pops: Array = []     ## [{text, age}]
var grow := 0.0          ## ring "swell" after an extension
var shown_frac := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE

func extended(add: float) -> void:
	pops.append({text = "+%.1fs" % add, age = 0.0}); grow = 1.0

func _process(dt: float) -> void:
	for p in pops: p.age += dt
	pops = pops.filter(func(p): return p.age < 1.1)
	grow = maxf(0.0, grow - dt * 3.0)
	if game and game.paks.active(): shown_frac = lerpf(shown_frac, game.paks.time_left / UpgradePaks.CAP, clampf(dt * 8.0, 0, 1))
	queue_redraw()

func pak_center() -> Vector2: return Vector2(84, size.y - 250)
func bag_origin() -> Vector2: return Vector2(size.x * 0.5 - 96, size.y - 205)

func _draw() -> void:
	if game == null: return
	var f := get_theme_default_font()
	var pk: UpgradePaks = game.paks
	if pk.active():
		var d: Dictionary = UpgradePaks.ALL[pk.id]
		var c := pak_center(); var r := 42.0 + grow * 8.0
		var col: Color = d.color
		if pk.warning() and fmod(pk.time_left, 0.5) < 0.25: col = Color(1, 0.15, 0.1)
		draw_circle(c, r + 4, Color(0, 0, 0, 0.55))
		draw_arc(c, r, 0, TAU, 48, Color(col, 0.22), 8.0, true)
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * clampf(shown_frac, 0, 1), 48, col, 8.0, true)
		draw_string(f, c + Vector2(-40, 14), d.icon, HORIZONTAL_ALIGNMENT_CENTER, 80, 38, Color.WHITE)
		draw_string(f, c + Vector2(r + 12, -6), d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		draw_string(f, c + Vector2(r + 12, 22), "%.1fs" % pk.time_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE if not pk.warning() else Color(1, 0.3, 0.25))
		for p in pops:
			var a: float = 1.0 - p.age / 1.1
			draw_string(f, c + Vector2(r + 12, -34 - p.age * 40.0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 1.0, 0.5, a))
	var bag: Backpack = game.player.backpack if game.player else null
	if bag == null: return
	var o := bag_origin()
	for i in Backpack.SLOTS:
		var rr := Rect2(o + Vector2(i * 66, 0), Vector2(58, 58))
		draw_rect(rr, Color(0.02, 0.05, 0.08, 0.6))
		var s: Dictionary = bag.slots[i]
		var edge := Color(0.4, 0.9, 1.0, 0.9) if i == bag.selected else Color(0.6, 0.7, 0.8, 0.45)
		draw_rect(rr, edge, false, 2.0)
		if not s.is_empty():
			var gd: Dictionary = Backpack.GADGETS[s.id]
			draw_string(f, rr.position + Vector2(0, 42), gd.icon, HORIZONTAL_ALIGNMENT_CENTER, 58, 34, gd.color)
			if s.count > 1: draw_string(f, rr.position + Vector2(36, 56), "x%d" % s.count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_string(f, rr.position + Vector2(4, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.9, 0.7))
	var g = game
	if g.aegis.up():
		draw_string(f, o + Vector2(0, -12), "AEGIS %.0fs · %d hits" % [g.aegis.time_left, g.aegis.hits_left], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.85, 1.0))
