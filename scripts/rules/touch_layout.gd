class_name TouchLayout
## v7 touch HUD layout. A big FIRE button bottom-right with ADS / reload / jump / crouch / grenade /
## swap / knife / skill on a thumb-reachable arc around it, the contextual USE (buy/interact) above
## the arc, optional left-side FIRE, sprint above the move zone, pause top-centre. Everything is laid
## out inside the device safe area (notches, rounded corners, gesture bar) and scales with
## [code]scale[/code]. Players can drag any button in Settings > Controls; those positions are stored
## as fractions of the safe area and re-clamped/de-overlapped on every layout.

const HIT_PAD := 1.15  ## touch hit area is a bit bigger than the drawn circle
const MARGIN := 10.0   ## px (at 720p) kept clear of the safe-area edge
## name: [ring, angle in degrees (0 = right, 90 = up), radius @720p]
const ARC := {
	"ads": [1, 184.0, 52.0],
	"reload": [1, 146.0, 46.0],
	"jump": [1, 108.0, 48.0],
	"crouch": [1, 72.0, 42.0],
	"use": [2, 192.0, 46.0],      # contextual buy/interact: only drawn when something is in reach
	"grenade": [2, 164.0, 40.0],
	"swap": [2, 136.0, 42.0],
	"knife": [2, 108.0, 38.0],
	"skill": [2, 80.0, 40.0],
	"gadget": [2, 52.0, 38.0],   # v7.13 backpack: use selected gadget
}
const ORDER := ["fire", "fire_l", "ads", "reload", "jump", "crouch", "grenade", "swap", "knife", "skill", "gadget", "use", "sprint", "pause"]

## Returns name -> [center, radius] in pixels.
## [param s] screen size, [param safe] safe-area rect in the same pixels, [param scale] button size
## multiplier (0.7-1.4), [param fire_scale] FIRE size, [param left_fire] add the left FIRE,
## [param custom] name -> Vector2 fraction of the safe rect (from the layout editor).
static func buttons(s: Vector2, safe := Rect2(), scale := 1.0, fire_scale := 1.3, left_fire := false, custom := {}) -> Dictionary:
	if safe.size == Vector2.ZERO: safe = Rect2(Vector2.ZERO, s)
	var u := s.y / 720.0
	var k := u * scale
	var out := {}
	# auto-fit: on short screens / huge settings shrink until the arc fits without overlaps
	for _i in 12:
		out = _arc(s, safe, k, fire_scale, left_fire)
		if overlaps(out).is_empty() and _fits(out, safe, MARGIN * u): break
		k *= 0.93
	for n in custom:
		if out.has(n) and custom[n] is Vector2:
			out[n][0] = safe.position + safe.size * (custom[n] as Vector2)
	clamp_to_safe(out, safe, MARGIN * u)
	return out

static func _ring(ring_min: float, ring: int) -> float:
	# smallest radius at which neighbours on this ring don't touch (chord >= padded radii)
	var keys := []
	for n in ARC:
		if ARC[n][0] == ring: keys.append(n)
	var need := ring_min
	for i in keys.size() - 1:
		var x: Array = ARC[keys[i]]; var y: Array = ARC[keys[i + 1]]
		var half := deg_to_rad(absf(x[1] - y[1])) / 2.0
		need = maxf(need, (x[2] + y[2]) * HIT_PAD / (2.0 * sin(half)) + 4.0)
	return need

static func _arc(s: Vector2, safe: Rect2, k: float, fire_scale: float, left_fire: bool) -> Dictionary:
	var rf := 78.0 * fire_scale * k
	var r1 := maxf(_ring(0.0, 1) * k, rf * HIT_PAD + 52.0 * k * HIT_PAD + 6.0 * k)
	var r2 := maxf(_ring(0.0, 2) * k, r1 + (52.0 + 46.0) * k * HIT_PAD + 8.0 * k)
	var out := {"fire": [Vector2.ZERO, rf]}
	for n in ARC:
		var d: Array = ARC[n]
		var a := deg_to_rad(d[1])
		out[n] = [Vector2(cos(a), -sin(a)) * (r1 if d[0] == 1 else r2), d[2] * k]
	# anchor the cluster so its right/bottom extents sit just inside the safe area
	var ex := 0.0; var ey := 0.0
	for n in out:
		ex = maxf(ex, out[n][0].x + out[n][1] * HIT_PAD); ey = maxf(ey, out[n][0].y + out[n][1] * HIT_PAD)
	var m := MARGIN * s.y / 720.0 + 2.0
	var fc := Vector2(safe.end.x - ex - m - 14.0 * k, safe.end.y - ey - m - 12.0 * k)
	for n in out: out[n][0] += fc
	out["sprint"] = [Vector2(safe.position.x + 230.0 * k, safe.end.y - 320.0 * k), 38.0 * k]
	out["pause"] = [safe.position + Vector2.ONE * (26.0 * k * HIT_PAD + m + 6.0 * k), 26.0 * k]
	if left_fire:
		out["fire_l"] = [Vector2(safe.position.x + 52.0 * k * HIT_PAD + m + 40.0 * k, safe.position.y + safe.size.y * 0.4), 52.0 * k]
	return out

static func _fits(b: Dictionary, safe: Rect2, pad: float) -> bool:
	for n in b:
		var r: float = b[n][1] * HIT_PAD + pad
		var c: Vector2 = b[n][0]
		if c.x - r < safe.position.x or c.y - r < safe.position.y or c.x + r > safe.end.x or c.y + r > safe.end.y: return false
	return true

## Push every button fully inside the safe rect (keeping [param pad] px of breathing room).
static func clamp_to_safe(b: Dictionary, safe: Rect2, pad := 0.0) -> void:
	for n in b:
		var r: float = b[n][1] * HIT_PAD + pad
		var c: Vector2 = b[n][0]
		b[n][0] = Vector2(clampf(c.x, safe.position.x + r, safe.end.x - r), clampf(c.y, safe.position.y + r, safe.end.y - r))

## Pairs of buttons whose touch areas overlap (should be empty).
static func overlaps(b: Dictionary) -> Array:
	var bad := []
	var names := b.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var x: Array = b[names[i]]; var y: Array = b[names[j]]
			if x[0].distance_to(y[0]) < (x[1] + y[1]) * HIT_PAD: bad.append([names[i], names[j]])
	return bad

## Buttons whose (padded) touch area leaves the safe rect (should be empty).
static func outside_safe(b: Dictionary, safe: Rect2) -> Array:
	var bad := []
	for n in b:
		var r: float = b[n][1] * HIT_PAD
		var c: Vector2 = b[n][0]
		if c.x - r < safe.position.x - 0.5 or c.y - r < safe.position.y - 0.5 or c.x + r > safe.end.x + 0.5 or c.y + r > safe.end.y + 0.5:
			bad.append(n)
	return bad

## True when moving [param name] to [param center] would not overlap any other button (editor drop check).
static func can_place(b: Dictionary, name: String, center: Vector2) -> bool:
	for n in b:
		if n == name: continue
		if center.distance_to(b[n][0]) < (b[n][1] + b[name][1]) * HIT_PAD: return false
	return true

## Simulated safe area for a phone of the given aspect (landscape): notch on the left, gesture bar at the bottom.
static func phone_safe(s: Vector2, notch := 0.0, bottom := 0.0) -> Rect2:
	return Rect2(Vector2(notch, 0), Vector2(s.x - notch * 2.0, s.y - bottom))
